import logging

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.dialects.postgresql import insert as pg_insert
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.api.deps import AuthenticatedUser, get_current_user, get_db
from app.core.rate_limit import rate_limit_user
from app.core.settings import settings
from app.models.enums import UserRole
from app.models.profile import Profile
from app.schemas.profile import BootstrapRequest, ProfileResponse

log = logging.getLogger(__name__)

router = APIRouter(prefix="/me", tags=["me"])


@router.get(
    "",
    response_model=ProfileResponse,
    dependencies=[
        Depends(rate_limit_user("me:read", settings.rate_limit_me_read_per_minute))
    ],
)
def get_me(
    current_user: AuthenticatedUser = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> Profile:
    """Read-only. Returns the caller's Profile if one exists; never
    creates one -- see POST /me/bootstrap for provisioning.
    """
    profile = db.get(Profile, current_user.id)
    if profile is None:
        raise HTTPException(
            status_code=404,
            detail="No profile exists for this account yet. Complete sign-up first.",
        )
    return profile


@router.post(
    "/bootstrap",
    response_model=ProfileResponse,
    dependencies=[
        Depends(
            rate_limit_user("me:bootstrap", settings.rate_limit_me_bootstrap_per_minute)
        )
    ],
)
def bootstrap_profile(
    body: BootstrapRequest,
    current_user: AuthenticatedUser = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> Profile:
    """Idempotently provisions the caller's own Profile.

    The profile id and email always come from the verified identity, not
    the client. `role` is always `parent` -- there is no client input
    that can set it (BootstrapRequest has no `role` field at all).

    Safe under concurrent duplicate calls: the insert is a no-op on
    conflict (keyed on the primary key, which is the verified user id),
    and the row is always read back afterwards regardless of whether this
    call or a concurrent one created it -- so two racing bootstrap calls
    both succeed and both return the same, single row.

    `Profile.email` is also unique, but that is *not* the conflict target
    here -- only `id` is. If the verified email already belongs to a
    different existing profile (a different id), Postgres raises a real
    IntegrityError rather than silently no-op-ing, which is caught below:
    the transaction is rolled back (so the session isn't left aborted)
    and a clear 409 is returned instead of a raw 500.
    """
    stmt = (
        pg_insert(Profile)
        .values(
            id=current_user.id,
            first_name=body.first_name,
            email=current_user.email,
            role=UserRole.parent,
            gender=body.gender,
        )
        .on_conflict_do_nothing(index_elements=[Profile.id])
    )
    try:
        result = db.execute(stmt)
        db.commit()
    except IntegrityError:
        db.rollback()
        log.warning("bootstrap conflict: email already belongs to a different profile")
        raise HTTPException(
            status_code=409,
            detail="This email is already associated with a different account.",
        ) from None

    # rowcount is 1 only when this call actually inserted the row (not a
    # no-op against an already-existing one) -- log id only, no email/PII.
    if result.rowcount:
        log.info("profile bootstrapped id=%s", current_user.id)

    profile = db.get(Profile, current_user.id)
    if profile is None:
        # Should be unreachable: the statement above either inserted this
        # row or no-opped against an already-existing one, so a row
        # should always be readable here. Fail explicitly rather than
        # with an AssertionError (which can be stripped under -O) if it
        # ever isn't.
        raise HTTPException(
            status_code=500,
            detail="Failed to provision profile.",
        )
    return profile
