"""Tests for API rate limiting (Issue #83, app/core/rate_limit.py).

Deterministic and sleep-free: exceeding a fixed-window limit is proven by
firing `limit + 1` requests within a single test (no need to wait for a
window to elapse), and an autouse fixture resets the real in-memory
`limits` storage before and after every test in this file so tests never
leak state into each other or into other test modules that share the
same process-wide storage instance.
"""

import uuid
from datetime import datetime, timezone
from unittest.mock import MagicMock

import pytest
from fastapi.testclient import TestClient

import app.api.deps as deps_module
from app.api.deps import AuthenticatedUser, get_current_user, get_db
from app.core.rate_limit import reset_rate_limit_storage
from app.core.settings import settings
from app.main import app
from app.models.enums import UserRole

client = TestClient(app)


@pytest.fixture(autouse=True)
def _isolate_rate_limit_state():
    reset_rate_limit_storage()
    yield
    app.dependency_overrides.clear()
    reset_rate_limit_storage()


def _override_current_user(user_id=None, email="parent@example.com"):
    user = AuthenticatedUser(id=user_id or uuid.uuid4(), email=email)
    app.dependency_overrides[get_current_user] = lambda: user
    return user


def _full_profile(user_id, role=UserRole.parent):
    profile = MagicMock()
    profile.id = user_id
    profile.first_name = "Rowan"
    profile.email = "parent@example.com"
    profile.role = role
    profile.gender = None
    profile.created_at = datetime.now(timezone.utc)
    profile.updated_at = datetime.now(timezone.utc)
    return profile


def _mock_db_with_profile(profile):
    mock_db = MagicMock()
    mock_db.get.return_value = profile
    app.dependency_overrides[get_db] = lambda: mock_db
    return mock_db


def _mock_db_for_admin_listing(profile, events=None):
    mock_db = MagicMock()
    mock_db.get.return_value = profile
    mock_db.execute.return_value.scalars.return_value.all.return_value = events or []
    app.dependency_overrides[get_db] = lambda: mock_db
    return mock_db


def _mock_db_returning_resources(resources):
    mock_db = MagicMock()
    mock_db.execute.return_value.scalars.return_value.all.return_value = resources
    app.dependency_overrides[get_db] = lambda: mock_db
    return mock_db


# --- exceeding the limit returns 429 -----------------------------------


def test_public_route_returns_429_after_exceeding_the_limit():
    limit = settings.rate_limit_public_per_minute
    ip_client = TestClient(app, client=("203.0.113.10", 12345))
    _mock_db_returning_resources([])

    statuses = [ip_client.get("/resources").status_code for _ in range(limit + 1)]

    assert statuses[:limit] == [200] * limit
    assert statuses[limit] == 429


def test_authenticated_route_returns_429_after_exceeding_the_limit():
    limit = settings.rate_limit_me_read_per_minute
    user = _override_current_user()
    _mock_db_with_profile(_full_profile(user.id))

    statuses = [client.get("/me").status_code for _ in range(limit + 1)]

    assert statuses[:limit] == [200] * limit
    assert statuses[limit] == 429


def test_admin_route_returns_429_after_exceeding_the_limit():
    limit = settings.rate_limit_admin_read_per_minute
    user = _override_current_user()
    _mock_db_for_admin_listing(_full_profile(user.id, role=UserRole.admin), [])

    statuses = [client.get("/events/drafts").status_code for _ in range(limit + 1)]

    assert statuses[:limit] == [200] * limit
    assert statuses[limit] == 429


# --- /health is exempt ---------------------------------------------------


def test_health_is_exempt_from_rate_limiting():
    limit = settings.rate_limit_public_per_minute
    statuses = [client.get("/health").status_code for _ in range(limit + 5)]
    assert statuses == [200] * (limit + 5)


# --- IP-spoofing resistance ------------------------------------------------


def test_spoofed_x_forwarded_for_does_not_bypass_the_ip_based_limit():
    limit = settings.rate_limit_public_per_minute
    ip_client = TestClient(app, client=("198.51.100.20", 40000))
    _mock_db_returning_resources([])

    statuses = []
    for i in range(limit + 1):
        # A different spoofed address on every request -- if
        # X-Forwarded-For were trusted, each request would land in its
        # own bucket and this limit would never be reached.
        response = ip_client.get(
            "/resources", headers={"X-Forwarded-For": f"10.0.0.{i % 250}"}
        )
        statuses.append(response.status_code)

    assert statuses[:limit] == [200] * limit
    assert statuses[limit] == 429


# --- keying: user id vs. IP -------------------------------------------------


def test_two_verified_users_on_the_same_ip_have_independent_quotas():
    limit = settings.rate_limit_me_read_per_minute
    user_a = _override_current_user()
    _mock_db_with_profile(_full_profile(user_a.id))

    statuses = [client.get("/me").status_code for _ in range(limit)]
    assert statuses == [200] * limit
    assert client.get("/me").status_code == 429  # user A's quota is spent

    user_b = _override_current_user()  # same TestClient/IP, different user
    _mock_db_with_profile(_full_profile(user_b.id))

    assert client.get("/me").status_code == 200  # user B is unaffected


def test_same_verified_user_across_different_ips_shares_one_quota():
    limit = settings.rate_limit_me_read_per_minute
    user = _override_current_user()
    _mock_db_with_profile(_full_profile(user.id))

    client_ip1 = TestClient(app, client=("203.0.113.50", 1))
    client_ip2 = TestClient(app, client=("203.0.113.60", 2))

    half = limit // 2
    for _ in range(half):
        assert client_ip1.get("/me").status_code == 200
    for _ in range(limit - half):
        assert client_ip2.get("/me").status_code == 200

    # The combined total across both simulated IPs already exhausted the
    # single per-user quota -- one more request from either IP is 429.
    assert client_ip1.get("/me").status_code == 429


# --- authorization precedes rate limiting -----------------------------------


def test_401_precedes_authenticated_rate_limiting():
    limit = settings.rate_limit_me_read_per_minute
    # No auth override at all -- every request is genuinely unauthenticated.
    statuses = [client.get("/me").status_code for _ in range(limit + 5)]
    assert statuses == [401] * (limit + 5)


def test_403_precedes_admin_rate_limiting():
    limit = settings.rate_limit_admin_read_per_minute
    user = _override_current_user()
    _mock_db_for_admin_listing(_full_profile(user.id, role=UserRole.parent), [])

    statuses = [client.get("/events/drafts").status_code for _ in range(limit + 5)]
    assert statuses == [403] * (limit + 5)


# --- no duplicate JWT verification ------------------------------------------


def test_verify_access_token_is_called_once_per_authenticated_request(monkeypatch):
    calls = []

    def _counting_verify(token):
        calls.append(token)
        return {"sub": str(uuid.uuid4()), "email": "parent@example.com"}

    # Deliberately does NOT override get_current_user itself -- the real
    # dependency must run so this proves FastAPI's per-request dependency
    # cache (not a test-only bypass) is what prevents double verification,
    # even though both the route's own `current_user` parameter and the
    # rate-limit dependency each declare Depends(get_current_user).
    monkeypatch.setattr(deps_module, "verify_access_token", _counting_verify)
    _mock_db_with_profile(_full_profile(uuid.uuid4()))

    response = client.get("/me", headers={"Authorization": "Bearer sometoken"})

    assert response.status_code == 200
    assert len(calls) == 1


# --- test isolation: no leaked state between tests --------------------------


def test_rate_limit_storage_resets_between_tests_case_a_exhausts_quota():
    limit = settings.rate_limit_public_per_minute
    ip_client = TestClient(app, client=("192.0.2.99", 5000))
    _mock_db_returning_resources([])

    statuses = [ip_client.get("/resources").status_code for _ in range(limit)]
    assert statuses == [200] * limit
    assert ip_client.get("/resources").status_code == 429


def test_rate_limit_storage_resets_between_tests_case_b_starts_fresh():
    # Reuses the exact same simulated IP that the test above fully
    # exhausted. If the autouse fixture did not reset in-memory
    # rate-limit storage between tests, this request would already be
    # 429 instead of 200.
    ip_client = TestClient(app, client=("192.0.2.99", 5000))
    _mock_db_returning_resources([])

    assert ip_client.get("/resources").status_code == 200
