from fastapi import APIRouter, Depends
from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.api.deps import get_db
from app.models.event import Event
from app.schemas.event import EventResponse

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
