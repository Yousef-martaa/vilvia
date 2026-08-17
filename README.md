# Vilvia

Vilvia is a Flutter app with a FastAPI backend.

## Prerequisites

- Flutter SDK
- Python 3.13
- A PostgreSQL database (see `backend/README.md`)
- A Supabase project (for auth)
- Windows + Git Bash (the instructions below assume this environment)

## One-time setup

**Backend** — see `backend/README.md` for full details:

```bash
cd backend
python -m venv .venv
.venv\Scripts\activate
pip install -r requirements.txt
cp .env.example .env   # then fill in DATABASE_URL, SUPABASE_URL, etc.
alembic upgrade head
cd ..
```

**Frontend** — copy the root env file and fill in your values:

```bash
cp .env.example .env
```

`.env` holds the Flutter dev-time config (`API_BASE_URL`, `SUPABASE_URL`,
`SUPABASE_PUBLISHABLE_KEY`). `API_BASE_URL` defaults to
`http://10.0.2.2:8000` (the Android emulator's alias for the host's
localhost) if left unset — override it for web/desktop
(`http://127.0.0.1:8000`) or a physical device (your machine's LAN IP).
`SUPABASE_URL` and `SUPABASE_PUBLISHABLE_KEY` are required.

## Run backend + frontend together

```bash
./dev.sh
```

This starts the FastAPI backend (`uvicorn --reload`) in the background and
Flutter (`flutter run`) in the foreground, in the same terminal, so both
logs stay visible. Extra arguments are forwarded to `flutter run`, e.g.:

```bash
./dev.sh -d chrome
```

Press Ctrl+C (or let Flutter exit) to stop; the backend is stopped
automatically.

## Run backend or frontend separately

Backend (from `backend/`, see `backend/README.md`):

```bash
uvicorn app.main:app --reload
```

Frontend (from the repo root):

```bash
flutter run \
  --dart-define=API_BASE_URL=http://10.0.2.2:8000 \
  --dart-define=SUPABASE_URL=<your-supabase-url> \
  --dart-define=SUPABASE_PUBLISHABLE_KEY=<your-supabase-key>
```
