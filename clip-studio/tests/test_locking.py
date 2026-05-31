from app.storage.db import init_db
from app.storage import repository as repo


def test_lock_requires_approved_selection(tmp_path):
    from app.config.settings import settings

    settings.database_path = tmp_path / "test.sqlite"
    settings.ensure_dirs()
    init_db()
    job = repo.create_job({"youtube_url": "https://youtu.be/abcdefghijk", "clip_count": 3})

    try:
        repo.lock_job(job["id"])
    except ValueError as exc:
        assert "At least one approved selection" in str(exc)
    else:
        raise AssertionError("lock_job should reject jobs without approved selections")


def test_edit_after_lock_auto_unlocks(tmp_path):
    from app.config.settings import settings

    settings.database_path = tmp_path / "test.sqlite"
    settings.ensure_dirs()
    init_db()
    job = repo.create_job({"youtube_url": "https://youtu.be/abcdefghijk", "clip_count": 3})
    selection = repo.create_selection(
        job["id"],
        {
            "start_time": 10,
            "end_time": 40,
            "text_excerpt": "A complete reminder about prayer and sincerity.",
            "source": "manual",
            "status": "approved",
        },
    )
    locked = repo.lock_job(job["id"])
    assert locked["locked_at"]

    repo.update_selection(job["id"], selection["id"], {"end_time": 45})
    unlocked = repo.get_job(job["id"])
    assert unlocked["locked_at"] is None


def test_framing_edit_persists_and_auto_unlocks(tmp_path):
    from app.config.settings import settings

    settings.database_path = tmp_path / "test.sqlite"
    settings.ensure_dirs()
    init_db()
    job = repo.create_job({"youtube_url": "https://youtu.be/abcdefghijk", "clip_count": 3})
    selection = repo.create_selection(
        job["id"],
        {
            "start_time": 10,
            "end_time": 40,
            "text_excerpt": "A complete reminder about prayer and sincerity.",
            "source": "manual",
            "status": "approved",
        },
    )
    repo.lock_job(job["id"])

    updated = repo.update_selection(job["id"], selection["id"], {"crop_focus_x": 0.72, "crop_focus_y": 0.44})

    assert updated["crop_focus_x"] == 0.72
    assert updated["crop_focus_y"] == 0.44
    assert repo.get_job(job["id"])["locked_at"] is None


def test_subtitle_offset_persists_and_auto_unlocks(tmp_path):
    from app.config.settings import settings

    settings.database_path = tmp_path / "test.sqlite"
    settings.ensure_dirs()
    init_db()
    job = repo.create_job({"youtube_url": "https://youtu.be/abcdefghijk", "clip_count": 3})
    selection = repo.create_selection(
        job["id"],
        {
            "start_time": 10,
            "end_time": 40,
            "text_excerpt": "A complete reminder about prayer and sincerity.",
            "source": "manual",
            "status": "approved",
        },
    )
    repo.lock_job(job["id"])

    updated = repo.update_selection(job["id"], selection["id"], {"subtitle_offset_ms": -250})

    assert updated["subtitle_offset_ms"] == -250
    assert repo.get_job(job["id"])["locked_at"] is None


def test_render_allowed_only_when_locked(tmp_path):
    from app.config.settings import settings

    settings.database_path = tmp_path / "test.sqlite"
    settings.ensure_dirs()
    init_db()
    job = repo.create_job({"youtube_url": "https://youtu.be/abcdefghijk", "clip_count": 3})
    repo.create_selection(
        job["id"],
        {
            "start_time": 10,
            "end_time": 40,
            "text_excerpt": "A complete reminder about prayer and sincerity.",
            "source": "manual",
            "status": "approved",
        },
    )

    try:
        repo.validate_render_allowed(job["id"])
    except ValueError as exc:
        assert "lock final selections" in str(exc)
    else:
        raise AssertionError("render should be blocked before locking")

    repo.lock_job(job["id"])
    repo.validate_render_allowed(job["id"])
