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
