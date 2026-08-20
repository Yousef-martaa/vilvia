import uuid
from datetime import datetime, timezone

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.api.deps import get_db, require_admin
from app.core.rate_limit import rate_limit_admin, rate_limit_public
from app.core.settings import settings
from app.models.event import Event
from app.models.profile import Profile
from app.schemas.event import EventCreate, EventPublishRequest, EventResponse

router = APIRouter(prefix="/events", tags=["events"])


@router.get(
    "",
    response_model=list[EventResponse],
    dependencies=[
        Depends(rate_limit_public("events:list", settings.rate_limit_public_per_minute))
    ],
)
def get_events(db: Session = Depends(get_db)) -> list[EventResponse]:
    result = db.execute(
        select(Event)
        .where(
            Event.is_published.is_(True),
            Event.starts_at >= func.now(),
        )
        .order_by(Event.starts_at.asc())
    )
    return result.scalars().all()


@router.get(
    "/drafts",
    response_model=list[EventResponse],
    dependencies=[
        Depends(
            rate_limit_admin("events:drafts", settings.rate_limit_admin_read_per_minute)
        )
    ],
)
def get_draft_events(
    admin_profile: Profile = Depends(require_admin),
    db: Session = Depends(get_db),
) -> list[EventResponse]:
    """Admin-only. Every unpublished Event, newest-created first --
    deliberately unfiltered by `starts_at` (unlike GET /events), so a
    past-dated draft still shows up here for review even though
    publishing it is rejected (see publish_event below).
    """
    result = db.execute(
        select(Event)
        .where(Event.is_published.is_(False))
        .order_by(Event.created_at.desc())
    )
    return result.scalars().all()


@router.post(
    "",
    response_model=EventResponse,
    status_code=status.HTTP_201_CREATED,
    dependencies=[
        Depends(
            rate_limit_admin("events:create", settings.rate_limit_admin_write_per_minute)
        )
    ],
)
def create_event(
    body: EventCreate,
    admin_profile: Profile = Depends(require_admin),
    db: Session = Depends(get_db),
) -> Event:
    """Admin-only. Creates a draft Event -- creation and publication are
    separate operations (see docs/FEATURES/events.md): `is_published` is
    always `False` here and is not client-settable. See publish_event
    below for the explicit review/publish step.

    `created_by` is always the caller's own Profile, resolved server-side
    by `require_admin` from the verified identity -- EventCreate has no
    `created_by` field, so there is no client input path to set it.
    """
    event = Event(
        title=body.title,
        description=body.description,
        location=body.location,
        starts_at=body.starts_at,
        ends_at=body.ends_at,
        created_by=admin_profile.id,
        is_published=False,
    )
    db.add(event)
    db.commit()
    db.refresh(event)
    return event


@router.post(
    "/{event_id}/publish",
    response_model=EventResponse,
    dependencies=[
        Depends(
            rate_limit_admin(
                "events:publish", settings.rate_limit_admin_write_per_minute
            )
        )
    ],
)
def publish_event(
    event_id: uuid.UUID,
    _body: EventPublishRequest | None = None,
    admin_profile: Profile = Depends(require_admin),
    db: Session = Depends(get_db),
) -> Event:
    """Admin-only. Idempotent: publishing an Event that's already
    published (and still upcoming) succeeds without further effect.

    Rejects (409) publishing an Event whose `starts_at` has already
    passed, leaving it untouched -- checked, and rejected, before any
    write. GET /events would never show it anyway (it also filters
    `starts_at >= now()`), so a "successful" publish that can never
    become visible would just be a confusing dead end for the admin.

    Comparison is timezone-aware (`starts_at` is always tz-aware, per
    EventCreate's validator) against `datetime.now(timezone.utc)`, so
    this is correct regardless of the offset the value was stored with.

    `_body` takes no real input -- see EventPublishRequest -- it exists
    only so a client-supplied field (e.g. `is_published`, `created_by`)
    is rejected with 422 rather than silently ignored.
    """
    event = db.get(Event, event_id)
    if event is None:
        raise HTTPException(status_code=404, detail="Event not found")

    if event.starts_at < datetime.now(timezone.utc):
        raise HTTPException(
            status_code=409,
            detail="Cannot publish an Event whose start time is already in the past.",
        )

    event.is_published = True
    db.commit()
    db.refresh(event)
    return event
