"""Manually fulfill durable account-deletion requests.

Usage:
    python scripts/fulfill_account_deletions.py USER_UUID
    python scripts/fulfill_account_deletions.py --purge-completed

No worker or scheduler is implied. Run this trusted operator command with
SUPABASE_SERVICE_ROLE_KEY set only in the operator environment.
"""

import argparse
import sys
import uuid
from pathlib import Path

sys.path.append(str(Path(__file__).resolve().parent.parent))

from app.core.database import SessionLocal  # noqa: E402
from app.core.settings import settings  # noqa: E402
from app.services.account_deletion import (  # noqa: E402
    AccountDeletionNotFound,
    fulfill_account_deletion,
    purge_completed_requests,
)
from app.services.supabase_admin import SupabaseAuthAdmin  # noqa: E402


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser()
    action = parser.add_mutually_exclusive_group(required=True)
    action.add_argument("user_id", nargs="?", type=uuid.UUID)
    action.add_argument("--purge-completed", action="store_true")
    args = parser.parse_args(argv)

    if args.purge_completed:
        db = SessionLocal()
        try:
            purged = purge_completed_requests(
                db,
                settings.account_deletion_completed_retention_days,
                max_access_token_lifetime_seconds=(
                    settings.supabase_access_token_max_lifetime_seconds
                ),
                jwt_clock_skew_seconds=settings.supabase_jwt_clock_skew_seconds,
            )
        except Exception:
            print("Completed-request purge failed.", file=sys.stderr)
            return 1
        finally:
            db.close()
        print(f"Purged {purged} expired completed request record(s).")
        return 0

    secret = settings.supabase_service_role_key
    if secret is None or not secret.get_secret_value().strip():
        print("SUPABASE_SERVICE_ROLE_KEY is required.", file=sys.stderr)
        return 2

    admin = SupabaseAuthAdmin(
        supabase_url=settings.supabase_url,
        service_role_key=secret.get_secret_value(),
        timeout_seconds=settings.supabase_admin_timeout_seconds,
    )
    db = SessionLocal()
    try:
        result = fulfill_account_deletion(db, args.user_id, admin.delete_user)
    except AccountDeletionNotFound:
        print("No account deletion request exists for that user id.", file=sys.stderr)
        return 1
    except Exception:
        # Deliberately omit exception text: upstream errors can contain
        # deployment details. The durable state identifies the retry point.
        print("Account deletion failed; the request remains retryable.", file=sys.stderr)
        return 1
    finally:
        db.close()
        admin.close()

    print(f"Account deletion state: {result.status.value}.")
    try:
        purge_db = SessionLocal()
        try:
            purged = purge_completed_requests(
                purge_db,
                settings.account_deletion_completed_retention_days,
                max_access_token_lifetime_seconds=(
                    settings.supabase_access_token_max_lifetime_seconds
                ),
                jwt_clock_skew_seconds=settings.supabase_jwt_clock_skew_seconds,
            )
        finally:
            purge_db.close()
    except Exception:
        print(
            "Account deletion completed, but expired-request purge failed.",
            file=sys.stderr,
        )
        return 1
    if purged:
        print(f"Purged {purged} expired completed request record(s).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
