import uuid
from datetime import datetime

from pydantic import BaseModel, ConfigDict

from app.models.enums import PostCategory


class PostResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    author_name: str
    author_avatar_url: str | None
    title: str
    body: str
    category: PostCategory
    reaction_count: int
    comment_count: int
    created_at: datetime
    updated_at: datetime
