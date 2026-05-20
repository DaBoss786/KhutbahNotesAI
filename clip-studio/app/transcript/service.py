from __future__ import annotations

from pathlib import Path
import html
import re

from app.config.settings import settings


def _words_from_text(text: str, start: float, end: float, segment_index: int) -> list[dict]:
    words = re.findall(r"\S+", text)
    if not words:
        return []
    duration = max(0.01, end - start)
    step = duration / len(words)
    return [
        {
            "text": word,
            "start_time": start + i * step,
            "end_time": start + (i + 1) * step,
            "segment_index": segment_index,
        }
        for i, word in enumerate(words)
    ]


def collapse_repeated_caption_text(text: str) -> str:
    """Remove YouTube VTT repeated cue fragments while preserving word order."""
    words = text.split()
    if len(words) < 4:
        return text
    cleaned: list[str] = []
    i = 0
    while i < len(words):
        max_span = min(14, (len(words) - i) // 2)
        repeated_span = 0
        for span in range(max_span, 0, -1):
            first = [w.lower().strip(".,?!;:") for w in words[i : i + span]]
            second = [w.lower().strip(".,?!;:") for w in words[i + span : i + span * 2]]
            if first == second:
                repeated_span = span
                break
        if repeated_span:
            cleaned.extend(words[i : i + repeated_span])
            i += repeated_span
            while i + repeated_span <= len(words):
                prev = [w.lower().strip(".,?!;:") for w in cleaned[-repeated_span:]]
                current = [w.lower().strip(".,?!;:") for w in words[i : i + repeated_span]]
                if current != prev:
                    break
                i += repeated_span
            continue
        if cleaned and words[i].lower().strip(".,?!;:") == cleaned[-1].lower().strip(".,?!;:"):
            i += 1
            continue
        cleaned.append(words[i])
        i += 1
    return " ".join(cleaned)


def remove_prefix_overlap(previous: str, current: str) -> str:
    prev_words = previous.split()
    current_words = current.split()
    max_span = min(len(prev_words), len(current_words), 18)
    for span in range(max_span, 0, -1):
        prev = [w.lower().strip(".,?!;:") for w in prev_words[-span:]]
        cur = [w.lower().strip(".,?!;:") for w in current_words[:span]]
        if prev == cur:
            return " ".join(current_words[span:]).strip()
    return current


def parse_vtt(path: Path) -> tuple[list[dict], list[dict]]:
    segments: list[dict] = []
    tokens: list[dict] = []
    content = path.read_text(encoding="utf-8", errors="ignore")
    blocks = re.split(r"\n\s*\n", content)
    ts_re = re.compile(
        r"(?P<s>\d\d:\d\d:\d\d\.\d{3})\s+-->\s+(?P<e>\d\d:\d\d:\d\d\.\d{3})"
    )
    for block in blocks:
        match = ts_re.search(block)
        if not match:
            continue
        start = parse_ts(match.group("s"))
        end = parse_ts(match.group("e"))
        if end - start < 0.08:
            continue
        raw_lines = [line.strip() for line in block.splitlines() if line.strip() and "-->" not in line and not line.strip().isdigit()]
        timed_lines = [line for line in raw_lines if re.search(r"<\d\d:\d\d:\d\d\.\d{3}>", line)]
        if timed_lines:
            raw_lines = timed_lines
        lines: list[str] = []
        for line in raw_lines:
            stripped = re.sub(r"<[^>]+>", "", line).strip()
            if not stripped:
                continue
            if lines and stripped == lines[-1]:
                continue
            lines.append(stripped)
        text = re.sub(r"<[^>]+>", "", " ".join(lines))
        text = html.unescape(re.sub(r"\s+", " ", text)).strip()
        text = collapse_repeated_caption_text(text)
        if segments:
            text = remove_prefix_overlap(segments[-1]["text"], text)
        if not text:
            continue
        idx = len(segments)
        segments.append({"start_time": start, "end_time": end, "text": text})
        tokens.extend(_words_from_text(text, start, end, idx))
    return segments, tokens


def parse_ts(value: str) -> float:
    hh, mm, rest = value.split(":")
    ss, ms = rest.split(".")
    return int(hh) * 3600 + int(mm) * 60 + int(ss) + int(ms) / 1000


def find_caption(job_dir: Path) -> Path | None:
    captions = sorted(job_dir.glob("*.vtt"))
    return captions[0] if captions else None


def transcribe_audio(audio_path: Path) -> tuple[list[dict], list[dict]]:
    try:
        from faster_whisper import WhisperModel
    except Exception as exc:
        raise RuntimeError(
            "No captions were available and faster-whisper is not installed. "
            "Run ./scripts/start.sh to install dependencies."
        ) from exc

    model = WhisperModel(settings.whisper_model, device="cpu", compute_type="int8")
    raw_segments, _ = model.transcribe(
        str(audio_path),
        word_timestamps=True,
        vad_filter=True,
        beam_size=5,
    )
    segments: list[dict] = []
    tokens: list[dict] = []
    for seg in raw_segments:
        idx = len(segments)
        text = (seg.text or "").strip()
        if not text:
            continue
        segments.append(
            {
                "start_time": float(seg.start),
                "end_time": float(seg.end),
                "text": text,
            }
        )
        words = getattr(seg, "words", None) or []
        if words:
            for word in words:
                tokens.append(
                    {
                        "start_time": float(word.start),
                        "end_time": float(word.end),
                        "text": word.word.strip(),
                        "segment_index": idx,
                    }
                )
        else:
            tokens.extend(_words_from_text(text, float(seg.start), float(seg.end), idx))
    return segments, tokens


def get_or_create_transcript(job_dir: Path, audio_path: Path) -> tuple[list[dict], list[dict], str]:
    caption = find_caption(job_dir)
    if caption:
        segments, tokens = parse_vtt(caption)
        if segments:
            return segments, tokens, f"youtube_caption:{caption.name}"
    segments, tokens = transcribe_audio(audio_path)
    return segments, tokens, "local_whisper"
