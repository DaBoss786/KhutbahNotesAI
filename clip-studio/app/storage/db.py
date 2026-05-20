from __future__ import annotations

from contextlib import contextmanager
from datetime import datetime, timezone
import json
import sqlite3
from typing import Any, Iterator

from app.config.settings import settings


def now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


def connect() -> sqlite3.Connection:
    settings.ensure_dirs()
    conn = sqlite3.connect(settings.database_path)
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA foreign_keys = ON")
    return conn


@contextmanager
def db() -> Iterator[sqlite3.Connection]:
    conn = connect()
    try:
        yield conn
        conn.commit()
    finally:
        conn.close()


def row_to_dict(row: sqlite3.Row | None) -> dict[str, Any] | None:
    if row is None:
        return None
    data = dict(row)
    for key in ("metadata", "branding", "rubric", "scores", "rationale", "render_payload"):
        if key in data and isinstance(data[key], str) and data[key]:
            try:
                data[key] = json.loads(data[key])
            except json.JSONDecodeError:
                pass
    return data


def json_dumps(value: Any) -> str:
    return json.dumps(value, ensure_ascii=False, separators=(",", ":"))


def init_db() -> None:
    settings.ensure_dirs()
    with db() as conn:
        conn.executescript(
            """
            CREATE TABLE IF NOT EXISTS jobs (
                id TEXT PRIMARY KEY,
                youtube_url TEXT NOT NULL,
                video_id TEXT,
                title TEXT,
                speaker_name TEXT,
                masjid_name TEXT,
                requested_clip_count INTEGER NOT NULL,
                min_duration REAL NOT NULL,
                max_duration REAL NOT NULL,
                branding TEXT NOT NULL,
                status TEXT NOT NULL,
                stage TEXT NOT NULL,
                ai_mode TEXT NOT NULL,
                locked_at TEXT,
                locked_by TEXT,
                render_confirmed_at TEXT,
                error_message TEXT,
                source_video_path TEXT,
                source_audio_path TEXT,
                created_at TEXT NOT NULL,
                updated_at TEXT NOT NULL
            );

            CREATE TABLE IF NOT EXISTS logs (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                job_id TEXT NOT NULL REFERENCES jobs(id) ON DELETE CASCADE,
                level TEXT NOT NULL,
                message TEXT NOT NULL,
                created_at TEXT NOT NULL
            );

            CREATE TABLE IF NOT EXISTS transcript_segments (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                job_id TEXT NOT NULL REFERENCES jobs(id) ON DELETE CASCADE,
                start_time REAL NOT NULL,
                end_time REAL NOT NULL,
                text TEXT NOT NULL
            );

            CREATE TABLE IF NOT EXISTS transcript_tokens (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                job_id TEXT NOT NULL REFERENCES jobs(id) ON DELETE CASCADE,
                segment_id INTEGER REFERENCES transcript_segments(id) ON DELETE CASCADE,
                start_time REAL NOT NULL,
                end_time REAL NOT NULL,
                text TEXT NOT NULL,
                token_index INTEGER NOT NULL
            );

            CREATE TABLE IF NOT EXISTS candidates (
                id TEXT PRIMARY KEY,
                job_id TEXT NOT NULL REFERENCES jobs(id) ON DELETE CASCADE,
                start_time REAL NOT NULL,
                end_time REAL NOT NULL,
                title TEXT NOT NULL,
                text_excerpt TEXT NOT NULL,
                quality_score REAL NOT NULL,
                status TEXT NOT NULL,
                scores TEXT NOT NULL,
                rationale TEXT NOT NULL,
                source TEXT NOT NULL,
                created_at TEXT NOT NULL,
                updated_at TEXT NOT NULL
            );

            CREATE TABLE IF NOT EXISTS selections (
                id TEXT PRIMARY KEY,
                job_id TEXT NOT NULL REFERENCES jobs(id) ON DELETE CASCADE,
                candidate_id TEXT REFERENCES candidates(id) ON DELETE SET NULL,
                start_time REAL NOT NULL,
                end_time REAL NOT NULL,
                text_excerpt TEXT NOT NULL,
                source TEXT NOT NULL,
                status TEXT NOT NULL,
                locked_at TEXT,
                locked_by TEXT,
                intro_title TEXT,
                intro_subtitle TEXT,
                outro_title TEXT,
                outro_subtitle TEXT,
                edited_at TEXT NOT NULL,
                created_at TEXT NOT NULL
            );

            CREATE TABLE IF NOT EXISTS outputs (
                id TEXT PRIMARY KEY,
                job_id TEXT NOT NULL REFERENCES jobs(id) ON DELETE CASCADE,
                selection_id TEXT REFERENCES selections(id) ON DELETE SET NULL,
                kind TEXT NOT NULL,
                path TEXT NOT NULL,
                status TEXT NOT NULL,
                error_message TEXT,
                render_payload TEXT,
                created_at TEXT NOT NULL,
                updated_at TEXT NOT NULL
            );
            """
        )
        ensure_column(conn, "selections", "intro_title", "TEXT")
        ensure_column(conn, "selections", "intro_subtitle", "TEXT")
        ensure_column(conn, "selections", "outro_title", "TEXT")
        ensure_column(conn, "selections", "outro_subtitle", "TEXT")


def ensure_column(conn: sqlite3.Connection, table: str, column: str, definition: str) -> None:
    rows = conn.execute(f"PRAGMA table_info({table})").fetchall()
    if column not in {row["name"] for row in rows}:
        conn.execute(f"ALTER TABLE {table} ADD COLUMN {column} {definition}")
