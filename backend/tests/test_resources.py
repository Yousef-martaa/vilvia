import uuid
from datetime import datetime, timezone
from unittest.mock import MagicMock

import pytest
from fastapi.testclient import TestClient

from app.api.deps import get_db
from app.main import app

client = TestClient(app)


def make_mock_resource(**kwargs):
    resource = MagicMock()
    resource.id = kwargs.get("id", uuid.uuid4())
    resource.title = kwargs.get("title", "Test Resource")
    resource.summary = kwargs.get("summary", "A short summary")
    resource.category = kwargs.get("category", "child_development")
    resource.stage = kwargs.get("stage", "pregnancy")
    resource.source_name = kwargs.get("source_name", "Health Authority")
    resource.source_url = kwargs.get("source_url", "https://example.com")
    resource.is_published = kwargs.get("is_published", True)
    resource.created_at = kwargs.get("created_at", datetime(2024, 1, 1, tzinfo=timezone.utc))
    resource.updated_at = kwargs.get("updated_at", datetime(2024, 1, 1, tzinfo=timezone.utc))
    return resource


@pytest.fixture(autouse=True)
def clear_overrides():
    yield
    app.dependency_overrides.clear()


def mock_db_returning(resources):
    mock_db = MagicMock()
    mock_db.execute.return_value.scalars.return_value.all.return_value = resources
    app.dependency_overrides[get_db] = lambda: mock_db
    return mock_db


def test_get_resources_returns_list():
    resource = make_mock_resource()
    mock_db_returning([resource])

    response = client.get("/resources")

    assert response.status_code == 200
    data = response.json()
    assert isinstance(data, list)
    assert len(data) == 1
    assert data[0]["title"] == resource.title
    assert data[0]["summary"] == resource.summary
    assert "body" not in data[0]


def test_get_resources_empty_returns_empty_list():
    mock_db_returning([])

    response = client.get("/resources")

    assert response.status_code == 200
    assert response.json() == []


def test_get_resources_query_filters_published_and_orders_by_created_at():
    mock_db = mock_db_returning([])

    client.get("/resources")

    stmt = mock_db.execute.call_args[0][0]
    sql = str(stmt).lower()
    assert "is_published is true" in sql
    assert "created_at desc" in sql
