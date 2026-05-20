from __future__ import annotations

import json
import math
import re
from typing import Any

from app.config.settings import settings


OPENAI_SYSTEM_PROMPT = """
Return strict JSON only with a top-level candidates array.

You are selecting short-form Islamic reminder clips from a khutbah transcript for
a human review workflow. Do not summarize the khutbah. Find the strongest
standalone moments for 20-60 second vertical videos.

Choose moments that make sense to a viewer with no prior context, contain one
clear complete takeaway, begin naturally, end naturally, and feel spiritually
relevant, practical, memorable, or emotionally resonant.

Prefer actionable reminders, clearly explained Quranic references or prophetic
examples, story moments with a clear lesson, quotable lines, and reminders tied
to daily life, worship, character, family, repentance, hope, sincerity, or
akhirah.

Reject Arabic-only or recitation-heavy passages, closing dua blocks, named
personal dua requests, announcements, fundraising, repeated caption artifacts,
fragments that start mid-thought, and snippets that require previous context.

Return fewer than requested if the remaining options are weak. Empty is better
than weak.

For each candidate include start_time, end_time, title, text_excerpt,
quality_score, scores, rationale, hook, main_point, start_reason, end_reason,
and risk_flags.
""".strip()


BAD_PATTERNS = [
    r"\bmake dua\b",
    r"\bdua for\b",
    r"\bmay allah (?:bless|forgive|grant)\b",
    r"\bannouncements?\b",
    r"\bdonate\b",
    r"\bsponsor\b",
    r"\bplease remember\b",
]


def mostly_arabic(text: str) -> bool:
    letters = [c for c in text if c.isalpha()]
    if not letters:
        return False
    arabic = [c for c in letters if "\u0600" <= c <= "\u06ff"]
    return len(arabic) / len(letters) > 0.45


def bad_context(text: str) -> str | None:
    lower = text.lower()
    if mostly_arabic(text):
        return "Arabic-only or mostly Arabic recitation."
    for pattern in BAD_PATTERNS:
        if re.search(pattern, lower):
            return "Likely announcement, closing dua, or named dua request."
    if lower.startswith(("and ", "so ", "but ", "because ", "this ", "that ")):
        return "Starts mid-thought."
    return None


def score_text(text: str) -> tuple[float, dict[str, float], dict[str, str]]:
    words = re.findall(r"\w+", text)
    unique = len(set(w.lower() for w in words))
    lower = text.lower()
    practical = sum(1 for w in ["remember", "should", "must", "can", "heart", "life", "family", "prayer", "quran", "allah"] if w in lower)
    emotional = sum(1 for w in ["mercy", "hope", "fear", "love", "forgive", "grateful", "sincere", "struggle"] if w in lower)
    completeness = 1.0 if text.rstrip().endswith((".", "!", "?")) and len(words) >= 45 else 0.55
    clarity = min(1.0, unique / max(1, len(words)) * 1.8)
    benefit = min(1.0, practical / 5)
    resonance = min(1.0, emotional / 3)
    relevance = 1.0 if any(w in lower for w in ["allah", "quran", "prophet", "islam", "salah", "akhirah"]) else 0.55
    context = 1.0 if not bad_context(text) else 0.0
    scores = {
        "clarity": clarity,
        "completeness": completeness,
        "practical_benefit": benefit,
        "emotional_resonance": resonance,
        "islamic_relevance": relevance,
        "context_integrity": context,
    }
    weighted = (
        clarity * 0.18
        + completeness * 0.2
        + benefit * 0.18
        + resonance * 0.14
        + relevance * 0.16
        + context * 0.14
    )
    bonus = 0.08 if any(w in lower for w in ["quran", "ayah", "allah says", "prophet"]) else 0
    return round(min(1.0, weighted + bonus), 3), scores, {"fallback": "Heuristic score from clarity, completeness, benefit, resonance, relevance, and context integrity."}


def make_title(text: str) -> str:
    words = re.findall(r"[A-Za-z']+", text)
    meaningful = [w for w in words if len(w) > 3][:7]
    if not meaningful:
        return "Khutbah Reminder"
    return " ".join(meaningful).title()[:70]


def semantic_windows(segments: list[dict], min_duration: float, max_duration: float) -> list[dict]:
    windows: list[dict] = []
    i = 0
    while i < len(segments):
        start = float(segments[i]["start_time"])
        parts: list[str] = []
        end = start
        j = i
        while j < len(segments) and end - start < min_duration:
            parts.append(segments[j]["text"])
            end = float(segments[j]["end_time"])
            j += 1
        while j < len(segments) and end - start < max_duration:
            next_text = segments[j]["text"]
            parts.append(next_text)
            end = float(segments[j]["end_time"])
            j += 1
            if next_text.rstrip().endswith((".", "?", "!")) and end - start >= min_duration:
                break
        text = re.sub(r"\s+", " ", " ".join(parts)).strip()
        if text and min_duration <= end - start <= max_duration:
            windows.append({"start_time": start, "end_time": end, "text_excerpt": text})
        i = max(i + 1, j - 1)
    return windows


def fallback_candidates(segments: list[dict], clip_count: int, min_duration: float, max_duration: float) -> list[dict]:
    candidates: list[dict] = []
    for window in semantic_windows(segments, min_duration, max_duration):
        reason = bad_context(window["text_excerpt"])
        if reason:
            continue
        score, scores, rationale = score_text(window["text_excerpt"])
        if score < 0.48:
            continue
        candidates.append(
            {
                "start_time": window["start_time"],
                "end_time": window["end_time"],
                "title": make_title(window["text_excerpt"]),
                "text_excerpt": window["text_excerpt"],
                "quality_score": score,
                "scores": scores,
                "rationale": rationale,
                "source": "fallback",
            }
        )
    candidates.sort(key=lambda c: c["quality_score"], reverse=True)
    return candidates[:clip_count]


def ranked_windows(segments: list[dict], min_duration: float, max_duration: float, limit: int = 40) -> list[dict]:
    windows: list[dict] = []
    for index, window in enumerate(semantic_windows(segments, min_duration, max_duration), start=1):
        reason = bad_context(window["text_excerpt"])
        if reason:
            continue
        score, scores, rationale = score_text(window["text_excerpt"])
        windows.append(
            {
                "window_id": f"window_{index}",
                "start_time": window["start_time"],
                "end_time": window["end_time"],
                "duration": round(float(window["end_time"]) - float(window["start_time"]), 2),
                "text_excerpt": window["text_excerpt"],
                "heuristic_score": score,
                "heuristic_scores": scores,
                "heuristic_rationale": rationale,
            }
        )
    windows.sort(key=lambda item: item["heuristic_score"], reverse=True)
    return windows[:limit]


def build_openai_prompt(segments: list[dict], clip_count: int, min_duration: float, max_duration: float) -> dict[str, Any]:
    transcript = "\n".join(
        f"[{s['start_time']:.1f}-{s['end_time']:.1f}] {s['text']}" for s in segments[:900]
    )
    candidate_windows = ranked_windows(
        segments,
        min_duration,
        max_duration,
        limit=max(24, min(60, clip_count * 10)),
    )
    return {
        "task": "Select the most relevant, impactful, complete khutbah short-video candidates for human review.",
        "selection_goal": "Publish-ready Islamic reminder clips that work for viewers encountering the clip cold.",
        "count_requested": clip_count,
        "duration_seconds": {
            "min": min_duration,
            "max": max_duration,
        },
        "candidate_windows": candidate_windows,
        "instructions": [
            "Rank the candidate_windows by actual short-form value, not just topic importance.",
            "Prefer one complete point over broad summaries or setup-heavy passages.",
            "Optimize boundaries so the clip starts where the point begins and ends when the thought is complete.",
            "You may adjust start_time and end_time within nearby transcript boundaries if it improves completeness.",
            "Do not force the requested count; return fewer candidates if the remaining windows are weak.",
        ],
        "rubric": {
            "clarity": "The point is easy to understand immediately.",
            "completeness": "The clip contains setup, point, and payoff without needing prior context.",
            "practical_benefit": "The listener can apply the reminder in daily life.",
            "emotional_resonance": "The moment feels memorable, sincere, hopeful, urgent, or spiritually moving.",
            "islamic_relevance": "The lesson is clearly tied to Islamic belief, worship, character, Quran, Sunnah, or akhirah.",
            "context_integrity": "The clip does not distort the speaker's meaning or depend on missing context.",
            "short_form_retention": "The first few seconds invite continued watching and the ending feels satisfying.",
        },
        "hard_exclusions": [
            "Arabic-only or recitation-heavy passages without clear English explanation",
            "closing dua blocks",
            "named personal dua requests",
            "announcements, logistics, fundraising, or sponsor messages",
            "snippets requiring prior explanation",
            "repeated rolling-caption artifacts",
        ],
        "reference_transcript": transcript,
        "output_contract": {
            "candidates": [
                {
                    "start_time": "number",
                    "end_time": "number",
                    "title": "short natural title, not clickbait",
                    "text_excerpt": "verbatim or near-verbatim selected text",
                    "quality_score": "0.0 to 1.0",
                    "scores": {
                        "clarity": "0.0 to 1.0",
                        "completeness": "0.0 to 1.0",
                        "practical_benefit": "0.0 to 1.0",
                        "emotional_resonance": "0.0 to 1.0",
                        "islamic_relevance": "0.0 to 1.0",
                        "context_integrity": "0.0 to 1.0",
                        "short_form_retention": "0.0 to 1.0",
                    },
                    "rationale": "brief explanation for human review",
                    "hook": "why the opening works",
                    "main_point": "one-sentence takeaway",
                    "start_reason": "why this start boundary is natural",
                    "end_reason": "why this end boundary is complete",
                    "risk_flags": ["possible issues, or empty array"],
                }
            ]
        },
    }


def normalize_openai_candidate(item: dict[str, Any], min_duration: float, max_duration: float) -> dict[str, Any] | None:
    duration = float(item["end_time"]) - float(item["start_time"])
    text_excerpt = item.get("text_excerpt") or item.get("summary") or ""
    if not (min_duration <= duration <= max_duration) or not text_excerpt or bad_context(text_excerpt):
        return None
    rationale = item.get("rationale") or item.get("reason") or "OpenAI-ranked candidate."
    if not isinstance(rationale, dict):
        rationale = {"summary": rationale}
    for key in ("hook", "main_point", "start_reason", "end_reason", "risk_flags"):
        if key in item and item[key]:
            rationale[key] = item[key]
    title = str(item.get("title") or make_title(text_excerpt))[:90]
    return {
        **item,
        "source": "openai",
        "title": title,
        "quality_score": round(float(item.get("quality_score", 0.7)), 3),
        "text_excerpt": text_excerpt,
        "scores": item.get("scores") or {},
        "rationale": rationale,
    }


def enhance_with_openai(segments: list[dict], fallback: list[dict], clip_count: int, min_duration: float, max_duration: float) -> list[dict]:
    if not settings.openai_api_key:
        return fallback
    try:
        from openai import OpenAI
        client = OpenAI(api_key=settings.openai_api_key)
        prompt = build_openai_prompt(segments, clip_count, min_duration, max_duration)
        response = client.responses.create(
            model=settings.openai_model,
            input=[
                {
                    "role": "system",
                    "content": OPENAI_SYSTEM_PROMPT,
                },
                {"role": "user", "content": json.dumps(prompt, ensure_ascii=False)},
            ],
            text={"format": {"type": "json_object"}},
        )
        parsed = json.loads(response.output_text)
        enhanced = []
        for item in parsed.get("candidates", []):
            candidate = normalize_openai_candidate(item, min_duration, max_duration)
            if candidate:
                enhanced.append(candidate)
        return enhanced[:clip_count] or fallback
    except Exception:
        return fallback


def generate_candidates(segments: list[dict], clip_count: int, min_duration: float, max_duration: float) -> list[dict]:
    fallback = fallback_candidates(segments, clip_count, min_duration, max_duration)
    return enhance_with_openai(segments, fallback, clip_count, min_duration, max_duration)
