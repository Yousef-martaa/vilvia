import uuid
from datetime import datetime
from typing import Optional

from sqlalchemy import DateTime, Enum as SAEnum, Integer, String, func
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column

from app.models.base import Base
from app.models.enums import ChildStage, UserRole


class Profile(Base):
    __tablename__ = "profiles"

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        primary_key=True,
        default=uuid.uuid4,
    )
    first_name: Mapped[str] = mapped_column(String, nullable=False)
    email: Mapped[str] = mapped_column(String, nullable=False, unique=True)
    role: Mapped[UserRole] = mapped_column(SAEnum(UserRole, native_enum=False), nullable=False)
    child_stage: Mapped[Optional[ChildStage]] = mapped_column(SAEnum(ChildStage, native_enum=False), nullable=True)
    pregnancy_week: Mapped[Optional[int]] = mapped_column(Integer, nullable=True)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now(), nullable=False
    )
