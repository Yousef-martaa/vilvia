"""add account deletion requests

Revision ID: f4c9d2a7e105
Revises: e6a1c4f9b207
Create Date: 2026-09-01 00:00:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


revision: str = "f4c9d2a7e105"
down_revision: Union[str, Sequence[str], None] = "e6a1c4f9b207"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        "account_deletion_requests",
        sa.Column("user_id", sa.UUID(), nullable=False),
        sa.Column(
            "status",
            sa.Enum(
                "requested",
                "auth_deleted",
                "completed",
                name="accountdeletionstatus",
                native_enum=False,
            ),
            server_default=sa.text("'requested'"),
            nullable=False,
        ),
        sa.Column(
            "requested_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("now()"),
            nullable=False,
        ),
        sa.Column("auth_deleted_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("completed_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column(
            "updated_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("now()"),
            nullable=False,
        ),
        sa.PrimaryKeyConstraint("user_id"),
        sa.CheckConstraint(
            "(status = 'requested' AND auth_deleted_at IS NULL "
            "AND completed_at IS NULL) OR "
            "(status = 'auth_deleted' AND auth_deleted_at IS NOT NULL "
            "AND completed_at IS NULL) OR "
            "(status = 'completed' AND auth_deleted_at IS NOT NULL "
            "AND completed_at IS NOT NULL)",
            name="account_deletion_requests_lifecycle_check",
        ),
    )


def downgrade() -> None:
    op.drop_table("account_deletion_requests")
