"""Seed the resources table with sample development data.

Safe to run multiple times: each record's id is derived deterministically
from a stable seed key (not from its title, which may change later), so
re-running only inserts records that are still missing.

This is local/dev seed data only, not verified or production content.

Usage:
    python scripts/seed_resources.py
"""

import sys
import uuid
from pathlib import Path

sys.path.append(str(Path(__file__).resolve().parent.parent))

from sqlalchemy import select  # noqa: E402

from app.core.database import SessionLocal  # noqa: E402
from app.models.enums import ResourceCategory, ResourceStage  # noqa: E402
from app.models.resource import Resource  # noqa: E402

# Fixed namespace for deriving deterministic seed ids. Do not change this
# value, or previously seeded records will no longer be recognized and will
# be re-inserted as duplicates.
SEED_NAMESPACE = uuid.UUID("faeecadf-2154-5a07-b593-ba717ed28ba9")

DISCLAIMER = "[Development sample data - not verified medical guidance.] "

SEED_RECORDS = [
    {
        "key": "pregnancy-baby-development",
        "title": "Understanding Your Baby's Development in the Womb",
        "summary": DISCLAIMER
        + "A sample overview of prenatal development milestones, for local testing.",
        "body": DISCLAIMER
        + "Placeholder body content describing how a baby typically develops "
        "during pregnancy, week by week. Used to exercise the resources "
        "list end to end; not reviewed or approved medical guidance.",
        "category": ResourceCategory.child_development,
        "stage": ResourceStage.pregnancy,
        "source_name": "Vilvia Team (Sample Data)",
        "source_url": "https://example.com/resources/pregnancy-baby-development",
    },
    {
        "key": "pregnancy-sleep-prep",
        "title": "Preparing Your Sleep Routine Before Baby Arrives",
        "summary": DISCLAIMER
        + "Sample tips for adjusting sleep habits ahead of a newborn's arrival.",
        "body": DISCLAIMER
        + "Placeholder body content on adjusting sleep schedules and the "
        "sleep environment before a baby arrives. Sample content only.",
        "category": ResourceCategory.sleep,
        "stage": ResourceStage.pregnancy,
        "source_name": "Vilvia Team (Sample Data)",
        "source_url": "https://example.com/resources/pregnancy-sleep-prep",
    },
    {
        "key": "newborn-breastfeeding-basics",
        "title": "Breastfeeding Basics for the First Weeks",
        "summary": DISCLAIMER
        + "A sample introduction to breastfeeding positioning and frequency.",
        "body": DISCLAIMER
        + "Placeholder body content covering common breastfeeding questions "
        "in the first weeks after birth. Sample content only.",
        "category": ResourceCategory.feeding,
        "stage": ResourceStage.newborn,
        "source_name": "Vilvia Team (Sample Data)",
        "source_url": "https://example.com/resources/newborn-breastfeeding-basics",
    },
    {
        "key": "infant-0-6m-sleep-habits",
        "title": "Building Healthy Sleep Habits for 0-6 Months",
        "summary": DISCLAIMER
        + "Sample guidance on establishing a sleep routine in the first six months.",
        "body": DISCLAIMER
        + "Placeholder body content on naps, bedtime routines, and sleep "
        "cues for infants aged 0-6 months. Sample content only.",
        "category": ResourceCategory.sleep,
        "stage": ResourceStage.months_0_6,
        "source_name": "Vilvia Team (Sample Data)",
        "source_url": "https://example.com/resources/infant-0-6m-sleep-habits",
    },
    {
        "key": "infant-6-12m-babyproofing",
        "title": "Babyproofing Your Home Before Baby Starts Moving",
        "summary": DISCLAIMER
        + "A sample checklist for home safety as babies become mobile.",
        "body": DISCLAIMER
        + "Placeholder body content listing common babyproofing steps for "
        "a crawling or early-walking infant. Sample content only.",
        "category": ResourceCategory.health_safety,
        "stage": ResourceStage.months_6_12,
        "source_name": "Vilvia Team (Sample Data)",
        "source_url": "https://example.com/resources/infant-6-12m-babyproofing",
    },
    {
        "key": "infant-6-12m-vaccinations",
        "title": "Understanding the 6-12 Month Vaccination Schedule",
        "summary": DISCLAIMER
        + "A sample summary of a typical 6-12 month vaccination schedule.",
        "body": DISCLAIMER
        + "Placeholder body content summarizing vaccines commonly given "
        "between 6 and 12 months. Always follow guidance from a licensed "
        "healthcare provider; this is sample content only.",
        "category": ResourceCategory.vaccinations,
        "stage": ResourceStage.months_6_12,
        "source_name": "Vilvia Team (Sample Data)",
        "source_url": "https://example.com/resources/infant-6-12m-vaccinations",
    },
    {
        "key": "toddler-1-3y-family-meals",
        "title": "Introducing Toddlers to Family Meals",
        "summary": DISCLAIMER
        + "Sample tips for transitioning a toddler to shared family meals.",
        "body": DISCLAIMER
        + "Placeholder body content on introducing toddlers to family "
        "meals and encouraging varied eating habits. Sample content only.",
        "category": ResourceCategory.feeding,
        "stage": ResourceStage.years_1_3,
        "source_name": "Vilvia Team (Sample Data)",
        "source_url": "https://example.com/resources/toddler-1-3y-family-meals",
    },
    {
        "key": "toddler-1-3y-everyday-routines",
        "title": "Everyday Routines That Support Toddler Growth",
        "summary": DISCLAIMER
        + "A sample look at daily routines that support toddler development.",
        "body": DISCLAIMER
        + "Placeholder body content describing everyday routines, such as "
        "consistent mealtimes and playtime, that support toddlers aged "
        "1-3 years. Sample content only.",
        "category": ResourceCategory.everyday_guidance,
        "stage": ResourceStage.years_1_3,
        "source_name": "Vilvia Team (Sample Data)",
        "source_url": "https://example.com/resources/toddler-1-3y-everyday-routines",
    },
]


def _resource_id(key: str) -> uuid.UUID:
    return uuid.uuid5(SEED_NAMESPACE, key)


def _records_to_insert(existing_ids: set[uuid.UUID]) -> list[dict]:
    return [
        record
        for record in SEED_RECORDS
        if _resource_id(record["key"]) not in existing_ids
    ]


def seed_resources() -> list[str]:
    """Insert any seed resources that don't already exist.

    Returns the titles of the resources that were inserted.
    """
    db = SessionLocal()
    try:
        seed_ids = [_resource_id(record["key"]) for record in SEED_RECORDS]
        existing_ids = set(
            db.execute(select(Resource.id).where(Resource.id.in_(seed_ids)))
            .scalars()
            .all()
        )

        to_insert = _records_to_insert(existing_ids)
        for record in to_insert:
            db.add(
                Resource(
                    id=_resource_id(record["key"]),
                    title=record["title"],
                    summary=record["summary"],
                    body=record["body"],
                    category=record["category"],
                    stage=record["stage"],
                    source_name=record["source_name"],
                    source_url=record["source_url"],
                    is_published=True,
                )
            )

        db.commit()
        return [record["title"] for record in to_insert]
    except Exception:
        db.rollback()
        raise
    finally:
        db.close()


if __name__ == "__main__":
    inserted_titles = seed_resources()
    if inserted_titles:
        print(f"Inserted {len(inserted_titles)} resource(s):")
        for title in inserted_titles:
            print(f"  - {title}")
    else:
        print("No new resources to insert; all seed records already exist.")
