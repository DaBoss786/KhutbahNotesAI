from __future__ import annotations

import os
import time

from app.config.settings import settings
from app.storage.cleanup import cleanup_jobs_folder
from app.storage.db import init_db
from app.storage import repository as repo


def make_job_folder(root, name: str, age_days: float, size: int = 16):
    folder = root / name
    folder.mkdir(parents=True)
    (folder / "source.mp4").write_bytes(b"x" * size)
    stamp = time.time() - age_days * 24 * 60 * 60
    os.utime(folder / "source.mp4", (stamp, stamp))
    os.utime(folder, (stamp, stamp))
    return folder


def test_cleanup_deletes_old_job_folders_only(monkeypatch, tmp_path, capsys):
    monkeypatch.setattr(settings, "root", tmp_path)
    jobs_dir = settings.jobs_dir
    jobs_dir.mkdir(parents=True)
    old_folder = make_job_folder(jobs_dir, "job_old", age_days=8, size=32)
    recent_folder = make_job_folder(jobs_dir, "job_recent", age_days=1, size=64)
    root_file = jobs_dir / "keep.txt"
    root_file.write_text("not a folder", encoding="utf-8")
    outside = tmp_path / "outside"
    outside.mkdir()
    (outside / "important.txt").write_text("keep", encoding="utf-8")
    (jobs_dir / "outside_link").symlink_to(outside)

    result = cleanup_jobs_folder(max_age_days=7, keep_recent=10)

    assert result.deleted_count == 1
    assert result.freed_bytes == 32
    assert not old_folder.exists()
    assert recent_folder.exists()
    assert jobs_dir.exists()
    assert root_file.exists()
    assert outside.exists()
    assert (outside / "important.txt").exists()
    assert "deleted 1 folder(s)" in capsys.readouterr().out


def test_cleanup_keeps_only_most_recent_job_folders(monkeypatch, tmp_path):
    monkeypatch.setattr(settings, "root", tmp_path)
    jobs_dir = settings.jobs_dir
    jobs_dir.mkdir(parents=True)
    for index in range(12):
        make_job_folder(jobs_dir, f"job_{index:02d}", age_days=index * 0.01)

    result = cleanup_jobs_folder(max_age_days=7, keep_recent=10)

    remaining = sorted(path.name for path in jobs_dir.iterdir() if path.is_dir())
    assert result.deleted_count == 2
    assert remaining == [f"job_{index:02d}" for index in range(10)]


def test_cleanup_uses_database_timestamp_for_known_jobs(monkeypatch, tmp_path):
    monkeypatch.setattr(settings, "root", tmp_path)
    monkeypatch.setattr(settings, "database_path", tmp_path / "test.sqlite")
    settings.ensure_dirs()
    init_db()
    job = repo.create_job({"youtube_url": "https://youtu.be/abcdefghijk"})
    folder = make_job_folder(settings.jobs_dir, job["id"], age_days=30)

    result = cleanup_jobs_folder(max_age_days=7, keep_recent=10)

    assert result.deleted_count == 0
    assert folder.exists()
