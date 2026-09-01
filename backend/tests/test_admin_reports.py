import uuid
from datetime import datetime, timedelta, timezone
from types import SimpleNamespace
from unittest.mock import MagicMock

import pytest
from fastapi.testclient import TestClient
from sqlalchemy.exc import SQLAlchemyError

from app.api.deps import AuthenticatedUser, get_current_user, get_db
from app.main import app
from app.models.enums import ReportStatus, UserRole
from app.routers.reports import MAX_REPORT_OFFSET

client = TestClient(app)


@pytest.fixture(autouse=True)
def clear_overrides():
    yield
    app.dependency_overrides.clear()


def _user_and_profile(role=UserRole.admin, *, profile=True):
    user = AuthenticatedUser(id=uuid.uuid4(), email="admin@example.com")
    app.dependency_overrides[get_current_user] = lambda: user
    resolved = None
    if profile:
        resolved = SimpleNamespace(id=user.id, role=role)
    return user, resolved


def _report(*, kind="post", status=ReportStatus.pending, created_at=None):
    target_id = uuid.uuid4()
    now = created_at or datetime.now(timezone.utc)
    report = SimpleNamespace(
        id=uuid.uuid4(),
        post_id=target_id if kind == "post" else None,
        comment_id=target_id if kind == "comment" else None,
        reason="Unsafe medical advice",
        status=status,
        created_at=now,
        updated_at=now,
    )
    post = (
        SimpleNamespace(
            id=target_id, title="Post title", body="Post body", is_hidden=False
        )
        if kind == "post"
        else None
    )
    comment = (
        SimpleNamespace(
            id=target_id, body="Comment body", post_id=None, is_hidden=False
        )
        if kind == "comment"
        else None
    )
    parent = (
        SimpleNamespace(id=uuid.uuid4(), title="Parent post")
        if kind == "comment"
        else None
    )
    if comment is not None:
        comment.post_id = parent.id
    return report, post, comment, parent


def _list_db(profile, rows):
    db = MagicMock()
    db.get.return_value = profile
    db.execute.return_value.all.return_value = rows
    app.dependency_overrides[get_db] = lambda: db
    return db


def _update_db(profile, report, context_row):
    db = MagicMock()
    db.get.return_value = profile
    preliminary = MagicMock()
    preliminary.scalar_one_or_none.return_value = report
    target = context_row[1] if report.post_id is not None else context_row[2]
    target_lock = MagicMock()
    target_lock.scalar_one_or_none.return_value = target
    report_lock = MagicMock()
    report_lock.scalar_one_or_none.return_value = report
    context = MagicMock()
    context.one.return_value = context_row
    context.one_or_none.return_value = context_row
    if report.post_id is not None:
        db.execute.side_effect = [
            preliminary,
            target_lock,
            report_lock,
            context,
            context,
        ]
    else:
        discovery = MagicMock()
        discovery.scalar_one_or_none.return_value = target
        parent_lock = MagicMock()
        parent_lock.scalar_one_or_none.return_value = context_row[3]
        db.execute.side_effect = [
            preliminary,
            discovery,
            parent_lock,
            target_lock,
            report_lock,
            context,
            context,
        ]
    app.dependency_overrides[get_db] = lambda: db
    return db


def test_get_reports_requires_authentication():
    assert client.get("/reports").status_code == 401


@pytest.mark.parametrize("profile", [None, SimpleNamespace(role=UserRole.parent)])
def test_get_reports_requires_admin_profile(profile):
    user, _ = _user_and_profile()
    if profile is not None:
        profile.id = user.id
    _list_db(profile, [])

    assert client.get("/reports").status_code == 403


def test_get_reports_defaults_to_pending_and_has_deterministic_order():
    _, profile = _user_and_profile()
    db = _list_db(profile, [])

    assert client.get("/reports").json() == []

    sql = str(db.execute.call_args.args[0]).lower()
    assert "reports.status =" in sql
    assert "order by reports.created_at desc, reports.id desc" in sql
    assert "limit" in sql and "offset" in sql


@pytest.mark.parametrize("value", ["pending", "reviewed", "dismissed"])
def test_get_reports_accepts_each_status_filter(value):
    _, profile = _user_and_profile()
    _list_db(profile, [])

    assert client.get("/reports", params={"status": value}).status_code == 200


def test_get_reports_rejects_unknown_status_and_unbounded_pagination():
    _, profile = _user_and_profile()
    _list_db(profile, [])

    assert client.get("/reports", params={"status": "open"}).status_code == 422
    assert client.get("/reports", params={"limit": 101}).status_code == 422
    assert client.get("/reports", params={"limit": 0}).status_code == 422
    assert client.get("/reports", params={"offset": -1}).status_code == 422


def test_get_reports_accepts_maximum_offset_and_rejects_one_above():
    _, profile = _user_and_profile()
    _list_db(profile, [])

    assert (
        client.get("/reports", params={"offset": MAX_REPORT_OFFSET}).status_code
        == 200
    )
    assert (
        client.get(
            "/reports", params={"offset": MAX_REPORT_OFFSET + 1}
        ).status_code
        == 422
    )


def test_get_reports_serializes_safe_post_context_only():
    _, profile = _user_and_profile()
    _list_db(profile, [_report(kind="post")])

    data = client.get("/reports").json()[0]

    assert data["target_kind"] == "post"
    assert data["target_is_hidden"] is False
    assert data["target_id"] == data["post"]["id"]
    assert data["post"]["title"] == "Post title"
    assert data["comment"] is None
    for private_field in ("reported_by", "reporter", "email", "report_count"):
        assert private_field not in data


def test_get_reports_serializes_comment_and_parent_post_context():
    _, profile = _user_and_profile()
    row = _report(kind="comment")
    _list_db(profile, [row])

    data = client.get("/reports").json()[0]

    assert data["target_kind"] == "comment"
    assert data["target_is_hidden"] is False
    assert data["comment"] == {
        "id": str(row[2].id),
        "body": "Comment body",
        "post_id": str(row[3].id),
        "post_title": "Parent post",
    }
    assert data["post"] is None


@pytest.mark.parametrize(
    "row",
    [
        lambda: (_report(kind="post")[0], None, None, None),
        lambda: (_report(kind="comment")[0], None, None, None),
        lambda: (lambda item: (item[0], None, item[2], None))(
            _report(kind="comment")
        ),
    ],
    ids=["missing-post", "missing-comment", "missing-parent-post"],
)
def test_get_reports_omits_invalid_target_context_without_failing_queue(row):
    _, profile = _user_and_profile()
    _list_db(profile, [row()])

    response = client.get("/reports")

    assert response.status_code == 200
    assert response.json() == []


@pytest.mark.parametrize("resulting", [ReportStatus.reviewed, ReportStatus.dismissed])
def test_pending_report_can_transition_to_terminal_status(resulting):
    _, profile = _user_and_profile()
    row = _report(status=ReportStatus.pending)
    db = _update_db(profile, row[0], row)

    response = client.put(
        f"/reports/{row[0].id}/status", json={"status": resulting.value}
    )

    assert response.status_code == 200
    assert response.json()["status"] == resulting.value
    assert row[0].status == resulting
    assert row[1].is_hidden is False
    db.commit.assert_called_once_with()


@pytest.mark.parametrize("terminal", [ReportStatus.reviewed, ReportStatus.dismissed])
def test_repeating_terminal_status_is_idempotent_without_mutation(terminal):
    _, profile = _user_and_profile()
    row = _report(status=terminal)
    db = _update_db(profile, row[0], row)

    response = client.put(
        f"/reports/{row[0].id}/status", json={"status": terminal.value}
    )

    assert response.status_code == 200
    db.commit.assert_not_called()


@pytest.mark.parametrize(
    ("current", "requested"),
    [
        (ReportStatus.pending, ReportStatus.pending),
        (ReportStatus.reviewed, ReportStatus.dismissed),
        (ReportStatus.reviewed, ReportStatus.pending),
        (ReportStatus.dismissed, ReportStatus.reviewed),
        (ReportStatus.dismissed, ReportStatus.pending),
    ],
)
def test_other_status_transitions_return_409_without_commit(current, requested):
    _, profile = _user_and_profile()
    row = _report(status=current)
    db = _update_db(profile, row[0], row)

    response = client.put(
        f"/reports/{row[0].id}/status", json={"status": requested.value}
    )

    assert response.status_code == 409
    db.commit.assert_not_called()


def test_update_missing_report_returns_404():
    _, profile = _user_and_profile()
    db = MagicMock()
    db.get.return_value = profile
    db.execute.return_value.scalar_one_or_none.return_value = None
    app.dependency_overrides[get_db] = lambda: db

    response = client.put(
        f"/reports/{uuid.uuid4()}/status", json={"status": "reviewed"}
    )

    assert response.status_code == 404
    db.commit.assert_not_called()


def test_update_status_requires_authentication():
    response = client.put(
        f"/reports/{uuid.uuid4()}/status", json={"status": "reviewed"}
    )

    assert response.status_code == 401


@pytest.mark.parametrize("profile", [None, SimpleNamespace(role=UserRole.parent)])
def test_update_status_requires_admin_profile(profile):
    user, _ = _user_and_profile()
    if profile is not None:
        profile.id = user.id
    _list_db(profile, [])

    response = client.put(
        f"/reports/{uuid.uuid4()}/status", json={"status": "reviewed"}
    )

    assert response.status_code == 403


@pytest.mark.parametrize(
    "invalid_row",
    [
        lambda row: (row[0], None, None, None),
        lambda row: (row[0], None, None, row[3]),
        lambda row: (row[0], None, row[2], None),
    ],
    ids=["missing-target", "missing-comment", "missing-parent-post"],
)
def test_update_does_not_mutate_or_commit_invalid_target_context(invalid_row):
    _, profile = _user_and_profile()
    row = _report(kind="comment")
    db = _update_db(profile, row[0], invalid_row(row))

    response = client.put(
        f"/reports/{row[0].id}/status", json={"status": "reviewed"}
    )

    assert response.status_code == 409
    assert row[0].status == ReportStatus.pending
    db.flush.assert_not_called()
    db.commit.assert_not_called()


def test_update_does_not_mutate_or_commit_when_post_target_is_missing():
    _, profile = _user_and_profile()
    row = _report(kind="post")
    db = _update_db(profile, row[0], (row[0], None, None, None))

    response = client.put(
        f"/reports/{row[0].id}/status", json={"status": "reviewed"}
    )

    assert response.status_code == 409
    assert row[0].status == ReportStatus.pending
    db.commit.assert_not_called()


def test_update_rejects_mutually_inconsistent_target_state_before_mutation():
    _, profile = _user_and_profile()
    row = _report(kind="post")
    row[0].comment_id = uuid.uuid4()
    db = _update_db(profile, row[0], row)

    response = client.put(
        f"/reports/{row[0].id}/status", json={"status": "dismissed"}
    )

    assert response.status_code == 409
    assert row[0].status == ReportStatus.pending
    db.commit.assert_not_called()


def test_update_rolls_back_when_commit_fails():
    _, profile = _user_and_profile()
    row = _report(status=ReportStatus.pending)
    db = _update_db(profile, row[0], row)
    db.commit.side_effect = SQLAlchemyError("commit failed")

    with pytest.raises(SQLAlchemyError, match="commit failed"):
        client.put(
            f"/reports/{row[0].id}/status", json={"status": "reviewed"}
        )

    db.flush.assert_called_once_with()
    db.rollback.assert_called_once_with()


@pytest.mark.parametrize(
    "payload",
    [{}, {"status": "unknown"}, {"status": "reviewed", "reported_by": "x"}],
)
def test_update_status_validates_body(payload):
    _, profile = _user_and_profile()
    _list_db(profile, [])

    assert client.put(f"/reports/{uuid.uuid4()}/status", json=payload).status_code == 422


def test_status_decision_query_requests_row_lock():
    _, profile = _user_and_profile()
    row = _report(status=ReportStatus.reviewed)
    db = _update_db(profile, row[0], row)

    client.put(f"/reports/{row[0].id}/status", json={"status": "reviewed"})

    sql = [str(call.args[0]).lower() for call in db.execute.call_args_list]
    assert "for update" not in sql[0]
    assert "from posts" in sql[1] and "for update" in sql[1]
    assert "from reports" in sql[2] and "for update" in sql[2]


def test_comment_status_executes_post_then_comment_then_report_locks():
    _, profile = _user_and_profile()
    row = _report(kind="comment", status=ReportStatus.reviewed)
    db = _update_db(profile, row[0], row)

    response = client.put(
        f"/reports/{row[0].id}/status", json={"status": "reviewed"}
    )

    assert response.status_code == 200
    sql = [str(call.args[0]).lower() for call in db.execute.call_args_list]
    assert "from reports" in sql[0] and "for update" not in sql[0]
    assert "from comments" in sql[1] and "for update" not in sql[1]
    assert "from posts" in sql[2] and "for update" in sql[2]
    assert "from comments" in sql[3] and "for update" in sql[3]
    assert "from reports" in sql[4] and "for update" in sql[4]


@pytest.mark.parametrize(("kind", "hidden"), [("post", True), ("comment", False)])
def test_admin_can_hide_or_restore_target_without_changing_report_status(kind, hidden):
    _, profile = _user_and_profile()
    row = _report(kind=kind, status=ReportStatus.reviewed)
    target = row[1] if kind == "post" else row[2]
    target.is_hidden = not hidden
    if kind == "comment":
        row[3].comment_count = 9
    db = _update_db(profile, row[0], row)
    db.scalar.return_value = 4

    response = client.put(
        f"/reports/{row[0].id}/target-visibility",
        json={"is_hidden": hidden},
    )

    assert response.status_code == 200
    assert response.json()["target_is_hidden"] is hidden
    assert response.json()["status"] == "reviewed"
    assert target.is_hidden is hidden
    assert row[0].status == ReportStatus.reviewed
    if kind == "comment":
        assert row[3].comment_count == 4
        count_sql = str(db.scalar.call_args.args[0]).lower()
        assert "comments.is_hidden is false" in count_sql
    else:
        db.scalar.assert_not_called()
    db.commit.assert_called_once_with()


@pytest.mark.parametrize("kind", ["post", "comment"])
def test_visibility_lock_order_is_target_first_and_report_last(kind):
    _, profile = _user_and_profile()
    row = _report(kind=kind)
    db = _update_db(profile, row[0], row)

    response = client.put(
        f"/reports/{row[0].id}/target-visibility",
        json={"is_hidden": True},
    )

    assert response.status_code == 200
    sql = [str(call.args[0]).lower() for call in db.execute.call_args_list]
    assert "for update" not in sql[0]
    if kind == "post":
        assert "from posts" in sql[1] and "for update" in sql[1]
        assert "from reports" in sql[2] and "for update" in sql[2]
    else:
        assert "for update" not in sql[1]
        assert "from posts" in sql[2] and "for update" in sql[2]
        assert "from comments" in sql[3] and "for update" in sql[3]
        assert "from reports" in sql[4] and "for update" in sql[4]


def test_repeating_visibility_is_idempotent_without_commit_or_recount():
    _, profile = _user_and_profile()
    row = _report(kind="comment")
    row[2].is_hidden = True
    db = _update_db(profile, row[0], row)

    response = client.put(
        f"/reports/{row[0].id}/target-visibility",
        json={"is_hidden": True},
    )

    assert response.status_code == 200
    assert response.json()["target_is_hidden"] is True
    db.flush.assert_not_called()
    db.scalar.assert_not_called()
    db.commit.assert_not_called()


def test_comment_visibility_commit_failure_invokes_rollback_without_success():
    _, profile = _user_and_profile()
    row = _report(kind="comment")
    row[3].comment_count = 7
    db = _update_db(profile, row[0], row)
    db.scalar.return_value = 3
    db.commit.side_effect = SQLAlchemyError("commit failed")

    with pytest.raises(SQLAlchemyError, match="commit failed"):
        client.put(
            f"/reports/{row[0].id}/target-visibility",
            json={"is_hidden": True},
        )

    assert row[2].is_hidden is True
    assert row[3].comment_count == 3
    assert db.flush.call_count == 2
    assert db.scalar.call_count == 1
    db.commit.assert_called_once_with()
    db.rollback.assert_called_once_with()


def test_visibility_requires_authentication_and_strict_body():
    report_id = uuid.uuid4()
    assert client.put(
        f"/reports/{report_id}/target-visibility", json={"is_hidden": True}
    ).status_code == 401

    _, profile = _user_and_profile()
    _list_db(profile, [])
    assert client.put(
        f"/reports/{report_id}/target-visibility", json={}
    ).status_code == 422
    assert client.put(
        f"/reports/{report_id}/target-visibility",
        json={"is_hidden": True, "status": "reviewed"},
    ).status_code == 422


def test_visibility_revalidates_report_target_after_locking():
    _, profile = _user_and_profile()
    row = _report(kind="post")
    original_target = row[1]
    locked_report = SimpleNamespace(**vars(row[0]))
    locked_report.post_id = uuid.uuid4()
    preliminary = MagicMock()
    preliminary.scalar_one_or_none.return_value = row[0]
    target_lock = MagicMock()
    target_lock.scalar_one_or_none.return_value = original_target
    report_lock = MagicMock()
    report_lock.scalar_one_or_none.return_value = locked_report
    db = MagicMock()
    db.get.return_value = profile
    db.execute.side_effect = [preliminary, target_lock, report_lock]
    app.dependency_overrides[get_db] = lambda: db

    response = client.put(
        f"/reports/{row[0].id}/target-visibility", json={"is_hidden": True}
    )

    assert response.status_code == 409
    assert original_target.is_hidden is False
    db.flush.assert_not_called()
    db.commit.assert_not_called()
