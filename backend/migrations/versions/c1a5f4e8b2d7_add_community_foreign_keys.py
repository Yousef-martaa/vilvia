"""add community foreign keys

Revision ID: c1a5f4e8b2d7
Revises: 7101b67a47b8
Create Date: 2026-08-22 00:00:00.000000

"""
from typing import Sequence, Union

from alembic import op


# revision identifiers, used by Alembic.
revision: str = "c1a5f4e8b2d7"
down_revision: Union[str, Sequence[str], None] = "7101b67a47b8"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Add database-enforced ownership and parent relationships."""
    op.create_foreign_key(
        "posts_author_id_fkey",
        "posts",
        "profiles",
        ["author_id"],
        ["id"],
        ondelete="RESTRICT",
    )
    op.create_foreign_key(
        "comments_author_id_fkey",
        "comments",
        "profiles",
        ["author_id"],
        ["id"],
        ondelete="RESTRICT",
    )
    op.create_foreign_key(
        "comments_post_id_fkey",
        "comments",
        "posts",
        ["post_id"],
        ["id"],
        ondelete="CASCADE",
    )


def downgrade() -> None:
    """Remove the community foreign keys."""
    op.drop_constraint("comments_post_id_fkey", "comments", type_="foreignkey")
    op.drop_constraint("comments_author_id_fkey", "comments", type_="foreignkey")
    op.drop_constraint("posts_author_id_fkey", "posts", type_="foreignkey")
