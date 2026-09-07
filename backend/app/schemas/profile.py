import uuid
from datetime import datetime

from pydantic import BaseModel, ConfigDict, Field

from app.models.enums import Gender, ParentRole, UserRole


class ProfileResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    first_name: str
    last_name: str | None
    email: str
    role: UserRole
    # Nullable: rows created before this field existed have no value and
    # are not backfilled -- see docs/FEATURES/authentication.md.
    gender: Gender | None
    parent_role: ParentRole | None
    created_at: datetime
    updated_at: datetime


class BootstrapRequest(BaseModel):
    """Deliberately has no `id`, `email`, or `role` field: those come only
    from the verified identity / trusted backend logic, never the client.

    `parent_role` and `gender` are optional here. Existing rows predating
    these fields stay NULL rather than being backfilled; see
    docs/FEATURES/authentication.md.

    `extra="forbid"` makes that "no id/email/role field" guarantee fail
    closed: without it, Pydantic's default behavior is to silently
    ignore unexpected input fields rather than reject them, so a client
    submitting `role`/`id`/`email` (or anything else not declared here)
    would succeed and just have that field quietly dropped. Rejecting it
    with a 422 instead is a deliberate, visible signal that the request
    doesn't match what this endpoint accepts.
    """

    model_config = ConfigDict(extra="forbid")

    first_name: str = Field(min_length=1, max_length=200)
    last_name: str = Field(min_length=1, max_length=200)
    parent_role: ParentRole | None = None
    gender: Gender | None = None
