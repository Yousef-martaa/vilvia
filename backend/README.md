# Vilvia Backend

FastAPI backend for the Vilvia app. Connects to a PostgreSQL database.

## Prerequisites

- Python 3.13

## Main Technologies

- FastAPI
- SQLAlchemy 2.x
- PostgreSQL
- psycopg (psycopg3)
- pydantic-settings
- Alembic
- pytest

## Setup

```bash
python -m venv .venv
.venv\Scripts\activate      # Windows
# source .venv/bin/activate  # macOS/Linux
pip install -r requirements.txt
```

Copy `.env.example` to `.env` and fill in your local values:

```bash
cp .env.example .env
```

## Run

```bash
uvicorn app.main:app --reload
```

Server runs at `http://127.0.0.1:8000`.

## Migrations

```bash
alembic upgrade head
```

## Seed data

Populate the database with sample development resources (for local testing
of the resources list end to end):

```bash
python scripts/seed_resources.py
```

Safe to run multiple times — already-seeded records are skipped, so it won't
create duplicates. This is local/dev sample content only, not real or
verified resource content.

## External resource sync (MedlinePlus)

Populate the database with real, trusted content from the MedlinePlus Web
Service (https://medlineplus.gov/about/developers/webservices/), Vilvia's
first explicitly-approved external content provider:

```bash
python scripts/sync_medlineplus.py
```

Idempotent and safe to run repeatedly: it upserts by a deterministic id
derived from each MedlinePlus URL, so re-running only inserts genuinely new
resources and updates ones whose content changed — it never creates
duplicates and never touches resources it didn't just fetch. If MedlinePlus
is unavailable, the run leaves all existing resources untouched and exits
non-zero.

This script only orchestrates (`SessionLocal` → `MedlinePlusProvider` →
`sync_provider`); it has no scheduling logic of its own by design, so it
can be wired into whatever the deployment environment already provides —
a cron entry, a platform's scheduled/cron job feature, a Kubernetes
CronJob — without any code changes. MedlinePlus recommends caching results
12–24 hours, so a daily invocation is a reasonable default cadence. A
PostgreSQL session-level advisory lock (not merely an in-process lock —
it's visible to every connection to the database, so it prevents overlap
across separate processes/hosts sharing that database) stops two
overlapping runs from racing each other; the deployment scheduler should
still avoid triggering overlapping runs as the primary safeguard.

Resources synced from MedlinePlus auto-publish (`is_published=True`) with
attribution (`source_name`/`source_url`) because MedlinePlus is an
explicitly approved trusted provider — unlike Vilvia-authored content,
which requires manual review before publication (see
`docs/FEATURES/parenting_information.md`).

## Test

```bash
pytest tests/
```

## Project Structure

```
backend/
├── app/
│   ├── main.py          # FastAPI app entry point
│   ├── core/            # Settings and database setup
│   ├── models/          # SQLAlchemy models
│   └── routers/         # API route handlers
└── tests/
```

## Current Features

- FastAPI application setup
- Health check endpoint (`GET /health`)
- Configuration via environment variables using pydantic-settings
- SQLAlchemy 2.x engine and session factory
- PostgreSQL connection with psycopg3
- Database models: `Profile`, `Resource`, `Post`, `Comment`, `Report`
- Alembic migration setup

## Planned Next

- Initial database migration
- API endpoints

## Endpoints

| Method | Path | Description |
|--------|------|-------------|
| GET | `/health` | Health check endpoint |
