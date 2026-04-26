#!/bin/zsh

set -euo pipefail

export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

ROOT="/Users/abbasanwar/Desktop/Projects/Khutbah Notes AI"
OUTPUT_DIR="$ROOT/transcripts/khutbah-streams"
PROJECT_ID="khutbah-notes-ai"
STATE_FILE="$ROOT/logs/weekly-masjid-publishing-state.json"

cd "$ROOT"

mkdir -p "$ROOT/logs"

exec node "$ROOT/functions/lib/runWeeklyMasjidWorkflow.js" \
  --output-dir "$OUTPUT_DIR" \
  --project-id "$PROJECT_ID" \
  --use-schedule-guard true \
  --state-file "$STATE_FILE" \
  --scheduled-weekday 6 \
  --scheduled-hour 20 \
  --scheduled-minute 40 \
  --catch-up-hours 72 \
  --publish-mode publish
