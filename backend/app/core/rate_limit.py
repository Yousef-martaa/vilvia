"""API rate limiting (Issue #83).

Uses the `limits` library directly -- not a FastAPI/Starlette-specific
wrapper such as SlowAPI -- with a single in-memory fixed-window counter.
This is correct only for a single process; see
docs/FEATURES/rate_limiting.md for the documented multi-worker/
multi-instance limitation and the future Redis-backed upgrade path.

Rate limiting is deliberately kept a separate concern from authorization:

- Public routes key on `request.client.host`, the ASGI server's own record
  of the TCP peer. This is never client-controlled -- `X-Forwarded-For`
  and `X-Real-IP` are not read anywhere in this module, and must not be,
  since either is fully attacker-settable unless a trusted reverse proxy
  overwrites it first (see docs/FEATURES/rate_limiting.md).
- Authenticated/admin routes key on the identity already resolved by
  `get_current_user` / `require_admin`. Each dependency below depends on
  that *same* function object, so FastAPI's per-request dependency cache
  (Depends() results are resolved at most once per request) guarantees
  the token is verified exactly once per request no matter how many
  dependencies need the identity -- this module never calls
  `verify_access_token` itself. A caller that fails authentication or
  admin authorization is rejected by those existing dependencies (401 /
  403) before any rate-limit check runs, so a 429 can never substitute
  for, or leak information about, an authorization decision.
"""

from fastapi import Depends, HTTPException, Request, status
from limits import RateLimitItemPerMinute
from limits.storage import MemoryStorage
from limits.strategies import FixedWindowRateLimiter

from app.api.deps import AuthenticatedUser, get_current_user, require_admin
from app.core.settings import settings
from app.models.profile import Profile

_storage = MemoryStorage()
_strategy = FixedWindowRateLimiter(_storage)


def _enforce(item: RateLimitItemPerMinute, key: str) -> None:
    if not settings.rate_limit_enabled:
        return
    if not _strategy.hit(item, key):
        raise HTTPException(
            status_code=status.HTTP_429_TOO_MANY_REQUESTS,
            detail="Rate limit exceeded. Please try again later.",
        )


def rate_limit_public(scope: str, per_minute: int):
    """Per-IP limit for an unauthenticated route.

    `scope` namespaces the counter to this specific endpoint so it never
    shares a quota with another public route for the same caller.
    """
    item = RateLimitItemPerMinute(per_minute)

    def dependency(request: Request) -> None:
        host = request.client.host if request.client else "unknown"
        _enforce(item, f"{scope}:ip:{host}")

    return dependency


def rate_limit_user(scope: str, per_minute: int):
    """Per-verified-user limit for an authenticated route.

    Depends on `get_current_user` -- the same dependency the route itself
    (or another dependency of it) already uses -- so this never triggers
    a second JWT verification.
    """
    item = RateLimitItemPerMinute(per_minute)

    def dependency(
        current_user: AuthenticatedUser = Depends(get_current_user),
    ) -> None:
        _enforce(item, f"{scope}:user:{current_user.id}")

    return dependency


def rate_limit_admin(scope: str, per_minute: int):
    """Per-verified-admin limit for an admin-only route.

    Depends on `require_admin` -- the same dependency the route itself
    already uses to authorize the request -- so a non-admin caller is
    rejected with 403 by `require_admin` before this check ever runs, and
    no second JWT verification or admin-status lookup occurs.
    """
    item = RateLimitItemPerMinute(per_minute)

    def dependency(admin_profile: Profile = Depends(require_admin)) -> None:
        _enforce(item, f"{scope}:admin:{admin_profile.id}")

    return dependency


def reset_rate_limit_storage() -> None:
    """Test-only: clears all counters so tests are isolated from each
    other without sleeping or depending on real elapsed time.
    """
    _storage.reset()
