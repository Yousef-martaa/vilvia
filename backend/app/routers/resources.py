import uuid

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.api.deps import get_db
from app.core.rate_limit import rate_limit_public
from app.core.settings import settings
from app.models.resource import Resource
from app.schemas.resource import ResourceDetailResponse, ResourceResponse

router = APIRouter(prefix="/resources", tags=["resources"])


@router.get(
    "",
    response_model=list[ResourceResponse],
    dependencies=[
        Depends(
            rate_limit_public("resources:list", settings.rate_limit_public_per_minute)
        )
    ],
)
def get_resources(db: Session = Depends(get_db)) -> list[ResourceResponse]:
    result = db.execute(
        select(Resource)
        .where(Resource.is_published.is_(True))
        .order_by(Resource.created_at.desc())
    )
    return result.scalars().all()


@router.get(
    "/{resource_id}",
    response_model=ResourceDetailResponse,
    dependencies=[
        Depends(
            rate_limit_public(
                "resources:detail", settings.rate_limit_public_per_minute
            )
        )
    ],
)
def get_resource(resource_id: uuid.UUID, db: Session = Depends(get_db)) -> Resource:
    resource = db.execute(
        select(Resource).where(
            Resource.id == resource_id,
            Resource.is_published.is_(True),
        )
    ).scalar_one_or_none()

    if resource is None:
        # A nonexistent id and an unpublished resource are indistinguishable
        # to a caller, and deliberately so -- an unpublished resource should
        # not be revealed to exist via a different status code.
        raise HTTPException(status_code=404, detail="Resource not found")

    return resource
