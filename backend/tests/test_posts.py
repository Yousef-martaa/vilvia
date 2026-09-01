import uuid
from datetime import datetime, timezone
from unittest.mock import MagicMock

import pytest
from fastapi.testclient import TestClient
from sqlalchemy.exc import IntegrityError

import app.api.deps as deps_module
from app.api.deps import (
    AuthenticatedUser,
    get_current_user,
    get_db,
    get_optional_current_user,
)
from app.core.auth import InvalidTokenError
from app.main import app
from app.models.enums import UserRole

client = TestClient(app)


def make_mock_post(**kwargs):
    post = MagicMock()
    post.id = kwargs.get("id", uuid.uuid4())
    post.author_id = kwargs.get("author_id", uuid.uuid4())
    post.author_name = kwargs.get("author_name", "Alex")
    post.author_avatar_url = kwargs.get("author_avatar_url")
    post.title = kwargs.get("title", "Test Post")
    post.body = kwargs.get("body", "A community post.")
    post.category = kwargs.get("category", "experiences")
    post.related_resource_id = kwargs.get("related_resource_id")
    post.reaction_count = kwargs.get("reaction_count", 2)
    post.comment_count = kwargs.get("comment_count", 3)
    post.report_count = kwargs.get("report_count", 1)
    post.is_published = kwargs.get("is_published", True)
    post.created_at = kwargs.get(
        "created_at", datetime(2026, 8, 22, tzinfo=timezone.utc)
    )
    post.updated_at = kwargs.get(
        "updated_at", datetime(2026, 8, 22, tzinfo=timezone.utc)
    )
    return post


@pytest.fixture(autouse=True)
def clear_overrides():
    yield
    app.dependency_overrides.clear()


def mock_db_returning(posts):
    mock_db = MagicMock()
    mock_db.execute.return_value.scalars.return_value.all.return_value = posts
    app.dependency_overrides[get_db] = lambda: mock_db
    return mock_db


def test_get_posts_is_public_and_returns_feed():
    post = make_mock_post()
    mock_db_returning([post])

    response = client.get("/posts")

    assert response.status_code == 200
    assert response.json()[0]["title"] == post.title
    assert response.json()[0]["body"] == post.body
    assert response.json()[0]["has_reacted"] is False


def test_get_posts_empty_returns_empty_list():
    mock_db_returning([])

    response = client.get("/posts")

    assert response.status_code == 200
    assert response.json() == []


def test_get_posts_query_filters_published_and_orders_newest_first():
    mock_db = mock_db_returning([])

    client.get("/posts")

    sql = str(mock_db.execute.call_args[0][0]).lower()
    assert "is_published is true" in sql
    assert "is_hidden is false" in sql
    assert "order by posts.created_at desc" in sql


def test_get_posts_response_excludes_internal_fields():
    mock_db_returning([make_mock_post()])

    data = client.get("/posts").json()[0]

    assert "author_id" not in data
    assert "report_count" not in data
    assert "is_published" not in data
    assert "is_hidden" not in data
    assert "related_resource_id" not in data


def test_get_posts_reports_authenticated_callers_reactions():
    reacted = make_mock_post()
    not_reacted = make_mock_post()
    user = AuthenticatedUser(id=uuid.uuid4(), email="parent@example.com")
    app.dependency_overrides[get_optional_current_user] = lambda: user
    db = MagicMock()
    db.execute.side_effect = [
        MagicMock(
            scalars=MagicMock(
                return_value=MagicMock(all=MagicMock(return_value=[reacted, not_reacted]))
            )
        ),
        MagicMock(scalars=MagicMock(return_value=[reacted.id])),
    ]
    app.dependency_overrides[get_db] = lambda: db

    data = client.get("/posts", headers={"Authorization": "Bearer valid"}).json()

    assert data[0]["has_reacted"] is True
    assert data[1]["has_reacted"] is False


def test_get_posts_rejects_an_invalid_supplied_token(monkeypatch):
    def reject(_token):
        raise InvalidTokenError("invalid")

    monkeypatch.setattr(deps_module, "verify_access_token", reject)
    mock_db_returning([])

    response = client.get("/posts", headers={"Authorization": "Bearer invalid"})

    assert response.status_code == 401


def authenticated_post_db(profile=True):
    user = AuthenticatedUser(id=uuid.uuid4(), email="parent@example.com")
    app.dependency_overrides[get_current_user] = lambda: user
    mock_db = MagicMock()
    if profile:
        stored_profile = MagicMock()
        stored_profile.id = user.id
        stored_profile.first_name = "Rowan"
        stored_profile.role = UserRole.parent
        mock_db.get.return_value = stored_profile
    else:
        mock_db.get.return_value = None

    def refresh(post):
        post.id = uuid.uuid4()
        post.reaction_count = 0
        post.comment_count = 0
        post.created_at = datetime.now(timezone.utc)
        post.updated_at = post.created_at

    mock_db.refresh.side_effect = refresh
    app.dependency_overrides[get_db] = lambda: mock_db
    return user, mock_db


def valid_create_body():
    return {
        "title": "  A useful question  ",
        "body": "  How did you handle this stage?  ",
        "category": "qa",
    }


def test_create_post_uses_verified_profile_and_publishes_immediately():
    user, mock_db = authenticated_post_db()

    response = client.post("/posts", json=valid_create_body())

    assert response.status_code == 201
    post = mock_db.add.call_args.args[0]
    assert post.author_id == user.id
    assert post.author_name == "Rowan"
    assert post.author_avatar_url is None
    assert post.title == "A useful question"
    assert post.body == "How did you handle this stage?"
    assert post.category.value == "qa"
    assert post.is_published is True
    mock_db.commit.assert_called_once_with()
    mock_db.refresh.assert_called_once_with(post)


def test_create_post_requires_authentication():
    mock_db_returning([])

    response = client.post("/posts", json=valid_create_body())

    assert response.status_code == 401


def test_create_post_returns_409_when_verified_user_has_no_profile():
    _, mock_db = authenticated_post_db(profile=False)

    response = client.post("/posts", json=valid_create_body())

    assert response.status_code == 409
    assert response.json()["detail"] == "A Profile is required before creating a post."
    mock_db.add.assert_not_called()


@pytest.mark.parametrize(
    "internal_field",
    [
        "author_id",
        "author_name",
        "author_avatar_url",
        "is_published",
        "is_hidden",
        "reaction_count",
        "comment_count",
        "report_count",
        "related_resource_id",
        "id",
    ],
)
def test_create_post_strictly_rejects_internal_fields(internal_field):
    authenticated_post_db()
    body = valid_create_body()
    body[internal_field] = True

    response = client.post("/posts", json=body)

    assert response.status_code == 422


@pytest.mark.parametrize(
    ("field", "value"),
    [
        ("title", ""),
        ("title", " " * 3),
        ("title", "x" * 201),
        ("body", ""),
        ("body", " " * 3),
        ("body", "x" * 5001),
        ("category", "not_a_category"),
    ],
)
def test_create_post_validates_content(field, value):
    authenticated_post_db()
    body = valid_create_body()
    body[field] = value

    response = client.post("/posts", json=body)

    assert response.status_code == 422


def test_create_post_rolls_back_integrity_error_and_returns_controlled_conflict():
    _, mock_db = authenticated_post_db()
    mock_db.commit.side_effect = IntegrityError("statement", {}, Exception("db"))

    response = client.post("/posts", json=valid_create_body())

    assert response.status_code == 409
    assert response.json()["detail"] == (
        "The post could not be created because of a data conflict."
    )
    mock_db.rollback.assert_called_once_with()
