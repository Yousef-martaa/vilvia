import uuid
from datetime import datetime

from pydantic import BaseModel, ConfigDict

from app.models.enums import ResourceCategory, ResourceStage


class ResourceResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    title: str
    summary: str
    category: ResourceCategory
    stage: ResourceStage
    source_name: str
    source_url: str
    created_at: datetime
    updated_at: datetime


class ResourceDetailResponse(ResourceResponse):
    """The single-resource response, used only by GET /resources/{id}.

    Includes the full article body -- deliberately excluded from
    ResourceResponse/GET /resources so the list endpoint stays lightweight
    as the catalog grows.
    """

    body: str
