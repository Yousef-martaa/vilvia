import uuid
from unittest.mock import MagicMock

import pytest
from fastapi.testclient import TestClient
from sqlalchemy.exc import IntegrityError

from app.api.deps import AuthenticatedUser, get_current_user, get_db
from app.main import app
from app.models.post_reaction import PostReaction
from app.models.profile import Profile

client = TestClient(app)


@pytest.fixture(autouse=True)
def clear_overrides():
    yield
    app.dependency_overrides.clear()


def reaction_db(*, post=True, profile=True, reaction=None, count=1):
    user = AuthenticatedUser(id=uuid.uuid4(), email="parent@example.com")
    app.dependency_overrides[get_current_user] = lambda: user
    db = MagicMock()
    stored_post = MagicMock() if post else None
    if stored_post is not None:
        stored_post.id = uuid.uuid4()
        stored_post.reaction_count = 0
    stored_profile = MagicMock() if profile else None
    if stored_profile is not None:
        stored_profile.id = user.id

    db.execute.return_value.scalar_one_or_none.return_value = stored_post

    def get(model, identity):
        if model is Profile:
            return stored_profile
        if model is PostReaction:
            return reaction
        raise AssertionError(f"Unexpected model: {model}")

    db.get.side_effect = get
    db.scalar.return_value = count
    app.dependency_overrides[get_db] = lambda: db
    return user, db, stored_post


def test_put_adds_server_owned_reaction_and_returns_authoritative_count():
    user, db, post = reaction_db(count=4)

    response = client.put(f"/posts/{post.id}/reaction")

    assert response.status_code == 200
    reaction = db.add.call_args.args[0]
    assert reaction.post_id == post.id
    assert reaction.profile_id == user.id
    assert response.json() == {"reacted": True, "reaction_count": 4}
    assert post.reaction_count == 4
    db.flush.assert_called_once_with()
    db.commit.assert_called_once_with()
    lock_sql = str(db.execute.call_args.args[0]).lower()
    assert "for update" in lock_sql
    assert "is_published is true" in lock_sql
    count_sql = str(db.scalar.call_args.args[0]).lower()
    assert "count(" in count_sql
    assert "post_reactions.post_id" in count_sql


def test_put_is_idempotent_when_reaction_already_exists():
    existing = MagicMock(spec=PostReaction)
    _, db, post = reaction_db(reaction=existing, count=1)

    response = client.put(f"/posts/{post.id}/reaction")

    assert response.json() == {"reacted": True, "reaction_count": 1}
    db.add.assert_not_called()
    db.delete.assert_not_called()


def test_delete_removes_only_the_callers_reaction():
    existing = MagicMock(spec=PostReaction)
    _, db, post = reaction_db(reaction=existing, count=2)

    response = client.delete(f"/posts/{post.id}/reaction")

    assert response.json() == {"reacted": False, "reaction_count": 2}
    db.delete.assert_called_once_with(existing)
    db.add.assert_not_called()


def test_delete_is_idempotent_when_reaction_is_absent():
    _, db, post = reaction_db(count=0)

    response = client.delete(f"/posts/{post.id}/reaction")

    assert response.json() == {"reacted": False, "reaction_count": 0}
    db.delete.assert_not_called()


@pytest.mark.parametrize("method", ["put", "delete"])
def test_reaction_mutation_requires_authentication(method):
    response = getattr(client, method)(f"/posts/{uuid.uuid4()}/reaction")
    assert response.status_code == 401


@pytest.mark.parametrize("method", ["put", "delete"])
def test_reaction_returns_404_for_missing_or_unpublished_post(method):
    _, db, _ = reaction_db(post=False)

    response = getattr(client, method)(f"/posts/{uuid.uuid4()}/reaction")

    assert response.status_code == 404
    db.get.assert_not_called()
    db.commit.assert_not_called()


@pytest.mark.parametrize("method", ["put", "delete"])
def test_reaction_returns_409_without_profile(method):
    _, db, post = reaction_db(profile=False)

    response = getattr(client, method)(f"/posts/{post.id}/reaction")

    assert response.status_code == 409
    assert response.json()["detail"] == (
        "A Profile is required before reacting to a post."
    )
    db.commit.assert_not_called()


def test_reaction_rolls_back_integrity_error():
    _, db, post = reaction_db()
    db.flush.side_effect = IntegrityError("statement", {}, Exception("db"))

    response = client.put(f"/posts/{post.id}/reaction")

    assert response.status_code == 409
    assert response.json()["detail"] == (
        "The reaction could not be updated because of a data conflict."
    )
    db.rollback.assert_called_once_with()
