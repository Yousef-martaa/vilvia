from fastapi import APIRouter, Depends, status
from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.api.deps import get_db, require_admin
from app.models.event import Event
from app.models.profile import Profile
from app.schemas.event import EventCreate, EventResponse

router = APIRouter(prefix="/events", tags=["events"])


@router.get("", response_model=list[EventResponse])
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


@router.post("", response_model=EventResponse, status_code=status.HTTP_201_CREATED)
def create_event(
    body: EventCreate,
    admin_profile: Profile = Depends(require_admin),
    db: Session = Depends(get_db),
) -> Event:
    """Admin-only. Creates a draft Event -- creation and publication are
    separate operations (see docs/FEATURES/events.md): `is_published` is
    always `False` here and is not client-settable. A later issue is
    expected to add the explicit review/publish capability.

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
