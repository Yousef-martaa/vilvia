import uuid
from datetime import datetime

from pydantic import BaseModel, ConfigDict, Field, field_validator


class CommentCreate(BaseModel):
    """The comment body is the only client-controlled field."""

    model_config = ConfigDict(extra="forbid")

    body: str = Field(min_length=1, max_length=2000)

    @field_validator("body", mode="before")
    @classmethod
    def _strip_whitespace(cls, value: object) -> object:
        return value.strip() if isinstance(value, str) else value


class CommentResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    author_name: str
    author_avatar_url: str | None
    body: str
    created_at: datetime
    updated_at: datetime


class CommentCreateResponse(BaseModel):
    comment: CommentResponse
    comment_count: int
