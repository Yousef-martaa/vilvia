import uuid
from datetime import datetime, timezone
from unittest.mock import MagicMock

import pytest
from fastapi.testclient import TestClient
from sqlalchemy.exc import IntegrityError

from app.api.deps import AuthenticatedUser, get_current_user, get_db
from app.main import app
from app.models.enums import Gender, UserRole

client = TestClient(app)


@pytest.fixture(autouse=True)
def clear_overrides():
    yield
    app.dependency_overrides.clear()


def _override_current_user(user_id=None, email="parent@example.com"):
    user = AuthenticatedUser(id=user_id or uuid.uuid4(), email=email)
    app.dependency_overrides[get_current_user] = lambda: user
    return user


def make_mock_profile(**kwargs):
    now = datetime.now(timezone.utc)
    profile = MagicMock()
    profile.id = kwargs.get("id", uuid.uuid4())
    profile.first_name = kwargs.get("first_name", "Rowan")
    profile.email = kwargs.get("email", "parent@example.com")
    profile.role = kwargs.get("role", UserRole.parent)
    profile.gender = kwargs.get("gender", Gender.female)
    profile.created_at = kwargs.get("created_at", now)
    profile.updated_at = kwargs.get("updated_at", now)
    return profile


def _mock_db_returning(profile):
    mock_db = MagicMock()
    mock_db.get.return_value = profile
    app.dependency_overrides[get_db] = lambda: mock_db
    return mock_db


# --- GET /me: read-only -------------------------------------------------


def test_get_me_returns_profile_when_it_exists():
    user = _override_current_user()
    _mock_db_returning(make_mock_profile(id=user.id, first_name="Rowan"))

    response = client.get("/me")

    assert response.status_code == 200
    assert response.json()["first_name"] == "Rowan"


def test_get_me_returns_null_gender_for_a_legacy_profile():
    # Rows created before `gender` existed have no value and are not
    # backfilled -- GET /me must surface that as null, not error or
    # invent a value.
    user = _override_current_user()
    _mock_db_returning(make_mock_profile(id=user.id, gender=None))

    response = client.get("/me")

    assert response.status_code == 200
    assert response.json()["gender"] is None


def test_get_me_returns_404_when_no_profile_exists():
    _override_current_user()
    _mock_db_returning(None)

    response = client.get("/me")

    assert response.status_code == 404


def test_get_me_never_writes_to_the_database():
    _override_current_user()
    mock_db = _mock_db_returning(None)

    client.get("/me")

    mock_db.add.assert_not_called()
    mock_db.execute.assert_not_called()
    mock_db.commit.assert_not_called()


def test_get_me_requires_authentication():
    app.dependency_overrides.clear()  # no auth override at all
    response = client.get("/me")
    assert response.status_code == 401


# --- POST /me/bootstrap ---------------------------------------------------


def test_bootstrap_creates_profile_using_verified_identity():
    user = _override_current_user(email="new@example.com")
    mock_db = _mock_db_returning(
        make_mock_profile(id=user.id, first_name="Rowan", email="new@example.com")
    )

    response = client.post(
        "/me/bootstrap", json={"first_name": "Rowan", "gender": "female"}
    )

    assert response.status_code == 200
    insert_values = mock_db.execute.call_args[0][0].compile().params
    assert insert_values["id"] == user.id
    assert insert_values["email"] == "new@example.com"
    assert insert_values["first_name"] == "Rowan"
    assert insert_values["gender"] == Gender.female
    assert insert_values["role"] == UserRole.parent


def test_bootstrap_rejects_role_field_with_422():
    # BootstrapRequest has no `role` field at all, and `extra="forbid"`
    # means submitting one is rejected outright rather than silently
    # dropped -- a client cannot even attempt to influence role.
    _override_current_user()

    response = client.post(
        "/me/bootstrap",
        json={"first_name": "Rowan", "gender": "male", "role": "admin"},
    )

    assert response.status_code == 422


def test_bootstrap_rejects_id_field_with_422():
    _override_current_user()

    response = client.post(
        "/me/bootstrap",
        json={"first_name": "Rowan", "gender": "male", "id": str(uuid.uuid4())},
    )

    assert response.status_code == 422


def test_bootstrap_rejects_email_field_with_422():
    _override_current_user()

    response = client.post(
        "/me/bootstrap",
        json={
            "first_name": "Rowan",
            "gender": "male",
            "email": "attacker@example.com",
        },
    )

    assert response.status_code == 422


def test_bootstrap_rejects_unknown_field_with_422():
    _override_current_user()

    response = client.post(
        "/me/bootstrap",
        json={"first_name": "Rowan", "gender": "male", "is_admin": True},
    )

    assert response.status_code == 422


def test_bootstrap_is_idempotent_and_does_not_overwrite_an_existing_profile():
    user = _override_current_user()
    existing = make_mock_profile(id=user.id, first_name="Original Name")
    _mock_db_returning(existing)

    response = client.post(
        "/me/bootstrap",
        json={"first_name": "A Different Name", "gender": "female"},
    )

    # ON CONFLICT DO NOTHING means the already-existing row is untouched;
    # the response reflects whatever db.get() reads back afterwards.
    assert response.status_code == 200
    assert response.json()["first_name"] == "Original Name"


def test_bootstrap_requires_first_name():
    _override_current_user()
    response = client.post("/me/bootstrap", json={"gender": "male"})
    assert response.status_code == 422


def test_bootstrap_rejects_blank_first_name():
    _override_current_user()
    response = client.post(
        "/me/bootstrap", json={"first_name": "", "gender": "male"}
    )
    assert response.status_code == 422


def test_bootstrap_requires_gender():
    _override_current_user()
    response = client.post("/me/bootstrap", json={"first_name": "Rowan"})
    assert response.status_code == 422


def test_bootstrap_rejects_invalid_gender():
    _override_current_user()
    response = client.post(
        "/me/bootstrap", json={"first_name": "Rowan", "gender": "nonbinary"}
    )
    assert response.status_code == 422


def test_bootstrap_persists_valid_gender():
    user = _override_current_user()
    mock_db = _mock_db_returning(make_mock_profile(id=user.id, gender=Gender.male))

    response = client.post(
        "/me/bootstrap", json={"first_name": "Rowan", "gender": "male"}
    )

    assert response.status_code == 200
    insert_values = mock_db.execute.call_args[0][0].compile().params
    assert insert_values["gender"] == Gender.male


def test_bootstrap_requires_authentication():
    app.dependency_overrides.clear()
    response = client.post(
        "/me/bootstrap", json={"first_name": "Rowan", "gender": "male"}
    )
    assert response.status_code == 401


def test_bootstrap_returns_409_and_rolls_back_on_conflicting_email():
    # The conflict target is only `id`; a different existing profile
    # already using this email raises a genuine IntegrityError rather
    # than being absorbed by ON CONFLICT DO NOTHING.
    _override_current_user(email="taken@example.com")
    mock_db = MagicMock()
    mock_db.execute.side_effect = IntegrityError(
        "INSERT ...", {}, Exception("duplicate key value violates unique constraint")
    )
    app.dependency_overrides[get_db] = lambda: mock_db

    response = client.post(
        "/me/bootstrap", json={"first_name": "Rowan", "gender": "male"}
    )

    assert response.status_code == 409
    mock_db.rollback.assert_called_once()
    # The session must not be left in an aborted-transaction state: no
    # further commands (like the post-insert read-back) were attempted.
    mock_db.get.assert_not_called()


def test_bootstrap_returns_500_if_profile_is_unreadable_after_insert():
    # Defends the explicit-error path that replaced a bare `assert` --
    # this should be unreachable in practice, but must fail as a clean
    # 500, not an AssertionError.
    _override_current_user()
    mock_db = MagicMock()
    mock_db.get.return_value = None
    app.dependency_overrides[get_db] = lambda: mock_db

    response = client.post(
        "/me/bootstrap", json={"first_name": "Rowan", "gender": "male"}
    )

    assert response.status_code == 500
