import uuid
from unittest.mock import MagicMock

import pytest
from fastapi.testclient import TestClient
from sqlalchemy.exc import IntegrityError

from app.api.deps import AuthenticatedUser, get_current_user, get_db
from app.main import app
from app.models.comment import Comment
from app.models.post import Post
from app.models.profile import Profile
from app.models.report import Report


client = TestClient(app)


@pytest.fixture(autouse=True)
def clear_overrides():
    yield
    app.dependency_overrides.clear()


def _result(value):
    result = MagicMock()
    result.scalar_one_or_none.return_value = value
    return result


def report_db(*, target_type="post", target=True, profile=True, existing=None, count=1):
    user = AuthenticatedUser(id=uuid.uuid4(), email="parent@example.com")
    app.dependency_overrides[get_current_user] = lambda: user
    db = MagicMock()
    stored_target = MagicMock(spec=Post if target_type == "post" else Comment) if target else None
    if stored_target is not None:
        stored_target.id = uuid.uuid4()
        stored_target.report_count = 0
        if target_type == "comment":
            stored_target.post_id = uuid.uuid4()
    stored_profile = MagicMock(spec=Profile) if profile else None
    if stored_profile is not None:
        stored_profile.id = user.id
    if target_type == "comment" and stored_target is not None:
        parent = MagicMock(spec=Post)
        parent.id = stored_target.post_id
        db.execute.side_effect = [
            _result(parent),
            _result(stored_target),
            _result(existing),
        ]
    else:
        db.execute.side_effect = [_result(stored_target), _result(existing)]
    db.get.return_value = stored_profile
    db.scalar.return_value = count
    app.dependency_overrides[get_db] = lambda: db
    return user, db, stored_target


def test_post_report_creates_server_owned_report_and_authoritative_count():
    user, db, post = report_db(count=4)

    response = client.put(
        f"/posts/{post.id}/report", json={"reason": "  Unsafe advice  "}
    )

    assert response.status_code == 200
    report = db.add.call_args.args[0]
    assert isinstance(report, Report)
    assert report.post_id == post.id
    assert report.comment_id is None
    assert report.reported_by == user.id
    assert report.reason == "Unsafe advice"
    assert response.json() == {"reported": True, "report_count": 4}
    assert post.report_count == 4
    assert "for update" in str(db.execute.call_args_list[0].args[0]).lower()
    assert "count(" in str(db.scalar.call_args.args[0]).lower()
    db.flush.assert_called_once_with()
    db.commit.assert_called_once_with()


def test_post_report_executes_advisory_then_post_lock_then_report_lookup():
    _, db, post = report_db()
    timeline = MagicMock()
    timeline.attach_mock(db.connection.return_value.exec_driver_sql, "advisory")
    timeline.attach_mock(db.execute, "execute")

    response = client.put(
        f"/posts/{post.id}/report", json={"reason": "Reason"}
    )

    assert response.status_code == 200
    sql = [str(call.args[0]).lower() for call in db.execute.call_args_list]
    assert "from posts" in sql[0] and "for update" in sql[0]
    assert "from reports" in sql[1]
    assert "for update" not in sql[1]
    assert [call[0] for call in timeline.method_calls[:3]] == [
        "advisory",
        "execute",
        "execute",
    ]


def test_duplicate_post_report_updates_reason_without_creating_row():
    existing = MagicMock(spec=Report)
    _, db, post = report_db(existing=existing, count=1)

    response = client.put(
        f"/posts/{post.id}/report", json={"reason": "Updated reason"}
    )

    assert response.status_code == 200
    assert response.json()["report_count"] == 1
    assert existing.reason == "Updated reason"
    db.add.assert_not_called()


@pytest.mark.parametrize("payload", [
    {"reason": ""},
    {"reason": "   "},
    {"reason": "x" * 501},
    {"reason": "valid", "reported_by": str(uuid.uuid4())},
])
def test_report_reason_validation(payload):
    user = AuthenticatedUser(id=uuid.uuid4(), email="parent@example.com")
    app.dependency_overrides[get_current_user] = lambda: user

    response = client.put(f"/posts/{uuid.uuid4()}/report", json=payload)

    assert response.status_code == 422


def test_post_report_requires_authentication():
    response = client.put(
        f"/posts/{uuid.uuid4()}/report", json={"reason": "Reason"}
    )
    assert response.status_code == 401


def test_post_report_returns_404_for_missing_or_unpublished_post():
    _, db, _ = report_db(target=False)

    response = client.put(
        f"/posts/{uuid.uuid4()}/report", json={"reason": "Reason"}
    )

    assert response.status_code == 404
    assert db.get.call_count == 1  # deletion check runs before target lookup
    db.commit.assert_not_called()


def test_post_report_hidden_target_uses_generic_not_found_without_mutation():
    _, db, _ = report_db(target=False)

    response = client.put(
        f"/posts/{uuid.uuid4()}/report", json={"reason": "Reason"}
    )

    assert response.status_code == 404
    assert response.json() == {"detail": "Post not found"}
    assert "is_hidden is false" in str(db.execute.call_args.args[0]).lower()
    db.add.assert_not_called()
    db.commit.assert_not_called()


def test_report_returns_409_without_profile():
    _, db, post = report_db(profile=False)

    response = client.put(
        f"/posts/{post.id}/report", json={"reason": "Reason"}
    )

    assert response.status_code == 409
    assert response.json()["detail"] == (
        "A Profile is required before reporting community content."
    )
    db.commit.assert_not_called()


def test_comment_report_validates_parent_and_creates_report():
    user, db, comment = report_db(target_type="comment", count=2)
    post_id = comment.post_id

    response = client.put(
        f"/posts/{post_id}/comments/{comment.id}/report",
        json={"reason": "Harassment"},
    )

    assert response.status_code == 200
    report = db.add.call_args.args[0]
    assert report.comment_id == comment.id
    assert report.post_id is None
    assert report.reported_by == user.id
    assert response.json() == {"reported": True, "report_count": 2}
    post_sql = str(db.execute.call_args_list[0].args[0]).lower()
    comment_sql = str(db.execute.call_args_list[1].args[0]).lower()
    assert "posts.is_published is true" in post_sql
    assert "posts.is_hidden is false" in post_sql
    assert "comments.post_id" in comment_sql
    assert "comments.is_hidden is false" in comment_sql
    assert "for update" in post_sql and "for update" in comment_sql


def test_comment_report_executes_advisory_post_comment_then_report_lookup():
    _, db, comment = report_db(target_type="comment")
    timeline = MagicMock()
    timeline.attach_mock(db.connection.return_value.exec_driver_sql, "advisory")
    timeline.attach_mock(db.execute, "execute")

    response = client.put(
        f"/posts/{comment.post_id}/comments/{comment.id}/report",
        json={"reason": "Reason"},
    )

    assert response.status_code == 200
    sql = [str(call.args[0]).lower() for call in db.execute.call_args_list]
    assert "from posts" in sql[0] and "for update" in sql[0]
    assert "from comments" in sql[1] and "for update" in sql[1]
    assert "from reports" in sql[2]
    assert "for update" not in sql[2]
    assert [call[0] for call in timeline.method_calls[:4]] == [
        "advisory",
        "execute",
        "execute",
        "execute",
    ]


@pytest.mark.parametrize("case", ["missing_parent", "unpublished_parent", "missing_comment", "wrong_parent"])
def test_comment_report_returns_404_when_target_query_finds_nothing(case):
    _, db, _ = report_db(target_type="comment", target=False)

    response = client.put(
        f"/posts/{uuid.uuid4()}/comments/{uuid.uuid4()}/report",
        json={"reason": "Reason"},
    )

    assert response.status_code == 404
    assert db.get.call_count == 1  # deletion check runs before target locks
    db.commit.assert_not_called()


def test_comment_report_hidden_parent_uses_generic_comment_not_found():
    _, db, _ = report_db(target_type="comment", target=False)

    response = client.put(
        f"/posts/{uuid.uuid4()}/comments/{uuid.uuid4()}/report",
        json={"reason": "Reason"},
    )

    assert response.status_code == 404
    assert response.json() == {"detail": "Comment not found"}
    assert "posts.is_hidden is false" in str(db.execute.call_args.args[0]).lower()
    assert db.execute.call_count == 1
    db.add.assert_not_called()
    db.commit.assert_not_called()


def test_comment_report_hidden_comment_uses_generic_not_found_without_mutation():
    user = AuthenticatedUser(id=uuid.uuid4(), email="parent@example.com")
    app.dependency_overrides[get_current_user] = lambda: user
    parent = MagicMock(spec=Post)
    parent.id = uuid.uuid4()
    db = MagicMock()
    db.execute.side_effect = [_result(parent), _result(None)]
    app.dependency_overrides[get_db] = lambda: db

    response = client.put(
        f"/posts/{parent.id}/comments/{uuid.uuid4()}/report",
        json={"reason": "Reason"},
    )

    assert response.status_code == 404
    assert response.json() == {"detail": "Comment not found"}
    comment_sql = str(db.execute.call_args_list[1].args[0]).lower()
    assert "comments.is_hidden is false" in comment_sql
    assert db.get.call_count == 1  # deletion check runs before target locks
    db.add.assert_not_called()
    db.commit.assert_not_called()


def test_duplicate_comment_report_is_idempotent():
    existing = MagicMock(spec=Report)
    _, db, comment = report_db(
        target_type="comment", existing=existing, count=1
    )

    response = client.put(
        f"/posts/{comment.post_id}/comments/{comment.id}/report",
        json={"reason": "Updated"},
    )

    assert response.json() == {"reported": True, "report_count": 1}
    assert existing.reason == "Updated"
    db.add.assert_not_called()


def test_report_rolls_back_integrity_error():
    _, db, post = report_db()
    db.flush.side_effect = IntegrityError("statement", {}, Exception("db"))

    response = client.put(
        f"/posts/{post.id}/report", json={"reason": "Reason"}
    )

    assert response.status_code == 409
    assert response.json()["detail"] == (
        "The report could not be submitted because of a data conflict."
    )
    db.rollback.assert_called_once_with()
