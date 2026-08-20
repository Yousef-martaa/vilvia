import uuid
from datetime import datetime, timedelta, timezone
from unittest.mock import MagicMock

import pytest
from fastapi.testclient import TestClient

from app.api.deps import AuthenticatedUser, get_current_user, get_db
from app.main import app
from app.models.enums import UserRole
from app.models.profile import Profile

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


# --- POST /events: admin-only draft creation -------------------------------


def _override_current_user(user_id=None, email="admin@example.com"):
    user = AuthenticatedUser(id=user_id or uuid.uuid4(), email=email)
    app.dependency_overrides[get_current_user] = lambda: user
    return user


def make_mock_profile(**kwargs):
    profile = MagicMock()
    profile.id = kwargs.get("id", uuid.uuid4())
    profile.role = kwargs.get("role", UserRole.parent)
    return profile


def _mock_db_for_create(profile):
    """A get_db override suitable for require_admin (db.get -> profile)
    plus a real POST /events write: db.refresh is faked to behave like a
    post-flush read-back, since the mock never actually inserts a row.
    """
    mock_db = MagicMock()
    mock_db.get.return_value = profile

    def _fake_refresh(event):
        if event.id is None:
            event.id = uuid.uuid4()
        now = datetime.now(timezone.utc)
        event.created_at = now
        event.updated_at = now

    mock_db.refresh.side_effect = _fake_refresh
    app.dependency_overrides[get_db] = lambda: mock_db
    return mock_db


def valid_event_payload(**overrides):
    now = datetime.now(timezone.utc)
    payload = {
        "title": "Parent & Baby Playgroup",
        "description": "A relaxed drop-in playgroup.",
        "location": "Community Centre",
        "starts_at": (now + timedelta(days=1)).isoformat(),
        "ends_at": (now + timedelta(days=1, hours=2)).isoformat(),
    }
    payload.update(overrides)
    return payload


def test_create_event_requires_authentication():
    app.dependency_overrides.clear()  # no auth override at all
    response = client.post("/events", json=valid_event_payload())
    assert response.status_code == 401


def test_create_event_rejects_authenticated_parent():
    _override_current_user()
    _mock_db_for_create(make_mock_profile(role=UserRole.parent))

    response = client.post("/events", json=valid_event_payload())

    assert response.status_code == 403


def test_create_event_rejects_authenticated_user_without_profile():
    _override_current_user()
    _mock_db_for_create(None)

    response = client.post("/events", json=valid_event_payload())

    assert response.status_code == 403


def test_create_event_allows_admin():
    _override_current_user()
    _mock_db_for_create(make_mock_profile(role=UserRole.admin))

    response = client.post("/events", json=valid_event_payload())

    assert response.status_code == 201
    data = response.json()
    assert data["title"] == "Parent & Baby Playgroup"
    assert data["location"] == "Community Centre"


def test_create_event_assigns_created_by_from_authenticated_admin():
    user = _override_current_user()
    admin_profile = make_mock_profile(id=user.id, role=UserRole.admin)
    mock_db = _mock_db_for_create(admin_profile)

    client.post("/events", json=valid_event_payload())

    created_event = mock_db.add.call_args[0][0]
    assert created_event.created_by == user.id


def test_create_event_always_sets_is_published_false():
    user = _override_current_user()
    admin_profile = make_mock_profile(id=user.id, role=UserRole.admin)
    mock_db = _mock_db_for_create(admin_profile)

    client.post("/events", json=valid_event_payload())

    created_event = mock_db.add.call_args[0][0]
    assert created_event.is_published is False


def test_create_event_does_not_expose_created_by_in_response():
    user = _override_current_user()
    _mock_db_for_create(make_mock_profile(id=user.id, role=UserRole.admin))

    response = client.post("/events", json=valid_event_payload())

    data = response.json()
    assert "created_by" not in data
    assert "is_published" not in data


def test_create_event_rejects_missing_required_fields():
    _override_current_user()
    _mock_db_for_create(make_mock_profile(role=UserRole.admin))

    response = client.post("/events", json={"title": "Only a title"})

    assert response.status_code == 422


def test_create_event_rejects_invalid_starts_at():
    _override_current_user()
    _mock_db_for_create(make_mock_profile(role=UserRole.admin))

    response = client.post(
        "/events", json=valid_event_payload(starts_at="not-a-datetime")
    )

    assert response.status_code == 422


@pytest.mark.parametrize("field", ["title", "location", "description"])
def test_create_event_rejects_blank_required_text_fields(field):
    _override_current_user()
    _mock_db_for_create(make_mock_profile(role=UserRole.admin))

    response = client.post("/events", json=valid_event_payload(**{field: ""}))

    assert response.status_code == 422


@pytest.mark.parametrize("field", ["title", "location", "description"])
def test_create_event_rejects_whitespace_only_required_text_fields(field):
    # min_length=1 alone would accept "   " -- EventCreate strips
    # whitespace before that check runs, so a whitespace-only value is
    # normalized to "" and rejected the same as an empty string.
    _override_current_user()
    _mock_db_for_create(make_mock_profile(role=UserRole.admin))

    response = client.post("/events", json=valid_event_payload(**{field: "   "}))

    assert response.status_code == 422


def test_create_event_rejects_ends_at_before_starts_at():
    _override_current_user()
    _mock_db_for_create(make_mock_profile(role=UserRole.admin))

    now = datetime.now(timezone.utc)
    response = client.post(
        "/events",
        json=valid_event_payload(
            starts_at=now.isoformat(), ends_at=(now - timedelta(hours=1)).isoformat()
        ),
    )

    assert response.status_code == 422


def test_create_event_rejects_ends_at_equal_to_starts_at():
    _override_current_user()
    _mock_db_for_create(make_mock_profile(role=UserRole.admin))

    now = datetime.now(timezone.utc)
    response = client.post(
        "/events",
        json=valid_event_payload(starts_at=now.isoformat(), ends_at=now.isoformat()),
    )

    assert response.status_code == 422


def test_create_event_rejects_naive_starts_at():
    _override_current_user()
    _mock_db_for_create(make_mock_profile(role=UserRole.admin))

    response = client.post(
        "/events", json=valid_event_payload(starts_at="2026-08-20T15:00:00")
    )

    assert response.status_code == 422


def test_create_event_rejects_naive_ends_at():
    _override_current_user()
    _mock_db_for_create(make_mock_profile(role=UserRole.admin))

    response = client.post(
        "/events",
        json=valid_event_payload(
            starts_at="2026-08-20T15:00:00+02:00", ends_at="2026-08-20T17:00:00"
        ),
    )

    assert response.status_code == 422


def test_create_event_accepts_timezone_aware_datetimes():
    _override_current_user()
    _mock_db_for_create(make_mock_profile(role=UserRole.admin))

    response = client.post(
        "/events",
        json=valid_event_payload(
            starts_at="2026-08-20T15:00:00+02:00",
            ends_at="2026-08-20T17:00:00+02:00",
        ),
    )

    assert response.status_code == 201


def test_create_event_rejects_client_supplied_created_by():
    _override_current_user()
    _mock_db_for_create(make_mock_profile(role=UserRole.admin))

    response = client.post(
        "/events", json=valid_event_payload(created_by=str(uuid.uuid4()))
    )

    assert response.status_code == 422


def test_create_event_rejects_client_supplied_is_published():
    _override_current_user()
    _mock_db_for_create(make_mock_profile(role=UserRole.admin))

    response = client.post("/events", json=valid_event_payload(is_published=True))

    assert response.status_code == 422


def test_create_event_rejects_arbitrary_extra_field():
    _override_current_user()
    _mock_db_for_create(make_mock_profile(role=UserRole.admin))

    response = client.post(
        "/events", json=valid_event_payload(unexpected_field="surprise")
    )

    assert response.status_code == 422


# --- GET /events/drafts: admin-only draft listing ---------------------------


def _mock_db_for_admin(profile):
    """A get_db override suitable for require_admin (db.get -> profile)."""
    mock_db = MagicMock()
    mock_db.get.return_value = profile
    app.dependency_overrides[get_db] = lambda: mock_db
    return mock_db


def _mock_db_for_admin_listing(profile, events):
    """Combines the require_admin db.get(...) lookup with a query result
    for db.execute(...).scalars().all(), the same shape GET /events uses.
    """
    mock_db = _mock_db_for_admin(profile)
    mock_db.execute.return_value.scalars.return_value.all.return_value = events
    return mock_db


def test_get_draft_events_requires_authentication():
    app.dependency_overrides.clear()
    response = client.get("/events/drafts")
    assert response.status_code == 401


def test_get_draft_events_rejects_authenticated_parent():
    _override_current_user()
    _mock_db_for_admin_listing(make_mock_profile(role=UserRole.parent), [])

    response = client.get("/events/drafts")

    assert response.status_code == 403


def test_get_draft_events_rejects_authenticated_user_without_profile():
    _override_current_user()
    _mock_db_for_admin_listing(None, [])

    response = client.get("/events/drafts")

    assert response.status_code == 403


def test_get_draft_events_returns_drafts_for_admin():
    _override_current_user()
    draft = make_mock_event(is_published=False, title="Draft Event")
    _mock_db_for_admin_listing(make_mock_profile(role=UserRole.admin), [draft])

    response = client.get("/events/drafts")

    assert response.status_code == 200
    data = response.json()
    assert len(data) == 1
    assert data[0]["title"] == "Draft Event"


def test_get_draft_events_empty_returns_empty_list():
    _override_current_user()
    _mock_db_for_admin_listing(make_mock_profile(role=UserRole.admin), [])

    response = client.get("/events/drafts")

    assert response.status_code == 200
    assert response.json() == []


def test_get_draft_events_does_not_expose_created_by():
    _override_current_user()
    draft = make_mock_event(is_published=False, created_by=uuid.uuid4())
    _mock_db_for_admin_listing(make_mock_profile(role=UserRole.admin), [draft])

    response = client.get("/events/drafts")

    data = response.json()
    assert "created_by" not in data[0]
    assert "is_published" not in data[0]


def test_get_draft_events_query_filters_unpublished_ordered_newest_first():
    _override_current_user()
    mock_db = _mock_db_for_admin_listing(make_mock_profile(role=UserRole.admin), [])

    client.get("/events/drafts")

    stmt = mock_db.execute.call_args[0][0]
    sql = str(stmt).lower()
    assert "is_published is false" in sql
    assert "order by events.created_at desc" in sql


def test_get_draft_events_query_has_no_starts_at_time_filter():
    # Unlike GET /events, drafts are not filtered by starts_at -- a
    # past-dated draft must still be listed here for review, even though
    # it can no longer be published (see publish_event tests below).
    _override_current_user()
    mock_db = _mock_db_for_admin_listing(make_mock_profile(role=UserRole.admin), [])

    client.get("/events/drafts")

    stmt = mock_db.execute.call_args[0][0]
    sql = str(stmt).lower()
    # `starts_at` itself is always present as a selected column; what
    # matters is that it's never used as a WHERE-clause time filter here,
    # unlike GET /events's `starts_at >= now()`.
    assert "starts_at >=" not in sql
    assert "now()" not in sql


# --- POST /events/{event_id}/publish: admin-only publishing -----------------


def _mock_db_for_publish(profile, event):
    """A get_db override suitable for require_admin (db.get -> profile)
    plus a single-event lookup for publish_event (db.get -> event).
    db.get is called twice with different model types (Profile, then
    Event), so it's routed by the model argument rather than call order.
    """
    mock_db = MagicMock()

    def _fake_get(model, _id):
        if model is Profile:
            return profile
        return event

    mock_db.get.side_effect = _fake_get
    app.dependency_overrides[get_db] = lambda: mock_db
    return mock_db


def test_publish_event_requires_authentication():
    app.dependency_overrides.clear()
    response = client.post(f"/events/{uuid.uuid4()}/publish")
    assert response.status_code == 401


def test_publish_event_rejects_authenticated_parent():
    _override_current_user()
    _mock_db_for_publish(make_mock_profile(role=UserRole.parent), make_mock_event())

    response = client.post(f"/events/{uuid.uuid4()}/publish")

    assert response.status_code == 403


def test_publish_event_rejects_authenticated_user_without_profile():
    _override_current_user()
    _mock_db_for_publish(None, make_mock_event())

    response = client.post(f"/events/{uuid.uuid4()}/publish")

    assert response.status_code == 403


def test_publish_event_returns_404_for_nonexistent_event():
    _override_current_user()
    _mock_db_for_publish(make_mock_profile(role=UserRole.admin), None)

    response = client.post(f"/events/{uuid.uuid4()}/publish")

    assert response.status_code == 404


def test_publish_event_sets_is_published_true_for_upcoming_draft():
    _override_current_user()
    now = datetime.now(timezone.utc)
    draft = make_mock_event(is_published=False, starts_at=now + timedelta(days=1))
    _mock_db_for_publish(make_mock_profile(role=UserRole.admin), draft)

    response = client.post(f"/events/{draft.id}/publish")

    assert response.status_code == 200
    assert draft.is_published is True


def test_publish_event_is_idempotent_for_already_published_upcoming_event():
    _override_current_user()
    now = datetime.now(timezone.utc)
    event = make_mock_event(is_published=True, starts_at=now + timedelta(days=1))
    _mock_db_for_publish(make_mock_profile(role=UserRole.admin), event)

    response = client.post(f"/events/{event.id}/publish")

    assert response.status_code == 200
    assert event.is_published is True


def test_publish_event_rejects_past_starts_at_with_409():
    _override_current_user()
    now = datetime.now(timezone.utc)
    draft = make_mock_event(is_published=False, starts_at=now - timedelta(hours=1))
    mock_db = _mock_db_for_publish(make_mock_profile(role=UserRole.admin), draft)

    response = client.post(f"/events/{draft.id}/publish")

    assert response.status_code == 409
    # Left untouched: rejected before any write.
    assert draft.is_published is False
    mock_db.commit.assert_not_called()


def test_publish_event_rejects_past_starts_at_even_if_already_published():
    _override_current_user()
    now = datetime.now(timezone.utc)
    event = make_mock_event(is_published=True, starts_at=now - timedelta(hours=1))
    mock_db = _mock_db_for_publish(make_mock_profile(role=UserRole.admin), event)

    response = client.post(f"/events/{event.id}/publish")

    assert response.status_code == 409
    mock_db.commit.assert_not_called()


def test_publish_event_uses_timezone_aware_utc_safe_comparison():
    # starts_at is genuinely in the past (in UTC terms), but represented
    # with a non-UTC offset -- a naive/incorrect comparison (e.g. against
    # a naive `datetime.now()`, or comparing raw wall-clock values without
    # normalizing offsets) could get this wrong. It must still be
    # rejected as past.
    _override_current_user()
    now_utc = datetime.now(timezone.utc)
    past_non_utc = (now_utc - timedelta(hours=1)).astimezone(
        timezone(timedelta(hours=5))
    )
    draft = make_mock_event(is_published=False, starts_at=past_non_utc)
    _mock_db_for_publish(make_mock_profile(role=UserRole.admin), draft)

    response = client.post(f"/events/{draft.id}/publish")

    assert response.status_code == 409


def test_publish_event_rejects_client_supplied_is_published():
    _override_current_user()
    now = datetime.now(timezone.utc)
    draft = make_mock_event(is_published=False, starts_at=now + timedelta(days=1))
    _mock_db_for_publish(make_mock_profile(role=UserRole.admin), draft)

    response = client.post(
        f"/events/{draft.id}/publish", json={"is_published": True}
    )

    assert response.status_code == 422


def test_publish_event_rejects_client_supplied_created_by():
    _override_current_user()
    now = datetime.now(timezone.utc)
    draft = make_mock_event(is_published=False, starts_at=now + timedelta(days=1))
    _mock_db_for_publish(make_mock_profile(role=UserRole.admin), draft)

    response = client.post(
        f"/events/{draft.id}/publish", json={"created_by": str(uuid.uuid4())}
    )

    assert response.status_code == 422


def test_publish_event_rejects_arbitrary_extra_field():
    _override_current_user()
    now = datetime.now(timezone.utc)
    draft = make_mock_event(is_published=False, starts_at=now + timedelta(days=1))
    _mock_db_for_publish(make_mock_profile(role=UserRole.admin), draft)

    response = client.post(
        f"/events/{draft.id}/publish", json={"unexpected_field": "surprise"}
    )

    assert response.status_code == 422


def test_publish_event_accepts_no_request_body():
    _override_current_user()
    now = datetime.now(timezone.utc)
    draft = make_mock_event(is_published=False, starts_at=now + timedelta(days=1))
    _mock_db_for_publish(make_mock_profile(role=UserRole.admin), draft)

    response = client.post(f"/events/{draft.id}/publish")

    assert response.status_code == 200


def test_publish_event_accepts_empty_json_object_body():
    _override_current_user()
    now = datetime.now(timezone.utc)
    draft = make_mock_event(is_published=False, starts_at=now + timedelta(days=1))
    _mock_db_for_publish(make_mock_profile(role=UserRole.admin), draft)

    response = client.post(f"/events/{draft.id}/publish", json={})

    assert response.status_code == 200


def test_publish_event_response_does_not_expose_created_by_or_is_published():
    _override_current_user()
    now = datetime.now(timezone.utc)
    draft = make_mock_event(is_published=False, starts_at=now + timedelta(days=1))
    _mock_db_for_publish(make_mock_profile(role=UserRole.admin), draft)

    response = client.post(f"/events/{draft.id}/publish")

    data = response.json()
    assert "created_by" not in data
    assert "is_published" not in data
