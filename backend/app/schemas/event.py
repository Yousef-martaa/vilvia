import uuid
from datetime import datetime

from pydantic import BaseModel, ConfigDict, Field, field_validator, model_validator


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


class EventCreate(BaseModel):
    """Deliberately has no `id`, `created_by`, or `is_published` field:
    those are always assigned server-side by POST /events, never taken
    from the client -- see app/routers/events.py.

    `extra="forbid"` makes that guarantee fail closed the same way
    BootstrapRequest does for `role`: a client submitting `created_by`,
    `is_published`, or any other undeclared field is rejected with a 422
    instead of having it silently dropped.
    """

    model_config = ConfigDict(extra="forbid")

    title: str = Field(min_length=1, max_length=200)
    description: str = Field(min_length=1)
    location: str = Field(min_length=1, max_length=200)
    starts_at: datetime
    ends_at: datetime | None = None

    @field_validator("title", "description", "location", mode="before")
    @classmethod
    def _strip_whitespace(cls, value: object) -> object:
        # Runs before the min_length constraint, so a whitespace-only
        # value (e.g. "   ") is normalized down to "" and then rejected
        # by min_length rather than accepted as if it were content.
        return value.strip() if isinstance(value, str) else value

    @field_validator("starts_at", "ends_at")
    @classmethod
    def _require_timezone_aware(cls, value: datetime | None) -> datetime | None:
        if value is not None and value.tzinfo is None:
            raise ValueError(
                "must include timezone information (e.g. a UTC offset), not a naive datetime"
            )
        return value

    @model_validator(mode="after")
    def _check_ends_at_after_starts_at(self) -> "EventCreate":
        if self.ends_at is not None and self.ends_at <= self.starts_at:
            raise ValueError("ends_at must be after starts_at")
        return self


class EventPublishRequest(BaseModel):
    """POST /events/{event_id}/publish takes no business input from the
    client -- there is nothing to assign here, only which Event to
    publish, and that comes from the path, not this body. This model
    exists purely so a client-supplied body (e.g. attempting to sneak in
    `is_published` or `created_by`) is rejected with 422 rather than
    silently ignored; a request with no body at all, or an empty JSON
    object, is accepted the same way, since neither carries any field
    for `extra="forbid"` to reject.
    """

    model_config = ConfigDict(extra="forbid")
