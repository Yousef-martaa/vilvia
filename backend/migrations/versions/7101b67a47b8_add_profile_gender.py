"""add profile gender

Revision ID: 7101b67a47b8
Revises: fde91fffb2e2
Create Date: 2026-08-18 21:57:55.119614

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = '7101b67a47b8'
down_revision: Union[str, Sequence[str], None] = 'fde91fffb2e2'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Upgrade schema.

    Nullable by design: existing profile rows predate this column and are
    not backfilled with a fabricated value. New signups are required to
    provide gender at the application layer (BootstrapRequest.gender is a
    required field), not enforced here at the schema level -- see
    docs/FEATURES/authentication.md.
    """
    op.add_column(
        'profiles',
        sa.Column(
            'gender',
            sa.Enum('male', 'female', name='gender', native_enum=False),
            nullable=True,
        ),
    )


def downgrade() -> None:
    """Downgrade schema."""
    op.drop_column('profiles', 'gender')
