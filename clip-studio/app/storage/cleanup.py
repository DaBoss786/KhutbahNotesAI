from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime
import logging
import shutil
import time
from pathlib import Path

from app.config.settings import settings
from app.storage.db import db


logger = logging.getLogger("clip_studio.cleanup")

DEFAULT_MAX_AGE_DAYS = 7
DEFAULT_KEEP_RECENT = 10


@dataclass
class CleanupResult:
    deleted_count: int
    freed_bytes: int
    kept_count: int


def format_bytes(size: int) -> str:
    value = float(max(0, size))
    for unit in ["B", "KB", "MB", "GB", "TB"]:
        if value < 1024 or unit == "TB":
            return f"{value:.1f} {unit}" if unit != "B" else f"{int(value)} B"
        value /= 1024
    return f"{value:.1f} TB"


def folder_size(path: Path) -> int:
    total = 0
    for item in path.rglob("*"):
        try:
            if item.is_symlink():
                continue
            if item.is_file():
                total += item.stat().st_size
        except OSError:
            continue
    return total


def console_info(message: str) -> None:
    logger.info(message)
    print(f"[jobs-cleanup] {message}", flush=True)


def console_warning(message: str) -> None:
    logger.warning(message)
    print(f"[jobs-cleanup] WARNING: {message}", flush=True)


def direct_job_folders(jobs_dir: Path) -> list[Path]:
    root = jobs_dir.resolve()
    if not root.exists():
        return []
    folders: list[Path] = []
    for child in root.iterdir():
        try:
            if child.parent.resolve() != root:
                continue
            if child.is_symlink() or not child.is_dir():
                continue
        except OSError:
            continue
        folders.append(child)
    return folders


def parse_iso_timestamp(value: str | None) -> float | None:
    if not value:
        return None
    try:
        return datetime.fromisoformat(value.replace("Z", "+00:00")).timestamp()
    except ValueError:
        return None


def job_folder_timestamps() -> dict[str, float]:
    try:
        with db() as conn:
            rows = conn.execute("SELECT id, created_at, updated_at FROM jobs").fetchall()
    except Exception:
        return {}
    timestamps: dict[str, float] = {}
    for row in rows:
        values = [
            parsed
            for parsed in (
                parse_iso_timestamp(row["created_at"]),
                parse_iso_timestamp(row["updated_at"]),
            )
            if parsed is not None
        ]
        if values:
            timestamps[row["id"]] = max(values)
    return timestamps


def cleanup_jobs_folder(
    max_age_days: int = DEFAULT_MAX_AGE_DAYS,
    keep_recent: int = DEFAULT_KEEP_RECENT,
) -> CleanupResult:
    jobs_dir = settings.jobs_dir
    jobs_dir.mkdir(parents=True, exist_ok=True)
    root = jobs_dir.resolve()
    now = time.time()
    cutoff = now - max_age_days * 24 * 60 * 60

    folders = direct_job_folders(root)
    db_timestamps = job_folder_timestamps()
    stats: list[tuple[Path, float]] = []
    for folder in folders:
        try:
            folder_mtime = folder.stat().st_mtime
            effective_time = max(folder_mtime, db_timestamps.get(folder.name, folder_mtime))
            stats.append((folder, effective_time))
        except OSError:
            continue

    to_delete: dict[Path, str] = {
        folder: "older than retention window"
        for folder, mtime in stats
        if mtime < cutoff
    }

    remaining = [(folder, mtime) for folder, mtime in stats if folder not in to_delete]
    remaining.sort(key=lambda item: item[1], reverse=True)
    for folder, _mtime in remaining[max(0, keep_recent) :]:
        to_delete[folder] = f"outside most recent {keep_recent} folders"

    deleted_count = 0
    freed_bytes = 0
    for folder, reason in sorted(to_delete.items(), key=lambda item: item[0].name):
        try:
            if folder.parent.resolve() != root or folder.resolve() == root:
                console_warning(f"Skipped unsafe jobs cleanup target: {folder}")
                continue
            if folder.is_symlink() or not folder.is_dir():
                console_warning(f"Skipped non-directory jobs cleanup target: {folder}")
                continue
            size = folder_size(folder)
            shutil.rmtree(folder)
            deleted_count += 1
            freed_bytes += size
            console_info(f"Deleted job folder {folder.name} ({reason}, freed {format_bytes(size)}).")
        except Exception as exc:
            console_warning(f"Could not delete job folder {folder}: {exc}")

    kept_count = max(0, len(stats) - deleted_count)
    console_info(
        "Jobs cleanup complete: "
        f"deleted {deleted_count} folder(s), freed {format_bytes(freed_bytes)}, kept {kept_count} folder(s)."
    )
    return CleanupResult(deleted_count=deleted_count, freed_bytes=freed_bytes, kept_count=kept_count)
