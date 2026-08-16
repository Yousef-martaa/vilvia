"""Sync MedlinePlus health topics into the resources table.

This script is intentionally thin: it only wires SessionLocal ->
MedlinePlusProvider -> sync_provider together. All discovery/ingestion/
normalization logic lives in app/providers/medlineplus.py, and all
upsert/persistence logic lives in app/services/resource_sync.py.

Safe to run repeatedly (idempotent upserts) and safe to schedule --
cron, a platform's scheduled-job feature, a Kubernetes CronJob -- exactly
as-is, with no code changes: only the trigger/cadence is a deployment
concern, never this script's internals. A PostgreSQL session-level
advisory lock (see resource_sync.py) -- visible across processes/hosts
sharing the same database, not just within one process -- makes a second
overlapping invocation a no-op rather than a race.

Usage:
    python scripts/sync_medlineplus.py
"""

import sys
from pathlib import Path

sys.path.append(str(Path(__file__).resolve().parent.parent))

from app.core.database import SessionLocal  # noqa: E402
from app.providers.medlineplus import MedlinePlusProvider  # noqa: E402
from app.services.resource_sync import sync_provider  # noqa: E402


def main() -> int:
    db = SessionLocal()
    provider = MedlinePlusProvider()
    try:
        # MedlinePlus is an explicitly approved trusted provider, so its
        # synced resources auto-publish with attribution (source_name/
        # source_url) rather than waiting on manual editorial review --
        # unlike Vilvia-authored content. See docs/FEATURES/
        # parenting_information.md.
        result = sync_provider(db, provider, publish=True)
    finally:
        provider.close()
        db.close()

    if result.skipped_locked:
        print("MedlinePlus sync already in progress elsewhere; skipped.")
        return 0

    print(
        f"MedlinePlus sync: {result.inserted} inserted, "
        f"{result.updated} updated, {result.unchanged} unchanged, "
        f"{result.failed} failed."
    )
    for error in result.errors:
        print(f"  - {error}")

    if result.provider_failed:
        print("MedlinePlus was unavailable; existing resources left unchanged.")
        return 1

    return 0


if __name__ == "__main__":
    sys.exit(main())
