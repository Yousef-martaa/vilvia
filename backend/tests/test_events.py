import uuid
from datetime import datetime, timedelta, timezone
from unittest.mock import MagicMock

import pytest
from fastapi.testclient import TestClient

from app.api.deps import get_db
from app.main import app

client = TestClient(app)


def make_mock_event(**kwargs):
    now = datetime.now(timezone.utc)
    event = MagicMock()
    event.id = kwargs.get("id", uuid.uuid4())
    event.title = kwargs.get("title", "Test Event")
    event.description = kwargs.get("description", "A short description")
    event.location = kwargs.get("location", "Community Centre")
    event.starts_at = kwargs.get("starts_at", now + timedelta(days=1))
    event.ends_at = kwargs.get("ends_at", now + timedelta(days=1, hours=2))
    event.created_by = kwargs.get("created_by", None)
    event.is_published = kwargs.get("is_published", True)
    event.created_at = kwargs.get("created_at", now)
    event.updated_at = kwargs.get("updated_at", now)
    return event


@pytest.fixture(autouse=True)
def clear_overrides():
    yield
    app.dependency_overrides.clear()


def mock_db_returning(events):
    mock_db = MagicMock()
    mock_db.execute.return_value.scalars.return_value.all.return_value = events
    app.dependency_overrides[get_db] = lambda: mock_db
    return mock_db


def test_get_events_returns_list():
    event = make_mock_event()
    mock_db_returning([event])

    response = client.get("/events")

    assert response.status_code == 200
    data = response.json()
    assert isinstance(data, list)
    assert len(data) == 1
    assert data[0]["title"] == event.title
    assert data[0]["location"] == event.location
    assert data[0]["description"] == event.description


def test_get_events_does_not_expose_created_by():
    # Issue #65 establishes ownership at the domain/DB layer only; the
    # public list contract is deliberately unchanged until something
    # actually needs creator information.
    event = make_mock_event(created_by=uuid.uuid4())
    mock_db_returning([event])

    response = client.get("/events")

    data = response.json()
    assert "created_by" not in data[0]
    assert "creator_name" not in data[0]


def test_get_events_empty_returns_empty_list():
    mock_db_returning([])

    response = client.get("/events")

    assert response.status_code == 200
    assert response.json() == []


def test_get_events_query_filters_published_and_upcoming_ordered_soonest_first():
    mock_db = mock_db_returning([])

    client.get("/events")

    stmt = mock_db.execute.call_args[0][0]
    sql = str(stmt).lower()
    assert "is_published is true" in sql
    assert "starts_at >=" in sql
    assert "now()" in sql
    assert "order by events.starts_at asc" in sql
