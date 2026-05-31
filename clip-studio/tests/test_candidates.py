from app.selection.candidates import build_openai_prompt, fallback_candidates


def test_candidate_filters_dua_and_arabic_only():
    segments = [
        {
            "start_time": 0,
            "end_time": 25,
            "text": "Please make dua for brother Ahmed and remember the announcements after salah.",
        },
        {
            "start_time": 25,
            "end_time": 55,
            "text": "الحمد لله رب العالمين الرحمن الرحيم مالك يوم الدين",
        },
        {
            "start_time": 55,
            "end_time": 88,
            "text": "Allah reminds us that gratitude changes how we see hardship. When a believer pauses and thanks Allah, the heart becomes steadier and the next right action becomes clearer.",
        },
    ]
    candidates = fallback_candidates(segments, 5, 20, 60)
    assert len(candidates) == 1
    assert "gratitude" in candidates[0]["text_excerpt"].lower()


def test_openai_prompt_ranks_curated_windows_without_losing_review_rules():
    segments = [
        {
            "start_time": 0,
            "end_time": 25,
            "text": "Please make dua for brother Ahmed and remember the announcements after salah.",
        },
        {
            "start_time": 25,
            "end_time": 55,
            "text": "Allah reminds us that repentance is not only regret. It is returning with hope, choosing one action today, and trusting that Allah's mercy is greater than our mistake.",
        },
        {
            "start_time": 55,
            "end_time": 85,
            "text": "When the Prophet taught sincerity, he showed that private worship can change public character. The point is simple: protect one deed that only Allah sees.",
        },
    ]

    prompt = build_openai_prompt(segments, clip_count=3, min_duration=20, max_duration=60)

    assert prompt["selection_goal"].startswith("Publish-ready")
    assert "short_form_retention" in prompt["rubric"]
    assert any("closing dua" in item for item in prompt["hard_exclusions"])
    assert all("make dua for brother Ahmed" not in item["text_excerpt"] for item in prompt["candidate_windows"])
    assert len(prompt["candidate_windows"]) == 2


def test_openai_prompt_includes_caption_learning_examples_when_available():
    segments = [
        {
            "start_time": 0,
            "end_time": 35,
            "text": "Allah teaches us that sincere repentance has a beginning, a complete return, and a practical change today.",
        }
    ]
    learning_context = {
        "stats": {"positive": 1, "negative": 1, "total": 2},
        "positive_examples": [
            {
                "outcome": "rendered",
                "title": "Sincere Repentance",
                "text": "A complete reminder about returning to Allah with one clear action.",
                "duration": 34.0,
                "boundary_start_delta": -4.0,
                "boundary_end_delta": 6.0,
            }
        ],
        "negative_examples": [
            {
                "outcome": "rejected_candidate",
                "title": "Mid Thought",
                "text": "And this is why it matters from the thing we said before.",
                "duration": 30.0,
                "boundary_start_delta": None,
                "boundary_end_delta": None,
            }
        ],
    }

    prompt = build_openai_prompt(segments, 3, 20, 60, learning_context)

    assert "user_preference_examples" in prompt
    assert prompt["user_preference_examples"]["positive_examples"][0]["outcome"] == "rendered"
    assert "caption-only" in prompt["user_preference_examples"]["description"].lower()
