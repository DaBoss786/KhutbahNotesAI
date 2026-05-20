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
