import uuid
from datetime import datetime

from pydantic import BaseModel, ConfigDict, Field, field_validator

from app.models.enums import PostCategory


class PostCreate(BaseModel):
    """Only user-authored post content is accepted from the client."""

    model_config = ConfigDict(extra="forbid")

    title: str = Field(min_length=1, max_length=200)
    body: str = Field(min_length=1, max_length=5000)
    category: PostCategory

    @field_validator("title", "body", mode="before")
    @classmethod
    def _strip_whitespace(cls, value: object) -> object:
        return value.strip() if isinstance(value, str) else value


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
