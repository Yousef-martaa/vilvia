import logging
import uuid
from collections.abc import Generator
from dataclasses import dataclass

from fastapi import Depends, Header, HTTPException, status
from sqlalchemy.orm import Session

from app.core.auth import InvalidTokenError, verify_access_token
from app.core.database import SessionLocal
from app.models.account_deletion_request import AccountDeletionRequest
from app.models.enums import AccountDeletionStatus, UserRole
from app.models.profile import Profile

log = logging.getLogger(__name__)


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


def get_optional_current_user(
    authorization: str | None = Header(default=None),
) -> AuthenticatedUser | None:
    """Return no identity when no credentials were supplied.

    A supplied bearer token is still verified normally, so malformed or
    invalid credentials never silently downgrade a caller to anonymous.
    """
    if authorization is None:
        return None
    return get_current_user(authorization)


def ensure_account_active(
    current_user: AuthenticatedUser,
    db: Session,
    *,
    serialize_mutation: bool = False,
) -> None:
    ensure_user_id_active(
        current_user.id, db, serialize_mutation=serialize_mutation
    )


def ensure_user_id_active(
    user_id: uuid.UUID,
    db: Session,
    *,
    serialize_mutation: bool = False,
) -> None:
    """Reject authenticated mutations after account deletion is requested.

    Reads remain available while an operator processes the request, but no
    endpoint using this dependency may create or alter user-owned data.

    Global mutation lock order is: account advisory barrier, then domain row
    locks. Community domain locks must continue Post -> Comment -> Report.
    Every future authenticated mutation must call this with
    ``serialize_mutation=True`` before acquiring any domain row lock.
    """
    if serialize_mutation:
        # Request creation takes the same transaction-scoped lock. This drains
        # an earlier in-flight write and makes a later write re-check the
        # durable request before mutating. Using the underlying connection
        # keeps this coordination separate from Community's row-query order.
        advisory_key = int.from_bytes(user_id.bytes[:8], signed=True)
        db.connection().exec_driver_sql(
            "SELECT pg_advisory_xact_lock(%s)", (advisory_key,)
        )

    deletion_request = db.get(AccountDeletionRequest, user_id)
    if getattr(deletion_request, "status", None) in {
        AccountDeletionStatus.requested,
        AccountDeletionStatus.auth_deleted,
        AccountDeletionStatus.completed,
    }:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Account deletion has been requested.",
        )


def require_admin(
    current_user: AuthenticatedUser = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> Profile:
    """Require the caller's Profile to have role == UserRole.admin.

    Resolves the Profile server-side from the verified identity -- never
    from client-supplied input, so there is no way for a request to claim
    admin status for itself. A missing Profile is treated the same as a
    non-admin one (403), not a distinct error: not-yet-provisioned and
    not-an-admin both mean "not authorized" here.

    Not currently used by any route -- added now, ahead of the first
    privileged endpoint, so that endpoint can depend on this directly
    instead of inventing an authorization check under pressure. See
    docs/FEATURES/authentication.md.
    """
    profile = db.get(Profile, current_user.id)
    if profile is None or profile.role != UserRole.admin:
        log.warning("admin access denied for user id=%s", current_user.id)
        raise HTTPException(status_code=403, detail="Admin access required")
    ensure_user_id_active(current_user.id, db)
    return profile
