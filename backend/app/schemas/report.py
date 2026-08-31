import uuid
from datetime import datetime
from typing import Literal

from pydantic import BaseModel, ConfigDict, Field, field_validator

from app.models.enums import ReportStatus


class ReportCreate(BaseModel):
    model_config = ConfigDict(extra="forbid")

    reason: str = Field(min_length=1, max_length=500)

    @field_validator("reason", mode="before")
    @classmethod
    def _strip_whitespace(cls, value: object) -> object:
        return value.strip() if isinstance(value, str) else value


class ReportResponse(BaseModel):
    reported: bool
    report_count: int


class ReportStatusUpdate(BaseModel):
    model_config = ConfigDict(extra="forbid")

    status: ReportStatus


class ReportPostContext(BaseModel):
    id: uuid.UUID
    title: str
    body: str


class ReportCommentContext(BaseModel):
    id: uuid.UUID
    body: str
    post_id: uuid.UUID
    post_title: str


class AdminReportResponse(BaseModel):
    id: uuid.UUID
    reason: str
    status: ReportStatus
    created_at: datetime
    updated_at: datetime
    target_kind: Literal["post", "comment"]
    target_id: uuid.UUID
    post: ReportPostContext | None = None
    comment: ReportCommentContext | None = None
