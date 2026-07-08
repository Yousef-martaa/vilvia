# Vilvia Backend

FastAPI backend for the Vilvia app.

## Setup

```bash
python -m venv .venv
.venv\Scripts\activate      # Windows
# source .venv/bin/activate  # macOS/Linux
pip install -r requirements.txt
```

## Run

```bash
uvicorn app.main:app --reload
```

Server runs at `http://127.0.0.1:8000`.

## Test

```bash
pytest tests/
```

## Endpoints

| Method | Path | Description |
|--------|------|-------------|
| GET | `/health` | Health check |
