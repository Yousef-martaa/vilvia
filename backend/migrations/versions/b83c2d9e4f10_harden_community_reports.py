"""harden community reports

Revision ID: b83c2d9e4f10
Revises: a92f4c7d1e30
Create Date: 2026-08-30 00:00:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


revision: str = "b83c2d9e4f10"
down_revision: Union[str, Sequence[str], None] = "a92f4c7d1e30"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column("reports", sa.Column("post_id", sa.UUID(), nullable=True))
    op.add_column("reports", sa.Column("comment_id", sa.UUID(), nullable=True))

    # Abort before destructive changes if legacy ownership cannot be preserved.
    op.execute(
        sa.text(
            """
            DO $$
            BEGIN
              IF EXISTS (
                SELECT 1 FROM reports r
                WHERE NOT EXISTS (SELECT 1 FROM profiles p WHERE p.id = r.reported_by)
              ) THEN
                RAISE EXCEPTION 'Cannot migrate reports: orphaned reported_by value';
              END IF;
              IF EXISTS (
                SELECT 1 FROM reports r
                WHERE (r.target_type = 'post' AND NOT EXISTS (
                         SELECT 1 FROM posts p WHERE p.id = r.target_id
                       ))
                   OR (r.target_type = 'comment' AND NOT EXISTS (
                         SELECT 1 FROM comments c WHERE c.id = r.target_id
                       ))
              ) THEN
                RAISE EXCEPTION 'Cannot migrate reports: orphaned report target';
              END IF;
              IF EXISTS (
                SELECT 1 FROM reports
                GROUP BY reported_by, target_type, target_id
                HAVING COUNT(*) > 1
              ) THEN
                RAISE EXCEPTION 'Cannot migrate reports: duplicate reporter and target';
              END IF;
            END $$;
            """
        )
    )

    op.execute(
        sa.text(
            "UPDATE reports SET post_id = target_id WHERE target_type = 'post'"
        )
    )
    op.execute(
        sa.text(
            "UPDATE reports SET comment_id = target_id "
            "WHERE target_type = 'comment'"
        )
    )

    op.create_foreign_key(
        "reports_post_id_fkey",
        "reports",
        "posts",
        ["post_id"],
        ["id"],
        ondelete="CASCADE",
    )
    op.create_foreign_key(
        "reports_comment_id_fkey",
        "reports",
        "comments",
        ["comment_id"],
        ["id"],
        ondelete="CASCADE",
    )
    op.create_foreign_key(
        "reports_reported_by_fkey",
        "reports",
        "profiles",
        ["reported_by"],
        ["id"],
        ondelete="RESTRICT",
    )
    op.create_check_constraint(
        "reports_exactly_one_target_check",
        "reports",
        "(post_id IS NOT NULL AND comment_id IS NULL) OR "
        "(post_id IS NULL AND comment_id IS NOT NULL)",
    )
    op.create_unique_constraint(
        "reports_reported_by_post_id_key",
        "reports",
        ["reported_by", "post_id"],
    )
    op.create_unique_constraint(
        "reports_reported_by_comment_id_key",
        "reports",
        ["reported_by", "comment_id"],
    )
    op.create_index("ix_reports_post_id", "reports", ["post_id"])
    op.create_index("ix_reports_comment_id", "reports", ["comment_id"])

    op.drop_column("reports", "target_type")
    op.drop_column("reports", "target_id")

    op.execute(
        sa.text(
            """
            UPDATE posts p
            SET report_count = (
              SELECT COUNT(*) FROM reports r WHERE r.post_id = p.id
            )
            """
        )
    )
    op.execute(
        sa.text(
            """
            UPDATE comments c
            SET report_count = (
              SELECT COUNT(*) FROM reports r WHERE r.comment_id = c.id
            )
            """
        )
    )


def downgrade() -> None:
    op.add_column("reports", sa.Column("target_id", sa.UUID(), nullable=True))
    op.add_column(
        "reports",
        sa.Column(
            "target_type",
            sa.Enum(
                "post", "comment", name="reporttargettype", native_enum=False
            ),
            nullable=True,
        ),
    )
    op.execute(
        sa.text(
            "UPDATE reports SET target_type = 'post', target_id = post_id "
            "WHERE post_id IS NOT NULL"
        )
    )
    op.execute(
        sa.text(
            "UPDATE reports SET target_type = 'comment', target_id = comment_id "
            "WHERE comment_id IS NOT NULL"
        )
    )
    op.alter_column("reports", "target_type", nullable=False)
    op.alter_column("reports", "target_id", nullable=False)

    op.drop_index("ix_reports_comment_id", table_name="reports")
    op.drop_index("ix_reports_post_id", table_name="reports")
    op.drop_constraint(
        "reports_reported_by_comment_id_key", "reports", type_="unique"
    )
    op.drop_constraint(
        "reports_reported_by_post_id_key", "reports", type_="unique"
    )
    op.drop_constraint(
        "reports_exactly_one_target_check", "reports", type_="check"
    )
    op.drop_constraint("reports_reported_by_fkey", "reports", type_="foreignkey")
    op.drop_constraint("reports_comment_id_fkey", "reports", type_="foreignkey")
    op.drop_constraint("reports_post_id_fkey", "reports", type_="foreignkey")
    op.drop_column("reports", "comment_id")
    op.drop_column("reports", "post_id")
