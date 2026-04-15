#!/bin/zsh

set -euo pipefail

export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

ROOT="/Users/abbasanwar/Desktop/Projects/Khutbah Notes AI"
OUTPUT_DIR="$ROOT/transcripts/khutbah-streams"
PROJECT_ID="khutbah-notes-ai"

cd "$ROOT"

exec npm --prefix functions run masjid:run-weekly-workflow -- \
  --output-dir "$OUTPUT_DIR" \
  --project-id "$PROJECT_ID" \
  --publish-mode publish
