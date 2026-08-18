"""Seed the events table with sample development data.

Local/dev seed data only: not verified, real, or production event content,
and never run automatically -- this script must be invoked manually.

Unlike a skip-if-exists seed script, this script REFRESHES (does not skip)
already-seeded rows on every run. Event dates are defined relative to
"now" at seed time (e.g. "3 days from now"), so a previously seeded event
would otherwise silently age past `starts_at` and drop out of the
upcoming-events filter -- refreshing keeps local dev/test data usable
indefinitely without needing to remember to clear the table. Each event's
id is still derived deterministically from a stable seed key (not from
its title), so re-running never creates duplicates.

Usage:
    python scripts/seed_events.py
"""

import sys
import uuid
from datetime import datetime, timedelta, timezone
from pathlib import Path

sys.path.append(str(Path(__file__).resolve().parent.parent))

from sqlalchemy import select  # noqa: E402

from app.core.database import SessionLocal  # noqa: E402
from app.models.event import Event  # noqa: E402

# Fixed namespace for deriving deterministic seed ids. Do not change this
# value, or previously seeded records will no longer be recognized and will
# be re-inserted as duplicates.
SEED_NAMESPACE = uuid.UUID("5eb6fb00-d0a6-4993-a6bb-0bce1eb07102")

DISCLAIMER = "[Development sample data - not a real scheduled event.] "


def _seed_records(now: datetime) -> list[dict]:
    return [
        {
            "key": "parent-baby-playgroup",
            "title": "Parent & Baby Playgroup",
            "description": DISCLAIMER
            + "A relaxed drop-in playgroup for parents and babies to meet "
            "other nearby families.",
            "location": "Kristianstad Community Centre",
            "starts_at": now + timedelta(days=3, hours=1),
            "ends_at": now + timedelta(days=3, hours=2, minutes=30),
        },
        {
            "key": "new-parents-meetup",
            "title": "New Parents Meetup",
            "description": DISCLAIMER
            + "An informal evening meetup for new and expecting parents to "
            "share experiences.",
            "location": "Vilvia Community Room",
            "starts_at": now + timedelta(days=6, hours=3),
            "ends_at": now + timedelta(days=6, hours=4, minutes=30),
        },
        {
            "key": "toddler-storytime",
            "title": "Toddler Storytime at the Library",
            "description": DISCLAIMER
            + "A weekly storytime session for toddlers, with songs and "
            "picture books.",
            "location": "Kristianstad Public Library",
            "starts_at": now + timedelta(days=9, hours=2),
            "ends_at": now + timedelta(days=9, hours=2, minutes=45),
        },
        {
            "key": "prenatal-yoga-session",
            "title": "Prenatal Yoga Session",
            "description": DISCLAIMER
            + "A gentle yoga class designed for expecting parents; all "
            "experience levels welcome.",
            "location": "Vilvia Community Room",
            "starts_at": now + timedelta(days=13, hours=5),
            "ends_at": now + timedelta(days=13, hours=6),
        },
    ]


def _event_id(key: str) -> uuid.UUID:
    return uuid.uuid5(SEED_NAMESPACE, key)


def seed_events() -> list[str]:
    """Insert missing seed events and refresh the dates of ones that
    already exist.

    Returns the titles of every seed record that was inserted or updated
    (i.e. all of them, every run).
    """
    now = datetime.now(timezone.utc)
    records = _seed_records(now)

    db = SessionLocal()
    try:
        ids = [_event_id(record["key"]) for record in records]
        existing_by_id = {
            event.id: event
            for event in db.execute(
                select(Event).where(Event.id.in_(ids))
            ).scalars().all()
        }

        touched_titles = []
        for record in records:
            event_id = _event_id(record["key"])
            existing_event = existing_by_id.get(event_id)

            if existing_event is None:
                db.add(
                    Event(
                        id=event_id,
                        title=record["title"],
                        description=record["description"],
                        location=record["location"],
                        starts_at=record["starts_at"],
                        ends_at=record["ends_at"],
                        is_published=True,
                    )
                )
            else:
                existing_event.title = record["title"]
                existing_event.description = record["description"]
                existing_event.location = record["location"]
                existing_event.starts_at = record["starts_at"]
                existing_event.ends_at = record["ends_at"]

            touched_titles.append(record["title"])

        db.commit()
        return touched_titles
    except Exception:
        db.rollback()
        raise
    finally:
        db.close()


if __name__ == "__main__":
    titles = seed_events()
    print(f"Seeded {len(titles)} event(s) (inserted or refreshed):")
    for title in titles:
        print(f"  - {title}")
