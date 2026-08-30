"""add post reactions

Revision ID: a92f4c7d1e30
Revises: c1a5f4e8b2d7
Create Date: 2026-08-23 00:00:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


revision: str = "a92f4c7d1e30"
down_revision: Union[str, Sequence[str], None] = "c1a5f4e8b2d7"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Add normalized ownership and discard unowned legacy counts."""
    op.create_table(
        "post_reactions",
        sa.Column("post_id", sa.UUID(), nullable=False),
        sa.Column("profile_id", sa.UUID(), nullable=False),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("now()"),
            nullable=False,
        ),
        sa.ForeignKeyConstraint(
            ["post_id"], ["posts.id"], ondelete="CASCADE"
        ),
        sa.ForeignKeyConstraint(
            ["profile_id"], ["profiles.id"], ondelete="CASCADE"
        ),
        sa.PrimaryKeyConstraint("post_id", "profile_id"),
    )
    op.execute(sa.text("UPDATE posts SET reaction_count = 0"))


def downgrade() -> None:
    op.drop_table("post_reactions")
