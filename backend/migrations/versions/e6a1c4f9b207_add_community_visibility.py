"""add community visibility

Revision ID: e6a1c4f9b207
Revises: b83c2d9e4f10
Create Date: 2026-08-31 00:00:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


revision: str = "e6a1c4f9b207"
down_revision: Union[str, Sequence[str], None] = "b83c2d9e4f10"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column(
        "posts",
        sa.Column(
            "is_hidden", sa.Boolean(), server_default=sa.false(), nullable=False
        ),
    )
    op.add_column(
        "comments",
        sa.Column(
            "is_hidden", sa.Boolean(), server_default=sa.false(), nullable=False
        ),
    )


def downgrade() -> None:
    op.drop_column("comments", "is_hidden")
    op.drop_column("posts", "is_hidden")
