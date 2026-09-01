"""Verification of Supabase-issued access tokens.

Uses the project's public JWKS endpoint (asymmetric JWT signing keys --
https://supabase.com/docs/guides/auth/signing-keys) to verify signatures
locally, with no secret/service-role key and no call to Supabase at
request time (PyJWKClient caches the fetched keys). Also validates
issuer, expiry, and audience, and explicitly rejects any token whose
`role` claim isn't "authenticated" -- Supabase's anon/service-role API
keys are themselves static JWTs and must never be accepted as an
ordinary authenticated user's identity.

This module only verifies tokens and returns their claims. It performs no
database access and does not resolve a token to application data -- see
app/api/deps.py for how a verified token becomes a usable identity, and
app/routers/me.py for how that identity is (or isn't) resolved to a
Profile.
"""

from __future__ import annotations

import jwt
from jwt import PyJWKClient

from app.core.settings import settings

_EXPECTED_ISSUER = f"{settings.supabase_url}/auth/v1"
_EXPECTED_AUDIENCE = "authenticated"
_JWKS_URL = f"{settings.supabase_url}/auth/v1/.well-known/jwks.json"

# A single module-level client so its key cache is actually shared across
# requests, rather than re-fetching the JWKS endpoint every time.
_jwks_client = PyJWKClient(_JWKS_URL)


class InvalidTokenError(Exception):
    """Raised for any token that fails verification, for any reason.

    Deliberately one exception type: callers should not distinguish *why*
    verification failed (expired vs. bad signature vs. wrong issuer vs.
    wrong audience, etc.), only that it did -- so a caller mapping this to
    an HTTP response can't accidentally leak which specific check failed.
    """


def verify_access_token(token: str) -> dict:
    """Verify a Supabase-issued access token and return its claims.

    Raises InvalidTokenError for a missing/invalid signature, wrong
    issuer, expiry, wrong audience, or a token whose role claim isn't
    "authenticated".
    """
    try:
        signing_key = _jwks_client.get_signing_key_from_jwt(token)
        claims = jwt.decode(
            token,
            signing_key.key,
            algorithms=["ES256"],
            issuer=_EXPECTED_ISSUER,
            audience=_EXPECTED_AUDIENCE,
            leeway=settings.supabase_jwt_clock_skew_seconds,
            options={"require": ["exp", "iat"]},
        )
    except jwt.PyJWTError as exc:
        raise InvalidTokenError(str(exc)) from exc

    if claims.get("role") != "authenticated":
        raise InvalidTokenError("token is not an authenticated-user session")

    try:
        token_lifetime = claims["exp"] - claims["iat"]
    except (KeyError, TypeError):
        raise InvalidTokenError("token lifetime claims are invalid") from None
    if token_lifetime > settings.supabase_access_token_max_lifetime_seconds:
        raise InvalidTokenError("token lifetime exceeds the accepted maximum")

    return claims
