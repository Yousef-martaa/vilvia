import uuid
from datetime import datetime

from pydantic import BaseModel, ConfigDict


class EventResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    title: str
    description: str
    location: str
    starts_at: datetime
    ends_at: datetime | None
    created_at: datetime
    updated_at: datetime
