import importlib

from fastapi.testclient import TestClient


def test_api_job_flow(monkeypatch, tmp_path):
    from app.config.settings import settings

    settings.database_path = tmp_path / "test.sqlite"
    settings.ensure_dirs()

    import app.main as main
    importlib.reload(main)

    monkeypatch.setattr(main, "submit_ingest", lambda job_id: None)
    client = TestClient(main.app)

    created = client.post(
        "/api/jobs",
        json={
            "youtube_url": "https://www.youtube.com/watch?v=abcdefghijk",
            "speaker_name": "Speaker",
            "masjid_name": "Masjid",
            "clip_count": 3,
            "min_duration": 20,
            "max_duration": 60,
            "branding_profile": "default",
        },
    )
    assert created.status_code == 200
    job = created.json()

    fetched = client.get(f"/api/jobs/{job['id']}")
    assert fetched.status_code == 200
    assert fetched.json()["job"]["youtube_url"].endswith("abcdefghijk")


def test_render_endpoint_rejects_unlocked(monkeypatch, tmp_path):
    from app.config.settings import settings

    settings.database_path = tmp_path / "test.sqlite"
    settings.ensure_dirs()

    import app.main as main
    importlib.reload(main)

    monkeypatch.setattr(main, "submit_ingest", lambda job_id: None)
    client = TestClient(main.app)
    job = client.post(
        "/api/jobs",
        json={"youtube_url": "https://youtu.be/abcdefghijk"},
    ).json()

    blocked = client.post(f"/api/jobs/{job['id']}/render")
    assert blocked.status_code == 409
    assert "approve at least one selection" in blocked.json()["detail"]


def test_subtitle_preview_endpoint_returns_render_blocks(monkeypatch, tmp_path):
    from app.config.settings import settings
    from app.storage import repository as repo

    settings.database_path = tmp_path / "test.sqlite"
    settings.ensure_dirs()

    import app.main as main
    importlib.reload(main)

    monkeypatch.setattr(main, "submit_ingest", lambda job_id: None)
    client = TestClient(main.app)
    job = client.post("/api/jobs", json={"youtube_url": "https://youtu.be/abcdefghijk"}).json()
    repo.replace_transcript(
        job["id"],
        [{"start_time": 10, "end_time": 14, "text": "Allah reminds us to be sincere."}],
        [
            {"start_time": 10.0, "end_time": 10.5, "text": "Allah", "segment_index": 0},
            {"start_time": 10.5, "end_time": 11.0, "text": "reminds", "segment_index": 0},
            {"start_time": 11.0, "end_time": 11.5, "text": "us", "segment_index": 0},
        ],
        {"transcript_source": "test", "timing_source": "youtube_word", "timing_quality": "word"},
    )
    selection = repo.create_selection(
        job["id"],
        {
            "start_time": 10,
            "end_time": 14,
            "text_excerpt": "Allah reminds us to be sincere.",
            "source": "manual",
            "status": "approved",
        },
    )

    preview = client.get(f"/api/jobs/{job['id']}/selections/{selection['id']}/subtitle-preview")

    assert preview.status_code == 200
    payload = preview.json()
    assert payload["selection_id"] == selection["id"]
    assert payload["timing_source"] == "youtube_word"
    assert payload["blocks"][0]["tokens"][0]["text"] == "Allah"
    assert payload["blocks"][0]["tokens"][1]["start_time"] == 10.5


def test_subtitle_preview_render_does_not_create_outputs(monkeypatch, tmp_path):
    from app.config.settings import settings
    from app.storage import repository as repo

    settings.database_path = tmp_path / "test.sqlite"
    settings.ensure_dirs()

    import app.main as main
    importlib.reload(main)

    monkeypatch.setattr(main, "submit_ingest", lambda job_id: None)
    client = TestClient(main.app)
    job = client.post("/api/jobs", json={"youtube_url": "https://youtu.be/abcdefghijk"}).json()
    source = tmp_path / "source.mp4"
    source.write_bytes(b"video")
    repo.update_job(job["id"], source_video_path=str(source))
    repo.replace_transcript(
        job["id"],
        [{"start_time": 10, "end_time": 14, "text": "Allah reminds us."}],
        [{"start_time": 10.0, "end_time": 10.5, "text": "Allah", "segment_index": 0}],
        {"transcript_source": "test", "timing_source": "youtube_word", "timing_quality": "word"},
    )
    selection = repo.create_selection(
        job["id"],
        {
            "start_time": 10,
            "end_time": 14,
            "text_excerpt": "Allah reminds us.",
            "source": "manual",
            "status": "approved",
        },
    )

    def fake_render(job_arg, selection_arg, tokens_arg, output_dir, preview_start=None, preview_duration=8):
        target = output_dir / "preview.mp4"
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(b"mp4")
        return {
            "selection_id": selection_arg["id"],
            "start_time": preview_start or selection_arg["start_time"],
            "end_time": (preview_start or selection_arg["start_time"]) + preview_duration,
            "duration": preview_duration,
            "subtitle_offset_ms": selection_arg["subtitle_offset_ms"],
            "mp4": str(target),
        }

    monkeypatch.setattr(main, "render_subtitle_preview", fake_render)

    rendered = client.post(
        f"/api/jobs/{job['id']}/selections/{selection['id']}/subtitle-preview-render",
        json={"subtitle_offset_ms": -250, "crop_focus_x": 0.72, "crop_focus_y": 0.5},
    )

    assert rendered.status_code == 200
    payload = rendered.json()
    assert payload["preview_url"].endswith("/preview.mp4")
    assert payload["subtitle_offset_ms"] == -250
    assert repo.get_outputs(job["id"]) == []
