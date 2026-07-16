from fastapi import APIRouter, Depends
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.api.deps import get_db
from app.models.resource import Resource
from app.schemas.resource import ResourceResponse

router = APIRouter(prefix="/resources", tags=["resources"])


@router.get("", response_model=list[ResourceResponse])
def get_resources(db: Session = Depends(get_db)) -> list[ResourceResponse]:
    result = db.execute(
        select(Resource)
        .where(Resource.is_published.is_(True))
        .order_by(Resource.created_at.desc())
    )
    return result.scalars().all()
