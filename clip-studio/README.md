# Khutbah Clip Studio

Local web app for turning one YouTube khutbah URL into reviewed, locked, and explicitly rendered 9:16 short clips.

## What It Does

1. Ingests a YouTube URL and downloads local media.
2. Gets captions when available, otherwise runs local Whisper transcription.
3. Generates clip candidates with fallback heuristics or OpenAI-enhanced ranking of curated transcript windows.
4. Requires candidate review, transcript boundary review, approval, and lock.
5. Renders only locked and approved clips after explicit confirmation.
6. Exports MP4 clips, thumbnails, JSON/CSV metadata, and a zip bundle.

The app runs only on `localhost`. It stores jobs in SQLite and media files under local folders.

## Setup

From this folder:

```bash
cp .env.example .env
```

Add your OpenAI key:

```bash
OPENAI_API_KEY=sk-proj-your-key-here
```

Then start:

```bash
./scripts/start.sh
```

Open:

```text
http://127.0.0.1:8787
```

## Verify OpenAI Is Loaded

At startup and in the top-right app badge:

- `AI Enhanced Mode: ON` means the backend found and validated `OPENAI_API_KEY`.
- `AI Enhanced Mode: OFF (fallback mode)` means the key is missing, invalid, or unreachable.

You can also visit:

```text
http://127.0.0.1:8787/api/system/ai-status
```

## OpenAI Troubleshooting

- Make sure `.env` is in this folder: `clip-studio/.env`.
- Make sure the variable name is exactly `OPENAI_API_KEY`.
- Restart the app after editing `.env`.
- If the key is invalid or billing is unavailable, the app still runs in fallback mode.
- The key is used only by the FastAPI backend. It is never embedded in frontend HTML or JavaScript.

## Local Dependencies

The startup script expects:

- macOS
- Homebrew
- `python3.12`
- `ffmpeg`
- `yt-dlp`

Install missing tools:

```bash
brew install python@3.12 ffmpeg yt-dlp
```

## Review-First Render Rules

Rendering is blocked unless all are true:

- at least one selection is approved
- final selections are explicitly locked
- you click render and confirm

Any edit after locking automatically unlocks the job and requires relocking before render.

## Run Tests

```bash
source .venv/bin/activate
pytest
```

## Example Run

Use a khutbah YouTube URL from one of the Khutbah Notes masjid channels. Recommended first test: use a 5-15 minute clip or a shorter khutbah to validate the flow quickly.

Steps:

1. New Job: paste the URL and keep default 5 clips, 20-60 seconds.
2. Candidate Review: approve at least 3 strong candidates.
3. Transcript Review: adjust boundaries and confirm duration warnings are clear.
4. Finalize & Lock: lock final selections.
5. Render & Export: confirm render and download the zip.

Rendered outputs appear in:

```text
outputs/<job_id>/
```

## Next Improvements

- Analytics loop for hook retention and manual quality ratings.
- Optional scheduler for weekly masjid clip queues.
- A/B hook testing for intro card wording.
- Stronger speaker auto-reframe using face tracking across frames.
- Optional app-store QR code in outro card.
