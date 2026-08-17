#!/usr/bin/env bash
# Starts the FastAPI backend and Flutter frontend together for local
# development. Both processes' logs stay visible in this terminal. Ctrl+C
# (or Flutter exiting on its own) stops the backend automatically.
#
# Usage: ./dev.sh [flutter run args...]
#   e.g. ./dev.sh -d chrome
#
# Frontend config (API_BASE_URL, SUPABASE_URL, SUPABASE_PUBLISHABLE_KEY) is
# read from .env at the repo root (copy .env.example to get started) and
# passed to `flutter run` as --dart-define values.
#
# To run backend/frontend separately instead, see backend/README.md and
# README.md.

set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"

venv_python="backend/.venv/Scripts/python.exe"
if [[ ! -x "$venv_python" ]]; then
  echo "error: backend virtualenv not found at $venv_python" >&2
  echo "Set it up first (see backend/README.md):" >&2
  echo "  cd backend && python -m venv .venv && .venv\\Scripts\\activate && pip install -r requirements.txt" >&2
  exit 1
fi

if [[ -f .env ]]; then
  set -a
  source .env
  set +a
fi

api_base_url="${API_BASE_URL:-http://10.0.2.2:8000}"

if [[ -z "${SUPABASE_URL:-}" || -z "${SUPABASE_PUBLISHABLE_KEY:-}" ]]; then
  echo "error: SUPABASE_URL and SUPABASE_PUBLISHABLE_KEY are required." >&2
  echo "  Copy .env.example to .env at the repo root and fill in your values." >&2
  exit 1
fi

backend_pid=""
cleanup() {
  if [[ -n "$backend_pid" ]]; then
    echo
    echo "Stopping backend (pid $backend_pid)..."
    taskkill //PID "$backend_pid" //T //F >/dev/null 2>&1 || kill "$backend_pid" 2>/dev/null || true
  fi
}
trap cleanup EXIT INT TERM

echo "Starting backend (uvicorn --reload)..."
(cd backend && .venv/Scripts/python.exe -m uvicorn app.main:app --reload) &
backend_pid=$!

echo "Starting frontend (flutter run)..."
flutter run \
  --dart-define=API_BASE_URL="$api_base_url" \
  --dart-define=SUPABASE_URL="$SUPABASE_URL" \
  --dart-define=SUPABASE_PUBLISHABLE_KEY="$SUPABASE_PUBLISHABLE_KEY" \
  "$@"
