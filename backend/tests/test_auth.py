"""Tests for token verification (app/core/auth.py) and the get_current_user
dependency (app/api/deps.py).

verify_access_token is tested against a real, locally-generated ES256
keypair -- tokens are genuinely signed and genuinely cryptographically
verified, with only the JWKS *fetch* step mocked out (no network call to
Supabase), so these tests exercise the real verification logic, not a
bypass.
"""

import time
import uuid

import jwt
import pytest
from cryptography.hazmat.primitives.asymmetric import ec
from fastapi import HTTPException

import app.api.deps as deps_module
import app.core.auth as auth_module
from app.api.deps import AuthenticatedUser, get_current_user
from app.core.auth import InvalidTokenError, verify_access_token


class _FakeSigningKey:
    def __init__(self, public_key):
        self.key = public_key


@pytest.fixture
def keypair():
    private_key = ec.generate_private_key(ec.SECP256R1())
    return private_key, private_key.public_key()


@pytest.fixture(autouse=True)
def patch_jwks(monkeypatch, keypair):
    _, public_key = keypair
    monkeypatch.setattr(
        auth_module._jwks_client,
        "get_signing_key_from_jwt",
        lambda token: _FakeSigningKey(public_key),
    )


def _make_token(private_key, **overrides):
    now = int(time.time())
    payload = {
        "sub": str(uuid.uuid4()),
        "email": "parent@example.com",
        "role": "authenticated",
        "iss": auth_module._EXPECTED_ISSUER,
        "aud": auth_module._EXPECTED_AUDIENCE,
        "exp": now + 3600,
        "iat": now,
    }
    payload.update(overrides)
    return jwt.encode(payload, private_key, algorithm="ES256")


# --- verify_access_token ---------------------------------------------


def test_valid_token_returns_claims(keypair):
    private_key, _ = keypair
    claims = verify_access_token(_make_token(private_key))
    assert claims["role"] == "authenticated"
    assert claims["email"] == "parent@example.com"


def test_expired_token_is_rejected(keypair):
    private_key, _ = keypair
    token = _make_token(private_key, exp=int(time.time()) - 10)
    with pytest.raises(InvalidTokenError):
        verify_access_token(token)


def test_wrong_issuer_is_rejected(keypair):
    private_key, _ = keypair
    token = _make_token(
        private_key, iss="https://not-our-project.supabase.co/auth/v1"
    )
    with pytest.raises(InvalidTokenError):
        verify_access_token(token)


def test_wrong_audience_is_rejected(keypair):
    private_key, _ = keypair
    token = _make_token(private_key, aud="something-else")
    with pytest.raises(InvalidTokenError):
        verify_access_token(token)


def test_anon_role_token_is_rejected(keypair):
    """An anon-key-shaped token must not be usable as a user identity."""
    private_key, _ = keypair
    token = _make_token(private_key, role="anon")
    with pytest.raises(InvalidTokenError):
        verify_access_token(token)


def test_service_role_token_is_rejected(keypair):
    """A service-role-key-shaped token must not be usable as a user
    identity."""
    private_key, _ = keypair
    token = _make_token(private_key, role="service_role")
    with pytest.raises(InvalidTokenError):
        verify_access_token(token)


def test_token_signed_with_a_different_key_is_rejected():
    other_private_key = ec.generate_private_key(ec.SECP256R1())
    # Signed with a key that is NOT the one `patch_jwks` exposes as the
    # trusted public key for this test.
    token = _make_token(other_private_key)
    with pytest.raises(InvalidTokenError):
        verify_access_token(token)


def test_malformed_token_is_rejected():
    with pytest.raises(InvalidTokenError):
        verify_access_token("not-a-real-jwt")


# --- get_current_user --------------------------------------------------


def test_missing_authorization_header_is_401():
    with pytest.raises(HTTPException) as exc_info:
        get_current_user(authorization=None)
    assert exc_info.value.status_code == 401


def test_non_bearer_scheme_is_401():
    with pytest.raises(HTTPException) as exc_info:
        get_current_user(authorization="Basic dXNlcjpwYXNz")
    assert exc_info.value.status_code == 401


def test_bearer_with_no_token_is_401():
    with pytest.raises(HTTPException) as exc_info:
        get_current_user(authorization="Bearer ")
    assert exc_info.value.status_code == 401


def test_invalid_token_is_401(monkeypatch):
    def raise_invalid(token):
        raise InvalidTokenError("simulated failure")

    monkeypatch.setattr(deps_module, "verify_access_token", raise_invalid)

    with pytest.raises(HTTPException) as exc_info:
        get_current_user(authorization="Bearer sometoken")
    assert exc_info.value.status_code == 401


def test_valid_token_resolves_to_authenticated_user(monkeypatch):
    user_id = uuid.uuid4()
    monkeypatch.setattr(
        deps_module,
        "verify_access_token",
        lambda token: {"sub": str(user_id), "email": "parent@example.com"},
    )

    result = get_current_user(authorization="Bearer sometoken")

    assert result == AuthenticatedUser(id=user_id, email="parent@example.com")


def test_token_missing_email_claim_is_401(monkeypatch):
    monkeypatch.setattr(
        deps_module,
        "verify_access_token",
        lambda token: {"sub": str(uuid.uuid4())},
    )

    with pytest.raises(HTTPException) as exc_info:
        get_current_user(authorization="Bearer sometoken")
    assert exc_info.value.status_code == 401
