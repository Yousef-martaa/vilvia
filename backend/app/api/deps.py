import uuid
from collections.abc import Generator
from dataclasses import dataclass

from fastapi import Header, HTTPException, status
from sqlalchemy.orm import Session

from app.core.auth import InvalidTokenError, verify_access_token
from app.core.database import SessionLocal


def get_db() -> Generator[Session, None, None]:
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()


@dataclass(frozen=True)
class AuthenticatedUser:
    """A verified Supabase identity -- nothing more than the token's own
    claims. Deliberately not a database model: resolving this to a
    Profile (or creating one) is the responsibility of the endpoints that
    need it (see app/routers/me.py), not of this dependency.
    """

    id: uuid.UUID
    email: str


def get_current_user(
    authorization: str | None = Header(default=None),
) -> AuthenticatedUser:
    """Verify the request's bearer token and return the caller's
    identity. Performs no database access -- see AuthenticatedUser.
    """
    credentials_error = HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail="Could not validate credentials",
        headers={"WWW-Authenticate": "Bearer"},
    )

    if not authorization:
        raise credentials_error

    scheme, _, token = authorization.partition(" ")
    if scheme.lower() != "bearer" or not token:
        raise credentials_error

    try:
        claims = verify_access_token(token)
    except InvalidTokenError:
        raise credentials_error from None

    subject = claims.get("sub")
    email = claims.get("email")
    if not subject or not email:
        raise credentials_error

    try:
        user_id = uuid.UUID(subject)
    except ValueError:
        raise credentials_error from None

    return AuthenticatedUser(id=user_id, email=email)
