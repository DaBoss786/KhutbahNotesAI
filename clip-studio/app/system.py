from __future__ import annotations

import shutil

from app.config.settings import settings


def dependency_status() -> dict:
    return {
        "ffmpeg": bool(shutil.which("ffmpeg")),
        "yt_dlp": bool(shutil.which("yt-dlp")),
    }


def ai_status(validate: bool = False) -> dict:
    if not settings.openai_api_key:
        return {
            "enabled": False,
            "label": "AI Enhanced Mode: OFF (fallback mode)",
            "reason": "OPENAI_API_KEY is missing.",
        }
    if not validate:
        return {
            "enabled": True,
            "label": "AI Enhanced Mode: ON",
            "reason": "OPENAI_API_KEY is present.",
        }
    try:
        from openai import OpenAI
        client = OpenAI(api_key=settings.openai_api_key)
        client.models.list()
        return {
            "enabled": True,
            "label": "AI Enhanced Mode: ON",
            "reason": "OPENAI_API_KEY validated.",
        }
    except Exception as exc:
        return {
            "enabled": False,
            "label": "AI Enhanced Mode: OFF (fallback mode)",
            "reason": f"OpenAI validation failed: {exc}",
        }

