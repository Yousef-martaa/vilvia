import uuid
from datetime import datetime, timezone
from unittest.mock import MagicMock

import pytest
from fastapi.testclient import TestClient

from app.api.deps import get_db
from app.main import app

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
    assert "order by posts.created_at desc" in sql


def test_get_posts_response_excludes_internal_fields():
    mock_db_returning([make_mock_post()])

    data = client.get("/posts").json()[0]

    assert "author_id" not in data
    assert "report_count" not in data
    assert "is_published" not in data
    assert "related_resource_id" not in data
