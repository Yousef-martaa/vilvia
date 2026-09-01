from datetime import datetime

from pydantic import BaseModel, ConfigDict

from app.models.enums import AccountDeletionStatus


class AccountDeletionRequestBody(BaseModel):
    """No client-controlled deletion policy or identity fields exist."""

    model_config = ConfigDict(extra="forbid")


class AccountDeletionRequestResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    status: AccountDeletionStatus
    requested_at: datetime
