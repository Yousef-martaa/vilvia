import uuid
from datetime import datetime

from sqlalchemy import CheckConstraint, DateTime, func, text
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column

from app.models.base import Base
from app.models.enums import AccountDeletionStatus, str_enum


class AccountDeletionRequest(Base):
    """Durable cross-system account-deletion state.

    ``user_id`` deliberately is not a foreign key: this record must survive
    deletion of the Profile long enough to prove/retry cross-system cleanup.
    Completed rows are purged by the operator command after the configured
    short recovery window.
    """

    __tablename__ = "account_deletion_requests"
    __table_args__ = (
        CheckConstraint(
            "(status = 'requested' AND auth_deleted_at IS NULL "
            "AND completed_at IS NULL) OR "
            "(status = 'auth_deleted' AND auth_deleted_at IS NOT NULL "
            "AND completed_at IS NULL) OR "
            "(status = 'completed' AND auth_deleted_at IS NOT NULL "
            "AND completed_at IS NOT NULL)",
            name="account_deletion_requests_lifecycle_check",
        ),
    )

    user_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), primary_key=True
    )
    status: Mapped[AccountDeletionStatus] = mapped_column(
        str_enum(AccountDeletionStatus),
        nullable=False,
        default=AccountDeletionStatus.requested,
        server_default=text("'requested'"),
    )
    requested_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )
    auth_deleted_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True
    )
    completed_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        server_default=func.now(),
        onupdate=func.now(),
        nullable=False,
    )
