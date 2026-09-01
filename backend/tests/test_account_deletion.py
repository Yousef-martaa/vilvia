import uuid
from datetime import datetime, timezone
from types import SimpleNamespace
from unittest.mock import MagicMock

import httpx
import pytest
from fastapi import HTTPException
from fastapi.testclient import TestClient
from pydantic import ValidationError
from sqlalchemy.exc import IntegrityError

from app.api.deps import (
    AuthenticatedUser,
    ensure_account_active,
    get_current_user,
    get_db,
)
from app.core.settings import Settings
from app.main import app
from app.models.account_deletion_request import AccountDeletionRequest
from app.models.enums import AccountDeletionStatus, UserRole
from app.services import account_deletion as service
from app.services.account_deletion import fulfill_account_deletion
from app.services.supabase_admin import (
    SupabaseAuthAdmin,
    SupabaseAuthDeletionError,
)


client = TestClient(app)


@pytest.fixture(autouse=True)
def clear_overrides():
    yield
    app.dependency_overrides.clear()


def _request(user_id, status=AccountDeletionStatus.requested):
    now = datetime.now(timezone.utc)
    return SimpleNamespace(
        user_id=user_id,
        status=status,
        requested_at=now,
        auth_deleted_at=None,
        completed_at=None,
    )


def test_signed_in_user_can_request_deletion_idempotently():
    user = AuthenticatedUser(id=uuid.uuid4(), email="not-returned@example.com")
    app.dependency_overrides[get_current_user] = lambda: user
    deletion_request = _request(user.id)
    db = MagicMock()
    db.execute.return_value.scalar_one.return_value = deletion_request
    app.dependency_overrides[get_db] = lambda: db

    response = client.post("/me/account-deletion-request")

    assert response.status_code == 202
    assert response.json() == {
        "status": "requested",
        "requested_at": deletion_request.requested_at.isoformat().replace(
            "+00:00", "Z"
        ),
    }
    insert = db.execute.call_args_list[0].args[0]
    compiled = str(insert.compile()).upper()
    assert "ON CONFLICT" in compiled
    assert "RETURNING" in compiled
    assert insert.compile().params["user_id"] == user.id
    db.commit.assert_called_once_with()
    db.execute.assert_called_once()
    advisory = db.connection.return_value.exec_driver_sql
    advisory.assert_called_once()
    assert "pg_advisory_xact_lock" in advisory.call_args.args[0]
    assert "email" not in response.text.lower()


def test_deletion_request_requires_authentication():
    assert client.post("/me/account-deletion-request").status_code == 401


def test_deletion_request_rejects_client_controlled_fields():
    user = AuthenticatedUser(id=uuid.uuid4(), email="private@example.com")
    app.dependency_overrides[get_current_user] = lambda: user

    response = client.post(
        "/me/account-deletion-request",
        json={"user_id": str(uuid.uuid4()), "status": "completed"},
    )

    assert response.status_code == 422


def test_repeating_request_returns_the_existing_lifecycle_state():
    user = AuthenticatedUser(id=uuid.uuid4(), email="private@example.com")
    app.dependency_overrides[get_current_user] = lambda: user
    existing = _request(user.id, AccountDeletionStatus.auth_deleted)
    existing.auth_deleted_at = datetime.now(timezone.utc)
    db = MagicMock()
    db.execute.return_value.scalar_one.return_value = existing
    app.dependency_overrides[get_db] = lambda: db

    first = client.post("/me/account-deletion-request")
    second = client.post("/me/account-deletion-request")

    assert first.status_code == second.status_code == 202
    assert first.json()["status"] == second.json()["status"] == "auth_deleted"
    assert db.commit.call_count == 2


def test_deletion_request_failure_rolls_back_without_success():
    user = AuthenticatedUser(id=uuid.uuid4(), email="private@example.com")
    app.dependency_overrides[get_current_user] = lambda: user
    db = MagicMock()
    db.execute.side_effect = IntegrityError("insert", {}, Exception("db"))
    app.dependency_overrides[get_db] = lambda: db

    response = client.post("/me/account-deletion-request")

    assert response.status_code == 503
    db.rollback.assert_called_once_with()
    db.commit.assert_not_called()
    assert "private@example.com" not in response.text


def test_deletion_request_commit_failure_cannot_return_success():
    user = AuthenticatedUser(id=uuid.uuid4(), email="private@example.com")
    app.dependency_overrides[get_current_user] = lambda: user
    db = MagicMock()
    db.execute.return_value.scalar_one.return_value = _request(user.id)
    db.commit.side_effect = IntegrityError("commit", {}, Exception("db"))
    app.dependency_overrides[get_db] = lambda: db

    response = client.post("/me/account-deletion-request")

    assert response.status_code == 503
    db.rollback.assert_called_once_with()


def test_deletion_request_advisory_failure_rolls_back_without_accepting():
    user = AuthenticatedUser(id=uuid.uuid4(), email="private@example.com")
    app.dependency_overrides[get_current_user] = lambda: user
    db = MagicMock()
    db.connection.return_value.exec_driver_sql.side_effect = IntegrityError(
        "advisory", {}, Exception("db")
    )
    app.dependency_overrides[get_db] = lambda: db

    response = client.post("/me/account-deletion-request")

    assert response.status_code == 503
    db.execute.assert_not_called()
    db.commit.assert_not_called()
    db.rollback.assert_called_once_with()


@pytest.mark.parametrize("status", list(AccountDeletionStatus))
def test_every_deletion_state_blocks_user_mutations(status):
    user = AuthenticatedUser(id=uuid.uuid4(), email="private@example.com")
    db = MagicMock()
    db.get.return_value = _request(user.id, status)

    with pytest.raises(HTTPException) as error:
        ensure_account_active(user, db)

    assert error.value.status_code == 409
    assert "private@example.com" not in error.value.detail


def test_no_deletion_request_keeps_account_active():
    db = MagicMock()
    db.get.return_value = None
    ensure_account_active(
        AuthenticatedUser(id=uuid.uuid4(), email="parent@example.com"), db
    )


def test_serialized_mutation_uses_stable_user_advisory_lock_before_check():
    user = AuthenticatedUser(id=uuid.uuid4(), email="parent@example.com")
    db = MagicMock()
    db.get.return_value = None

    ensure_account_active(user, db, serialize_mutation=True)

    expected_key = int.from_bytes(user.id.bytes[:8], signed=True)
    db.connection.return_value.exec_driver_sql.assert_called_once_with(
        "SELECT pg_advisory_xact_lock(%s)", (expected_key,)
    )
    assert [call[0] for call in db.method_calls[:2]] == ["connection", "get"]


def test_pending_request_blocks_profile_bootstrap_without_write():
    user = AuthenticatedUser(id=uuid.uuid4(), email="private@example.com")
    app.dependency_overrides[get_current_user] = lambda: user
    db = MagicMock()
    db.get.return_value = _request(user.id)
    app.dependency_overrides[get_db] = lambda: db

    response = client.post(
        "/me/bootstrap", json={"first_name": "Rowan", "gender": "female"}
    )

    assert response.status_code == 409
    db.execute.assert_not_called()
    db.commit.assert_not_called()


def test_pending_request_blocks_new_post_without_write():
    user = AuthenticatedUser(id=uuid.uuid4(), email="private@example.com")
    app.dependency_overrides[get_current_user] = lambda: user
    db = MagicMock()
    db.get.return_value = _request(user.id)
    app.dependency_overrides[get_db] = lambda: db

    response = client.post(
        "/posts",
        json={"title": "Title", "body": "Body", "category": "experiences"},
    )

    assert response.status_code == 409
    db.add.assert_not_called()
    db.commit.assert_not_called()


@pytest.mark.parametrize(
    ("method", "path", "body"),
    [
        ("post", lambda post, comment: f"/posts/{post}/comments", {"body": "x"}),
        ("put", lambda post, comment: f"/posts/{post}/reaction", None),
        ("delete", lambda post, comment: f"/posts/{post}/reaction", None),
        ("put", lambda post, comment: f"/posts/{post}/report", {"reason": "x"}),
        (
            "put",
            lambda post, comment: f"/posts/{post}/comments/{comment}/report",
            {"reason": "x"},
        ),
    ],
    ids=[
        "comment-create",
        "reaction-add",
        "reaction-remove",
        "post-report",
        "comment-report",
    ],
)
def test_pending_request_blocks_community_mutation_before_target_lock(
    method, path, body
):
    user = AuthenticatedUser(id=uuid.uuid4(), email="private@example.com")
    app.dependency_overrides[get_current_user] = lambda: user
    db = MagicMock()
    db.get.return_value = _request(user.id)
    app.dependency_overrides[get_db] = lambda: db

    response = client.request(
        method.upper(), path(uuid.uuid4(), uuid.uuid4()), json=body
    )

    assert response.status_code == 409
    db.execute.assert_not_called()
    db.add.assert_not_called()
    db.commit.assert_not_called()


def test_pending_request_blocks_admin_owned_event_creation():
    user = AuthenticatedUser(id=uuid.uuid4(), email="private@example.com")
    app.dependency_overrides[get_current_user] = lambda: user
    profile = SimpleNamespace(id=user.id, role=UserRole.admin)
    db = MagicMock()
    db.get.side_effect = [profile, _request(user.id)]
    app.dependency_overrides[get_db] = lambda: db

    response = client.post(
        "/events",
        json={
            "title": "Event",
            "description": "Description",
            "location": "Location",
            "starts_at": "2030-01-01T10:00:00Z",
        },
    )

    assert response.status_code == 409
    db.add.assert_not_called()
    db.commit.assert_not_called()


def _workflow_db(deletion_request):
    db = MagicMock()
    db.execute.return_value.scalar_one_or_none.return_value = deletion_request
    return db


def test_fulfillment_records_auth_then_postgres_completion(monkeypatch):
    user_id = uuid.uuid4()
    deletion_request = _request(user_id)
    db = _workflow_db(deletion_request)
    auth_delete = MagicMock()
    cleanup = MagicMock()
    monkeypatch.setattr(service, "_cleanup_postgres", cleanup)

    result = fulfill_account_deletion(db, user_id, auth_delete)

    assert result.status == AccountDeletionStatus.completed
    auth_delete.assert_called_once_with(user_id)
    cleanup.assert_called_once_with(db, user_id)
    assert deletion_request.auth_deleted_at is not None
    assert deletion_request.completed_at is not None
    assert db.commit.call_count == 2


def test_auth_identity_without_profile_completes_cleanup():
    user_id = uuid.uuid4()
    deletion_request = _request(user_id)
    db = _workflow_db(deletion_request)
    db.execute.return_value.all.return_value = []
    db.scalars.return_value.all.return_value = []

    result = fulfill_account_deletion(db, user_id, MagicMock())

    assert result.status == AccountDeletionStatus.completed
    delete_sql = [
        str(call.args[0]).lower()
        for call in db.execute.call_args_list
        if str(call.args[0]).lower().startswith("delete")
    ]
    assert any("delete from profiles" in sql for sql in delete_sql)
    assert db.commit.call_count == 2


def test_retry_from_requested_succeeds_when_auth_identity_is_already_absent(
    monkeypatch,
):
    user_id = uuid.uuid4()
    deletion_request = _request(user_id)
    db = _workflow_db(deletion_request)
    cleanup = MagicMock()
    monkeypatch.setattr(service, "_cleanup_postgres", cleanup)
    transport = httpx.MockTransport(
        lambda request: httpx.Response(404, request=request)
    )
    admin = SupabaseAuthAdmin(
        supabase_url="https://project.supabase.co",
        service_role_key="operator-secret",
        timeout_seconds=1,
        client=httpx.Client(transport=transport),
    )

    result = fulfill_account_deletion(db, user_id, admin.delete_user)

    assert result.status == AccountDeletionStatus.completed
    cleanup.assert_called_once_with(db, user_id)
    assert db.commit.call_count == 2


def test_auth_failure_leaves_request_retryable_and_skips_cleanup(monkeypatch):
    user_id = uuid.uuid4()
    deletion_request = _request(user_id)
    db = _workflow_db(deletion_request)
    cleanup = MagicMock()
    monkeypatch.setattr(service, "_cleanup_postgres", cleanup)

    with pytest.raises(SupabaseAuthDeletionError):
        fulfill_account_deletion(
            db,
            user_id,
            MagicMock(side_effect=SupabaseAuthDeletionError("unavailable")),
        )

    assert deletion_request.status == AccountDeletionStatus.requested
    cleanup.assert_not_called()
    db.commit.assert_not_called()
    db.rollback.assert_called_once_with()


def test_auth_state_commit_failure_retries_from_requested(monkeypatch):
    user_id = uuid.uuid4()
    deletion_request = _request(user_id)
    db = _workflow_db(deletion_request)
    db.commit.side_effect = IntegrityError("commit", {}, Exception("db"))
    cleanup = MagicMock()
    monkeypatch.setattr(service, "_cleanup_postgres", cleanup)
    auth_delete = MagicMock()

    with pytest.raises(IntegrityError):
        fulfill_account_deletion(db, user_id, auth_delete)

    auth_delete.assert_called_once_with(user_id)
    cleanup.assert_not_called()
    db.rollback.assert_called_once_with()


def test_retry_after_auth_success_skips_auth_and_completes(monkeypatch):
    user_id = uuid.uuid4()
    deletion_request = _request(user_id, AccountDeletionStatus.auth_deleted)
    db = _workflow_db(deletion_request)
    cleanup = MagicMock()
    monkeypatch.setattr(service, "_cleanup_postgres", cleanup)
    auth_delete = MagicMock()

    result = fulfill_account_deletion(db, user_id, auth_delete)

    assert result.status == AccountDeletionStatus.completed
    auth_delete.assert_not_called()
    cleanup.assert_called_once_with(db, user_id)
    db.commit.assert_called_once_with()


def test_second_operator_completion_is_observed_without_repeating_cleanup(
    monkeypatch,
):
    user_id = uuid.uuid4()
    requested = _request(user_id)
    completed = _request(user_id, AccountDeletionStatus.completed)
    completed.auth_deleted_at = datetime.now(timezone.utc)
    completed.completed_at = datetime.now(timezone.utc)
    db = MagicMock()
    db.execute.side_effect = [
        MagicMock(scalar_one_or_none=MagicMock(return_value=requested)),
        MagicMock(scalar_one_or_none=MagicMock(return_value=completed)),
    ]
    cleanup = MagicMock()
    monkeypatch.setattr(service, "_cleanup_postgres", cleanup)

    result = fulfill_account_deletion(db, user_id, MagicMock())

    assert result.status == AccountDeletionStatus.completed
    cleanup.assert_not_called()
    assert db.commit.call_count == 1
    db.rollback.assert_called_once_with()


def test_postgres_failure_after_auth_success_remains_retryable(monkeypatch):
    user_id = uuid.uuid4()
    deletion_request = _request(user_id)
    db = _workflow_db(deletion_request)
    monkeypatch.setattr(
        service,
        "_cleanup_postgres",
        MagicMock(side_effect=IntegrityError("delete", {}, Exception("db"))),
    )

    with pytest.raises(IntegrityError):
        fulfill_account_deletion(db, user_id, MagicMock())

    assert deletion_request.status == AccountDeletionStatus.auth_deleted
    assert deletion_request.completed_at is None
    assert db.commit.call_count == 1
    db.rollback.assert_called_once_with()


def test_completion_commit_failure_rolls_back_cleanup_and_completion(monkeypatch):
    user_id = uuid.uuid4()
    deletion_request = _request(user_id, AccountDeletionStatus.auth_deleted)
    db = _workflow_db(deletion_request)
    db.commit.side_effect = IntegrityError("commit", {}, Exception("db"))
    cleanup = MagicMock()
    monkeypatch.setattr(service, "_cleanup_postgres", cleanup)

    with pytest.raises(IntegrityError):
        fulfill_account_deletion(db, user_id, MagicMock())

    cleanup.assert_called_once_with(db, user_id)
    db.rollback.assert_called_once_with()


def test_completed_fulfillment_is_idempotent(monkeypatch):
    user_id = uuid.uuid4()
    deletion_request = _request(user_id, AccountDeletionStatus.completed)
    db = _workflow_db(deletion_request)
    auth_delete = MagicMock()
    cleanup = MagicMock()
    monkeypatch.setattr(service, "_cleanup_postgres", cleanup)

    result = fulfill_account_deletion(db, user_id, auth_delete)

    assert result.status == AccountDeletionStatus.completed
    auth_delete.assert_not_called()
    cleanup.assert_not_called()
    db.commit.assert_not_called()


def test_postgres_cleanup_uses_target_first_locks_and_repairs_counters():
    user_id = uuid.uuid4()
    authored_post_id = uuid.uuid4()
    surviving_post_id = uuid.uuid4()
    authored_comment_id = uuid.uuid4()
    thread_comment_id = uuid.uuid4()
    reported_comment_id = uuid.uuid4()

    authored_post = SimpleNamespace(id=authored_post_id)
    surviving_post = SimpleNamespace(
        id=surviving_post_id,
        reaction_count=99,
        comment_count=99,
        report_count=99,
    )
    authored_comment = SimpleNamespace(
        id=authored_comment_id,
        post_id=surviving_post_id,
        report_count=99,
    )
    thread_comment = SimpleNamespace(
        id=thread_comment_id,
        post_id=authored_post_id,
        report_count=99,
    )
    reported_comment = SimpleNamespace(
        id=reported_comment_id,
        post_id=surviving_post_id,
        report_count=99,
    )

    db = MagicMock()
    db.scalars.side_effect = [
        MagicMock(all=MagicMock(return_value=[authored_post_id])),
        MagicMock(all=MagicMock(return_value=[authored_comment_id])),
        MagicMock(all=MagicMock(return_value=[surviving_post_id])),
        MagicMock(all=MagicMock(return_value=[surviving_post_id])),
        MagicMock(all=MagicMock(return_value=[authored_post, surviving_post])),
        MagicMock(all=MagicMock(return_value=[thread_comment_id])),
        MagicMock(
            all=MagicMock(
                return_value=[authored_comment, thread_comment, reported_comment]
            )
        ),
        MagicMock(all=MagicMock(return_value=[uuid.uuid4()])),
        MagicMock(all=MagicMock(return_value=[SimpleNamespace()])),
    ]
    report_rows = [
        SimpleNamespace(post_id=surviving_post_id, comment_id=None),
        SimpleNamespace(post_id=None, comment_id=reported_comment_id),
    ]
    db.execute.side_effect = [
        MagicMock(all=MagicMock(return_value=report_rows)),
        MagicMock(),
        MagicMock(),
        MagicMock(),
        MagicMock(),
        MagicMock(),
    ]
    db.scalar.side_effect = [4, 2, 1, 3]

    service._cleanup_postgres(db, user_id)

    scalar_sql = [str(call.args[0]).lower() for call in db.scalars.call_args_list]
    assert "from posts" in scalar_sql[4] and "for update" in scalar_sql[4]
    assert "order by posts.id" in scalar_sql[4]
    assert "from comments" in scalar_sql[6] and "for update" in scalar_sql[6]
    assert "order by comments.id" in scalar_sql[6]
    assert "from reports" in scalar_sql[8] and "for update" in scalar_sql[8]
    assert "order by reports.id" in scalar_sql[8]

    delete_sql = [
        str(call.args[0]).lower() for call in db.execute.call_args_list[1:]
    ]
    assert "delete from reports" in delete_sql[0]
    assert "delete from comments" in delete_sql[1]
    assert "delete from posts" in delete_sql[2]
    assert "delete from post_reactions" in delete_sql[3]
    assert "delete from profiles" in delete_sql[4]
    assert surviving_post.reaction_count == 4
    assert surviving_post.comment_count == 2
    assert surviving_post.report_count == 1
    assert reported_comment.report_count == 3
    assert db.flush.call_count == 2


@pytest.mark.parametrize("status_code", [200, 204, 404])
def test_supabase_auth_deletion_treats_absent_identity_as_success(status_code):
    captured = {}

    def respond(request):
        captured["request"] = request
        return httpx.Response(status_code, request=request)

    transport = httpx.MockTransport(
        respond
    )
    http_client = httpx.Client(transport=transport)
    admin = SupabaseAuthAdmin(
        supabase_url="https://project.supabase.co",
        service_role_key="operator-secret",
        timeout_seconds=1,
        client=http_client,
    )

    user_id = uuid.uuid4()
    admin.delete_user(user_id)

    request = captured["request"]
    assert request.method == "DELETE"
    assert request.url.path == f"/auth/v1/admin/users/{user_id}"
    assert request.headers["apikey"] == "operator-secret"
    assert request.headers["authorization"] == "Bearer operator-secret"


def test_supabase_auth_failure_never_exposes_response_body_or_secret():
    transport = httpx.MockTransport(
        lambda request: httpx.Response(
            500, text="private@example.com operator-secret", request=request
        )
    )
    admin = SupabaseAuthAdmin(
        supabase_url="https://project.supabase.co",
        service_role_key="operator-secret",
        timeout_seconds=1,
        client=httpx.Client(transport=transport),
    )

    with pytest.raises(SupabaseAuthDeletionError) as error:
        admin.delete_user(uuid.uuid4())

    assert "private@example.com" not in str(error.value)
    assert "operator-secret" not in str(error.value)


def test_completed_request_purge_rejects_zero_retention():
    with pytest.raises(ValueError):
        service.purge_completed_requests(
            MagicMock(),
            0,
            max_access_token_lifetime_seconds=3600,
            jwt_clock_skew_seconds=60,
        )


def test_settings_accept_valid_account_deletion_retention():
    configured = Settings(
        _env_file=None,
        account_deletion_completed_retention_days=2,
        supabase_access_token_max_lifetime_seconds=86_000,
        supabase_jwt_clock_skew_seconds=400,
    )

    assert configured.account_deletion_completed_retention_days == 2


def test_default_account_deletion_retention_is_safe():
    configured = Settings(_env_file=None)

    assert configured.supabase_access_token_max_lifetime_seconds == 3600
    assert configured.supabase_jwt_clock_skew_seconds == 60
    assert configured.account_deletion_completed_retention_days == 7


def test_settings_accept_exact_retention_boundary():
    configured = Settings(
        _env_file=None,
        account_deletion_completed_retention_days=1,
        supabase_access_token_max_lifetime_seconds=86_000,
        supabase_jwt_clock_skew_seconds=200,
    )

    assert configured.supabase_access_token_max_lifetime_seconds == 86_000


def test_settings_reject_retention_shorter_than_jwt_lifetime_and_skew():
    with pytest.raises(ValidationError, match="retention must cover"):
        Settings(
            _env_file=None,
            account_deletion_completed_retention_days=1,
            supabase_access_token_max_lifetime_seconds=86_001,
            supabase_jwt_clock_skew_seconds=200,
        )


def test_purge_refuses_unsafe_retention_without_querying_database():
    db = MagicMock()

    with pytest.raises(ValueError, match="shorter than JWT validity"):
        service.purge_completed_requests(
            db,
            1,
            max_access_token_lifetime_seconds=86_001,
            jwt_clock_skew_seconds=200,
        )

    db.execute.assert_not_called()
    db.commit.assert_not_called()


def test_completed_request_purge_is_bounded_and_committed():
    db = MagicMock()
    db.execute.return_value.rowcount = 2

    count = service.purge_completed_requests(
        db,
        7,
        max_access_token_lifetime_seconds=3600,
        jwt_clock_skew_seconds=60,
    )

    assert count == 2
    sql = str(db.execute.call_args.args[0]).lower()
    assert "delete from account_deletion_requests" in sql
    assert "status" in sql and "completed_at" in sql
    assert "completed_at <" in sql
    db.commit.assert_called_once_with()


def test_completed_request_purge_rolls_back_on_database_error():
    db = MagicMock()
    db.execute.side_effect = IntegrityError("delete", {}, Exception("db"))

    with pytest.raises(IntegrityError):
        service.purge_completed_requests(
            db,
            7,
            max_access_token_lifetime_seconds=3600,
            jwt_clock_skew_seconds=60,
        )

    db.rollback.assert_called_once_with()
    db.commit.assert_not_called()
