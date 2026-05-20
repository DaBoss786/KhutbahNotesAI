#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

if ! command -v python3.12 >/dev/null 2>&1; then
  echo "python3.12 is required. Install with: brew install python@3.12"
  exit 1
fi

if [ ! -d ".venv" ]; then
  python3.12 -m venv .venv
fi

source .venv/bin/activate
python -m pip install --upgrade pip >/dev/null
python -m pip install -r requirements.txt

mkdir -p data jobs outputs tmp
python -m app.bootstrap

HOST="${APP_HOST:-127.0.0.1}"
PORT="${APP_PORT:-8787}"
exec uvicorn app.main:app --host "$HOST" --port "$PORT" --reload

