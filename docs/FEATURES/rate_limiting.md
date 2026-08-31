# API Rate Limiting

## Why this exists

A production-readiness audit found that the FastAPI backend had no rate
limiting at all -- every route, including unauthenticated ones, could be
called at unlimited frequency (Issue #83).

## Implementation

`app/core/rate_limit.py` uses the [`limits`](https://limits.readthedocs.io/)
library directly -- not a FastAPI/Starlette-specific wrapper such as
SlowAPI -- with a single in-memory fixed-window counter (`MemoryStorage` +
`FixedWindowRateLimiter`). Each route gets a small `Depends()`-based
dependency, wired the same way `get_db`/`get_current_user`/`require_admin`
already are (via each router's `dependencies=[...]`), rather than a
decorator-based mechanism. A caller that exceeds its limit gets
`429 Too Many Requests`.

### Why not SlowAPI

SlowAPI's `key_func` only ever receives the raw ASGI `Request`, not any
already-resolved FastAPI dependency value. Keying authenticated/admin
routes by verified identity without that would require verifying the JWT
a second time inside the key function, or making `get_current_user`/
`require_admin` stash the identity onto `request.state` as a side effect
purely to serve the rate limiter -- both add real coupling or cost this
design avoids. Using `limits` directly, wrapped in plain dependencies,
needs neither.

### Rate limiting is a separate concern from authorization

- **Public routes** key on `request.client.host` -- the ASGI server's own
  record of the TCP peer, never a client-controlled header. `X-Forwarded-For`
  and `X-Real-IP` are not read anywhere in this codebase and must not be:
  either is fully attacker-settable unless a trusted reverse proxy
  overwrites it first (see "Reverse-proxy considerations" below).
- **Authenticated routes** (`rate_limit_user`) key on the user id already
  resolved by `get_current_user`.
- **Admin routes** (`rate_limit_admin`) key on the admin `Profile.id`
  already resolved by `require_admin`.

Critically, the authenticated/admin rate-limit dependencies declare
`Depends(get_current_user)` / `Depends(require_admin)` as their own
sub-dependency -- the *same* function object the route itself already
depends on for authorization, not a re-implementation. FastAPI caches a
dependency's resolved value once per request (`Depends()` defaults to
`use_cache=True`), so no matter how many places in a single request's
dependency graph need that identity, the token is verified exactly once.
This also means a request that fails authentication or admin
authorization is rejected with `401`/`403` by those existing dependencies
*before* any rate-limit check runs -- rate limiting can never substitute
for, or leak information about, an authorization decision. A non-admin
hammering an admin route always gets `403`, never a `429` that would
imply "admin, but throttled."

Each rate-limit dependency also includes a `scope` string in its key
(e.g. `"me:read"` vs. `"me:bootstrap"`), so a single user's or IP's quota
on one endpoint is independent of their quota on another -- they don't
share a counter just because the identity is the same.

## Default limits

| Route | Limit | Keyed by | Reasoning |
|---|---|---|---|
| `GET /health` | exempt | -- | Hit by uptime/load-balancer health checks; must never appear down because of its own traffic. |
| `GET /resources`, `GET /resources/{id}`, `GET /events` | 60/minute | client IP | Zero-auth-cost, highest-volume surface -- the only place with no gate at all before this. Generous enough for normal browsing, tight enough to blunt naive scraping. |
| `GET /me` | 60/minute | verified user | Low-cost authenticated read; loose to avoid false positives against a user's own client. |
| `POST /me/bootstrap` | 10/minute | verified user | Idempotent but does a real write attempt; called ~once per signup plus occasional retries. |
| `GET /events/drafts` | 60/minute | verified admin | Admin-only; mostly a safety net against a buggy/runaway admin client, not an external attack surface (non-admins never get past `require_admin`). |
| `POST /events`, `POST /events/{id}/publish` | 20/minute | verified admin | Meaningful admin writes; plenty for real content workflows, curbs a compromised or buggy admin session. |
| `GET /reports` | 60/minute | verified admin | Report-specific admin read scope; separate from event drafts and all public/community quotas. |
| `PUT /reports/{id}/status` | 20/minute | verified admin | Report-specific admin write scope for terminal triage decisions. |
| `POST /posts` | 10/minute | verified user | Dedicated community-write quota limits spam and accidental repeated submissions without consuming other authenticated-route quotas. |
| `GET /posts/{id}/comments` | 60/minute | client IP | Public discussion reads use the existing public-read setting. |
| `POST /posts/{id}/comments` | 10/minute | verified user | Reuses the community-write setting with its own endpoint scope, so comment submissions do not consume the post-creation counter. |

These are starting points, configurable via `Settings`/`.env`
(`RATE_LIMIT_*`, see `backend/.env.example`) without a code change.

## Reverse-proxy considerations

`request.client.host` is correct today because nothing sits between the
ASGI server and the caller. This codebase does not parse
`X-Forwarded-For`/`X-Real-IP` anywhere, and must not start to, since
either header is fully client-controlled unless a trusted proxy
overwrites it first -- trusting them by default would let anyone bypass
IP-based limiting with a rotating fake header.

When a real reverse proxy or CDN is eventually placed in front of this
app, the fix belongs at the **ASGI server layer, not in application
code**: run uvicorn with `--proxy-headers --forwarded-allow-ips=<the
proxy's actual IP(s)>` (Starlette/Uvicorn's built-in
`ProxyHeadersMiddleware`). Configured this way, uvicorn only trusts
`X-Forwarded-For` when the connection genuinely comes from an
allow-listed proxy IP, and correctly overwrites `request.client.host`
with the real client address before the app ever sees the request. This
codebase's rate-limit key functions never need to change for that --
they always read `request.client.host` and are correct in both
topologies. There is no reverse proxy configured anywhere in this repo
today, so this step is deliberately deferred until a real deployment
target exists.

## Multi-worker / multi-instance limitation

**This is not correct once more than one process serves traffic.** Each
uvicorn worker (or each horizontally-scaled instance) holds its own
independent in-memory counters with no coordination between them -- a
configured "60/minute" limit becomes up to "60 × N/minute" in the worst
case across N processes, since each one only sees and limits its own
slice of load-balanced traffic.

This is not a live problem today: nothing in this repository runs more
than one process (no `--workers` flag anywhere, `dev.sh` and
`backend/README.md` both start exactly one `uvicorn` invocation, and
there is no deployment configuration in this repo at all). It is an
accepted, explicitly documented limitation of the current MVP, not an
oversight.

### Future upgrade path: shared storage

`limits` supports pluggable storage backends (in-memory, Redis,
Memcached, etc.) behind the same `Storage`/strategy interface used here.
When Vilvia actually moves to multiple workers or multiple instances,
the fix is to swap `MemoryStorage` in `app/core/rate_limit.py` for a
Redis-backed storage instance (plus adding a Redis client dependency and
provisioning a Redis instance at that point) -- the key functions,
per-route scopes, and configured limits do not need to change. Redis is
deliberately **not** introduced now: there is no existing shared
infrastructure, no evidence of horizontal scaling, and adding it purely
for rate limiting ahead of an actual need would be infrastructure the
project doesn't yet require.

## Login/sign-up brute-force protection is out of scope here

This backend has no login, sign-up, password-reset, or token-refresh
route. The Flutter client talks to Supabase Auth directly for all of
that; this backend only ever verifies an *already-issued* JWT (see
`docs/FEATURES/authentication.md`). Those requests never transit this
API, so **this backend cannot rate-limit brute-force authentication
attempts** -- that protection is Supabase Auth / Supabase Dashboard
configuration (password policy, leaked-password protection, Supabase's
own rate limits, CAPTCHA/bot protection), outside this codebase and
outside this issue's scope.
