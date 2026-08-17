import uuid
from datetime import datetime

from pydantic import BaseModel, ConfigDict, Field

from app.models.enums import UserRole


class ProfileResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    first_name: str
    email: str
    role: UserRole
    created_at: datetime
    updated_at: datetime


class BootstrapRequest(BaseModel):
    """Deliberately has no `id`, `email`, or `role` field: those come only
    from the verified identity / trusted backend logic, never the client.
    """

    first_name: str = Field(min_length=1, max_length=200)
