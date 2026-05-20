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
