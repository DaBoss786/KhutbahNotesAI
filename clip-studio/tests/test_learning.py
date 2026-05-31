from app.storage.db import init_db
from app.storage import repository as repo


def test_learning_sync_records_locked_positive_and_rejected_candidate(tmp_path):
    from app.config.settings import settings

    settings.database_path = tmp_path / "test.sqlite"
    settings.ensure_dirs()
    init_db()
    job = repo.create_job({"youtube_url": "https://youtu.be/abcdefghijk", "clip_count": 3})
    repo.replace_candidates(
        job["id"],
        [
            {
                "id": "cand_good",
                "start_time": 10,
                "end_time": 42,
                "title": "Repentance With Action",
                "text_excerpt": "Allah reminds us that repentance is a complete return with one practical action today.",
                "quality_score": 0.9,
                "scores": {},
                "rationale": {},
                "source": "openai",
            },
            {
                "id": "cand_bad",
                "start_time": 50,
                "end_time": 82,
                "title": "Mid Thought",
                "text_excerpt": "And this is why the earlier thing we mentioned matters for everyone.",
                "quality_score": 0.6,
                "scores": {},
                "rationale": {},
                "source": "openai",
            },
        ],
    )
    repo.set_candidate_approvals(job["id"], {"cand_good": "approved", "cand_bad": "rejected"})
    selection = [s for s in repo.get_selections(job["id"]) if s["candidate_id"] == "cand_good"][0]
    repo.update_selection(
        job["id"],
        selection["id"],
        {
            "start_time": 8,
            "end_time": 48,
            "text_excerpt": "Allah reminds us that repentance is a complete return with one practical action today and a hopeful next step.",
        },
    )
    repo.lock_job(job["id"])

    stats = repo.learning_stats()
    examples = repo.learning_examples_for_prompt("repentance action hopeful")

    assert stats["positive"] == 1
    assert stats["negative"] == 1
    assert examples["positive_examples"][0]["boundary_start_delta"] == -2.0
    assert examples["positive_examples"][0]["boundary_end_delta"] == 6.0
    assert examples["negative_examples"][0]["outcome"] == "rejected_candidate"


def test_learning_sync_does_not_record_unlocked_approval_as_positive(tmp_path):
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

    learned = repo.sync_learning_examples_for_job(job["id"])

    assert selection["status"] == "approved"
    assert learned["positive"] == 0
    assert repo.learning_stats()["total"] == 0
