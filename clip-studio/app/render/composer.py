from __future__ import annotations

import csv
import json
import math
from pathlib import Path
import re
import shlex
import subprocess
import uuid
import zipfile

from PIL import Image, ImageDraw, ImageFont

from app.config.settings import settings
from app.storage import repository as repo


def run_ffmpeg(args: list[str]) -> None:
    proc = subprocess.run(
        args,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        check=False,
    )
    if proc.returncode != 0:
        raise RuntimeError(proc.stdout[-4000:])


def ass_escape(text: str) -> str:
    return text.replace("\\", "\\\\").replace("{", "\\{").replace("}", "\\}").replace("\n", " ")


def ff_escape(text: str) -> str:
    return text.replace("\\", "\\\\").replace(":", "\\:").replace("'", "\\'").replace("\n", " ")


def font(size: int, bold: bool = False) -> ImageFont.FreeTypeFont | ImageFont.ImageFont:
    candidates = [
        "/System/Library/Fonts/Supplemental/Arial Bold.ttf" if bold else "/System/Library/Fonts/Supplemental/Arial.ttf",
        "/System/Library/Fonts/Supplemental/Helvetica.ttc",
        "/Library/Fonts/Arial.ttf",
    ]
    for candidate in candidates:
        try:
            return ImageFont.truetype(candidate, size=size)
        except Exception:
            continue
    return ImageFont.load_default()


def wrap_text(draw: ImageDraw.ImageDraw, text: str, text_font, max_width: int) -> list[str]:
    words = text.split()
    lines: list[str] = []
    current: list[str] = []
    for word in words:
        trial = " ".join([*current, word])
        if draw.textbbox((0, 0), trial, font=text_font)[2] <= max_width or not current:
            current.append(word)
        else:
            lines.append(" ".join(current))
            current = [word]
    if current:
        lines.append(" ".join(current))
    return lines


def draw_centered_lines(
    draw: ImageDraw.ImageDraw,
    lines: list[str],
    y: int,
    text_font,
    fill: tuple[int, int, int, int],
    stroke_width: int = 0,
    stroke_fill: tuple[int, int, int, int] = (0, 0, 0, 255),
    line_gap: int = 16,
) -> int:
    for line in lines:
        bbox = draw.textbbox((0, 0), line, font=text_font, stroke_width=stroke_width)
        x = (1080 - (bbox[2] - bbox[0])) // 2
        draw.text((x, y), line, font=text_font, fill=fill, stroke_width=stroke_width, stroke_fill=stroke_fill)
        y += bbox[3] - bbox[1] + line_gap
    return y


def line_count_for_words(draw: ImageDraw.ImageDraw, words: list[str], text_font, max_width: int) -> int:
    if not words:
        return 0
    lines = 1
    current = ""
    for word in words:
        trial = word if not current else f"{current} {word}"
        if draw.textbbox((0, 0), trial, font=text_font, stroke_width=5)[2] <= max_width:
            current = trial
        else:
            lines += 1
            current = word
    return lines


def hex_to_rgb(value: str) -> tuple[int, int, int]:
    clean = value.strip().lstrip("#")
    return tuple(int(clean[i : i + 2], 16) for i in (0, 2, 4))


def clamp_float(value, default: float = 0.5) -> float:
    try:
        parsed = float(value)
    except (TypeError, ValueError):
        parsed = default
    return max(0.0, min(1.0, parsed))


def clamp_int(value, default: int = 0, minimum: int = -750, maximum: int = 750) -> int:
    try:
        parsed = int(value)
    except (TypeError, ValueError):
        parsed = default
    return max(minimum, min(maximum, parsed))


def reframe_filter(selection: dict) -> str:
    focus_x = clamp_float(selection.get("crop_focus_x"))
    focus_y = clamp_float(selection.get("crop_focus_y"))
    crop_x = f"min(max({focus_x:.4f}*iw-540\\,0)\\,iw-1080)"
    crop_y = f"min(max({focus_y:.4f}*ih-960\\,0)\\,ih-1920)"
    return (
        "[0:v]scale=1080:1920:force_original_aspect_ratio=increase,"
        f"crop=1080:1920:{crop_x}:{crop_y}[base];"
        "[base][1:v]overlay=0:0:format=auto[v]"
    )


def ass_time(seconds: float) -> str:
    cs = int(round(seconds * 100))
    h = cs // 360000
    cs %= 360000
    m = cs // 6000
    cs %= 6000
    s = cs // 100
    cs %= 100
    return f"{h}:{m:02d}:{s:02d}.{cs:02d}"


def subtitle_lines(tokens: list[dict], start: float, end: float) -> list[dict]:
    selected = [t for t in tokens if float(t["end_time"]) > start and float(t["start_time"]) < end]
    lines = []
    current: list[dict] = []
    for token in selected:
        current.append(token)
        text = " ".join(t["text"] for t in current)
        if len(text) > 34 or len(current) >= 7:
            lines.append({"tokens": current})
            current = []
    if current:
        lines.append({"tokens": current})
    return lines


def write_ass(path: Path, tokens: list[dict], start: float, end: float) -> None:
    lines = [
        "[Script Info]",
        "ScriptType: v4.00+",
        "PlayResX: 1080",
        "PlayResY: 1920",
        "",
        "[V4+ Styles]",
        "Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding",
        "Style: Default,Arial,78,&H00FFFFFF,&H0036D978,&H00101818,&H99000000,-1,0,0,0,100,100,0,0,1,6,2,2,80,80,260,1",
        "",
        "[Events]",
        "Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text",
    ]
    for group in subtitle_lines(tokens, start, end):
        group_tokens = group["tokens"]
        group_start = max(float(group_tokens[0]["start_time"]), start) - start
        group_end = min(float(group_tokens[-1]["end_time"]), end) - start
        for i, active in enumerate(group_tokens):
            event_start = max(float(active["start_time"]), start) - start
            event_end = min(float(active["end_time"]), end) - start
            if event_end <= event_start:
                continue
            rendered = []
            for j, token in enumerate(group_tokens):
                word = ass_escape(token["text"].strip())
                if i == j:
                    rendered.append(r"{\c&H78D936&\3c&H102018&}" + word + r"{\c&HFFFFFF&}")
                else:
                    rendered.append(word)
            text = " ".join(rendered)
            lines.append(
                f"Dialogue: 0,{ass_time(event_start)},{ass_time(event_end)},Default,,0,0,0,,{text}"
            )
        if not group_tokens:
            continue
        if group_end > group_start and not any(float(t["start_time"]) >= start for t in group_tokens):
            text = ass_escape(" ".join(t["text"] for t in group_tokens))
            lines.append(f"Dialogue: 0,{ass_time(group_start)},{ass_time(group_end)},Default,,0,0,0,,{text}")
    path.write_text("\n".join(lines), encoding="utf-8")


def title_from_selection(selection: dict) -> str:
    if selection.get("_title"):
        return selection["_title"]
    if selection.get("title"):
        return selection["title"]
    text = selection.get("text_excerpt") or "Khutbah Insight"
    words = re.findall(r"[A-Za-z']+", text)
    meaningful = [w for w in words if len(w) > 3][:6]
    return " ".join(meaningful).title() or "Khutbah Insight"


def card_png(path: Path, title: str, subtitle: str, outro: bool = False) -> Path:
    bg = hex_to_rgb(settings.brand_primary if not outro else "#0F2F25")
    accent = hex_to_rgb(settings.brand_accent)
    image = Image.new("RGB", (1080, 1920), bg)
    draw = ImageDraw.Draw(image)
    title_font = font(58 if outro else 76, bold=True)
    subtitle_font = font(40 if outro else 42, bold=False)
    brand_font = font(46, bold=True)
    watermark_font = font(34, bold=True)
    if outro and settings.brand_logo_path.exists():
        logo = Image.open(settings.brand_logo_path).convert("RGBA")
        logo.thumbnail((210, 210))
        logo_bg = Image.new("RGBA", (250, 250), (255, 255, 255, 238))
        logo_bg.alpha_composite(logo, ((250 - logo.width) // 2, (250 - logo.height) // 2))
        image.paste(logo_bg.convert("RGB"), ((1080 - 250) // 2, 230))
        draw_centered_lines(draw, [settings.brand_name], 525, brand_font, (*accent, 255))
        title_y = 690
        subtitle_y = 1135
    else:
        draw_centered_lines(draw, [settings.brand_name], 290, brand_font, (*accent, 255))
        title_y = None
        subtitle_y = 1080
    title_lines = wrap_text(draw, title, title_font, 880)
    title_height = len(title_lines) * 92
    draw_centered_lines(
        draw,
        title_lines,
        title_y if title_y is not None else int((1920 - title_height) / 2 - 90),
        title_font,
        (255, 255, 255, 255),
        stroke_width=2,
        stroke_fill=(0, 0, 0, 160),
        line_gap=18,
    )
    subtitle_lines_wrapped = wrap_text(draw, subtitle, subtitle_font, 880)
    draw_centered_lines(draw, subtitle_lines_wrapped, subtitle_y, subtitle_font, (250, 248, 240, 255), line_gap=14)
    draw_centered_lines(draw, [settings.brand_watermark], 1700, watermark_font, (255, 255, 255, 150))
    png = path.with_suffix(".png")
    image.save(png)
    return png


def create_card(path: Path, title: str, subtitle: str, duration: float, outro: bool = False) -> None:
    png = card_png(path, title, subtitle, outro=outro)
    run_ffmpeg(
        [
            "ffmpeg",
            "-y",
            "-loop",
            "1",
            "-t",
            str(duration),
            "-i",
            str(png),
            "-f",
            "lavfi",
            "-i",
            "anullsrc=channel_layout=stereo:sample_rate=48000",
            "-t",
            str(duration),
            "-c:v",
            "libx264",
            "-pix_fmt",
            "yuv420p",
            "-c:a",
            "aac",
            "-shortest",
            str(path),
        ]
    )


def build_subtitle_blocks(tokens: list[dict], window_start: float, window_end: float) -> list[dict]:
    selected = [t for t in tokens if float(t["end_time"]) > window_start and float(t["start_time"]) < window_end]
    if not selected:
        return []
    measure = Image.new("RGBA", (1080, 1920), (0, 0, 0, 0))
    draw = ImageDraw.Draw(measure)
    subtitle_font = font(74, bold=True)
    blocks: list[dict] = []
    current: list[dict] = []
    for token in selected:
        trial = [*current, token]
        words = [t["text"].strip() for t in trial if t["text"].strip()]
        duration = float(trial[-1]["end_time"]) - float(trial[0]["start_time"])
        too_many_lines = line_count_for_words(draw, words, subtitle_font, 900) > 2
        too_many_words = len(words) > 10
        natural_break = bool(current) and current[-1]["text"].strip().endswith((".", "?", "!")) and duration > 1.8
        if current and (too_many_lines or too_many_words or natural_break):
            blocks.append({"tokens": current})
            current = [token]
        else:
            current = trial
    if current:
        blocks.append({"tokens": current})
    for index, block in enumerate(blocks):
        block["start_time"] = max(float(block["tokens"][0]["start_time"]), window_start)
        natural_end = min(float(block["tokens"][-1]["end_time"]), window_end)
        next_start = (
            max(float(blocks[index + 1]["tokens"][0]["start_time"]), window_start)
            if index + 1 < len(blocks)
            else window_end
        )
        block["end_time"] = min(max(natural_end, next_start), window_end)
    return blocks


def subtitle_text_for_time(blocks: list[dict], absolute_time: float) -> tuple[list[dict], int] | None:
    if not blocks:
        return None
    block = None
    for candidate in blocks:
        if float(candidate["start_time"]) <= absolute_time < float(candidate["end_time"]):
            block = candidate
            break
    if block is None:
        if absolute_time < float(blocks[0]["start_time"]):
            block = blocks[0]
        else:
            block = blocks[-1]
    line_tokens = block["tokens"]
    active_index = 0
    for i, token in enumerate(line_tokens):
        if float(token["start_time"]) <= absolute_time <= float(token["end_time"]):
            active_index = i
            break
        if float(token["start_time"]) <= absolute_time:
            active_index = i
    return line_tokens, active_index


def subtitle_preview_blocks(tokens: list[dict], start: float, end: float) -> list[dict]:
    blocks = []
    for block in build_subtitle_blocks(tokens, start, end):
        blocks.append(
            {
                "start_time": float(block["start_time"]),
                "end_time": float(block["end_time"]),
                "tokens": [
                    {
                        "text": str(token["text"]).strip(),
                        "start_time": float(token["start_time"]),
                        "end_time": float(token["end_time"]),
                    }
                    for token in block["tokens"]
                    if str(token["text"]).strip()
                ],
            }
        )
    return blocks


def adjusted_subtitle_time(absolute_time: float, subtitle_offset_ms: int = 0) -> float:
    return absolute_time - clamp_int(subtitle_offset_ms) / 1000


def draw_subtitle_overlay(path: Path, line_tokens: list[dict], active_index: int) -> None:
    image = Image.new("RGBA", (1080, 1920), (0, 0, 0, 0))
    draw = ImageDraw.Draw(image)
    subtitle_font = font(74, bold=True)
    y = 1370
    words = [t["text"].strip() for t in line_tokens]
    lines: list[list[tuple[str, bool]]] = []
    current: list[tuple[str, bool]] = []
    for i, word in enumerate(words):
        trial = " ".join([w for w, _ in [*current, (word, i == active_index)]])
        if draw.textbbox((0, 0), trial, font=subtitle_font, stroke_width=5)[2] <= 900 or not current:
            current.append((word, i == active_index))
        else:
            lines.append(current)
            current = [(word, i == active_index)]
    if current:
        lines.append(current)
    for line in lines[:2]:
        widths = [draw.textbbox((0, 0), word, font=subtitle_font, stroke_width=5)[2] for word, _ in line]
        space = draw.textlength(" ", font=subtitle_font)
        total = sum(widths) + space * (len(line) - 1)
        x = (1080 - total) / 2
        for (word, active), width in zip(line, widths):
            fill = hex_to_rgb(settings.brand_accent) + (255,) if active else (255, 255, 255, 255)
            draw.text(
                (x, y),
                word,
                font=subtitle_font,
                fill=fill,
                stroke_width=6,
                stroke_fill=(10, 18, 16, 235),
            )
            x += width + space
        y += 92
    # Watermark
    wm_font = font(30, bold=True)
    text = settings.brand_watermark
    bbox = draw.textbbox((0, 0), text, font=wm_font)
    draw.text((1080 - (bbox[2] - bbox[0]) - 56, 56), text, font=wm_font, fill=(255, 255, 255, 120))
    path.parent.mkdir(parents=True, exist_ok=True)
    image.save(path)


def render_overlay_sequence(
    tokens: list[dict],
    start: float,
    end: float,
    output_dir: Path,
    fps: int = 10,
    subtitle_offset_ms: int = 0,
) -> Path:
    frames_dir = output_dir / "subtitle_frames"
    frames_dir.mkdir(parents=True, exist_ok=True)
    frame_count = max(1, math.ceil((end - start) * fps))
    blocks = build_subtitle_blocks(tokens, start, end)
    for frame in range(frame_count):
        t = adjusted_subtitle_time(start + frame / fps, subtitle_offset_ms)
        target = frames_dir / f"frame_{frame:05d}.png"
        payload = subtitle_text_for_time(blocks, t)
        if payload:
            draw_subtitle_overlay(target, payload[0], payload[1])
        else:
            Image.new("RGBA", (1080, 1920), (0, 0, 0, 0)).save(target)
    return frames_dir


def render_selection(job: dict, selection: dict, tokens: list[dict], output_dir: Path, index: int) -> dict:
    source = Path(job["source_video_path"])
    start = float(selection["start_time"])
    end = float(selection["end_time"])
    duration = max(0.1, end - start)
    stem = f"clip_{index:02d}_{selection['id']}"
    intro = output_dir / f"{stem}_intro.mp4"
    main = output_dir / f"{stem}_main.mp4"
    outro = output_dir / f"{stem}_outro.mp4"
    concat_file = output_dir / f"{stem}_concat.txt"
    final = output_dir / f"{stem}.mp4"
    thumb = output_dir / f"{stem}.jpg"

    title = title_from_selection(selection)
    intro_title = selection.get("intro_title") or f"Khutbah Insight: {title}"
    intro_subtitle = selection.get("intro_subtitle") or f"{job.get('speaker_name') or 'Khutbah'} - {job.get('masjid_name') or settings.brand_name}"
    outro_title = selection.get("outro_title") or "See this khutbah + summaries, key points, and Quranic references"
    outro_subtitle = selection.get("outro_subtitle") or "Khutbah Notes app - Available on iOS"
    create_card(intro, intro_title, intro_subtitle, settings.intro_seconds)
    create_card(
        outro,
        outro_title,
        outro_subtitle,
        settings.outro_seconds,
        outro=True,
    )
    subtitle_offset_ms = clamp_int(selection.get("subtitle_offset_ms"))
    frames_dir = render_overlay_sequence(tokens, start, end, output_dir / stem, subtitle_offset_ms=subtitle_offset_ms)
    vf = reframe_filter(selection)
    run_ffmpeg(
        [
            "ffmpeg",
            "-y",
            "-ss",
            str(start),
            "-t",
            str(duration),
            "-i",
            str(source),
            "-framerate",
            "10",
            "-i",
            str(frames_dir / "frame_%05d.png"),
            "-filter_complex",
            vf,
            "-map",
            "[v]",
            "-map",
            "0:a?",
            "-c:v",
            "libx264",
            "-preset",
            "veryfast",
            "-crf",
            "20",
            "-pix_fmt",
            "yuv420p",
            "-c:a",
            "aac",
            "-ar",
            "48000",
            "-ac",
            "2",
            str(main),
        ]
    )
    run_ffmpeg(
        [
            "ffmpeg",
            "-y",
            "-i",
            str(intro),
            "-i",
            str(main),
            "-i",
            str(outro),
            "-filter_complex",
            (
                "[0:v]fps=30,setsar=1[v0];[1:v]fps=30,setsar=1[v1];"
                "[2:v]fps=30,setsar=1[v2];"
                "[0:a]aformat=sample_rates=48000:channel_layouts=stereo[a0];"
                "[1:a]aformat=sample_rates=48000:channel_layouts=stereo[a1];"
                "[2:a]aformat=sample_rates=48000:channel_layouts=stereo[a2];"
                "[v0][a0][v1][a1][v2][a2]concat=n=3:v=1:a=1[v][a]"
            ),
            "-map",
            "[v]",
            "-map",
            "[a]",
            "-c:v",
            "libx264",
            "-preset",
            "veryfast",
            "-crf",
            "20",
            "-pix_fmt",
            "yuv420p",
            "-c:a",
            "aac",
            "-ar",
            "48000",
            "-ac",
            "2",
            str(final),
        ]
    )
    run_ffmpeg(
        [
            "ffmpeg",
            "-y",
            "-ss",
            "1",
            "-i",
            str(final),
            "-frames:v",
            "1",
            "-q:v",
            "2",
            str(thumb),
        ]
    )
    metadata = {
        "selection_id": selection["id"],
        "title": title,
        "start_time": start,
        "end_time": end,
        "duration": duration,
        "crop_focus_x": clamp_float(selection.get("crop_focus_x")),
        "crop_focus_y": clamp_float(selection.get("crop_focus_y")),
        "subtitle_offset_ms": subtitle_offset_ms,
        "mp4": str(final),
        "thumbnail": str(thumb),
    }
    (output_dir / f"{stem}.json").write_text(json.dumps(metadata, indent=2), encoding="utf-8")
    return metadata


def render_subtitle_preview(
    job: dict,
    selection: dict,
    tokens: list[dict],
    output_dir: Path,
    preview_start: float | None = None,
    preview_duration: float = 8.0,
) -> dict:
    source = Path(job["source_video_path"])
    selection_start = float(selection["start_time"])
    selection_end = float(selection["end_time"])
    start = preview_start if preview_start is not None else selection_start
    start = max(selection_start, min(float(start), max(selection_start, selection_end - 0.25)))
    end = min(selection_end, start + max(1.0, min(float(preview_duration), 15.0)))
    duration = max(0.25, end - start)
    stem = f"preview_{selection['id']}_{uuid.uuid4().hex[:8]}"
    output_dir.mkdir(parents=True, exist_ok=True)
    final = output_dir / f"{stem}.mp4"
    subtitle_offset_ms = clamp_int(selection.get("subtitle_offset_ms"))
    frames_dir = render_overlay_sequence(tokens, start, end, output_dir / stem, subtitle_offset_ms=subtitle_offset_ms)
    run_ffmpeg(
        [
            "ffmpeg",
            "-y",
            "-ss",
            str(start),
            "-t",
            str(duration),
            "-i",
            str(source),
            "-framerate",
            "10",
            "-i",
            str(frames_dir / "frame_%05d.png"),
            "-filter_complex",
            reframe_filter(selection),
            "-map",
            "[v]",
            "-map",
            "0:a?",
            "-c:v",
            "libx264",
            "-preset",
            "veryfast",
            "-crf",
            "20",
            "-pix_fmt",
            "yuv420p",
            "-c:a",
            "aac",
            "-ar",
            "48000",
            "-ac",
            "2",
            str(final),
        ]
    )
    return {
        "selection_id": selection["id"],
        "start_time": start,
        "end_time": end,
        "duration": duration,
        "subtitle_offset_ms": subtitle_offset_ms,
        "mp4": str(final),
    }


def render_job(job_id: str) -> list[dict]:
    repo.validate_render_allowed(job_id)
    job = repo.get_job(job_id)
    transcript = repo.get_transcript(job_id)
    selections = [s for s in repo.get_selections(job_id) if s["status"] == "approved"]
    candidate_titles = {c["id"]: c["title"] for c in repo.get_candidates(job_id)}
    output_dir = settings.outputs_dir / job_id
    output_dir.mkdir(parents=True, exist_ok=True)
    rendered = []
    for index, selection in enumerate(selections, start=1):
        if selection.get("candidate_id") in candidate_titles:
            selection["_title"] = candidate_titles[selection["candidate_id"]]
        output = repo.create_output(job_id, selection["id"], "mp4", output_dir / f"pending_{index}.mp4", "rendering")
        try:
            metadata = render_selection(job, selection, transcript["tokens"], output_dir, index)
            repo.update_output(output["id"], path=metadata["mp4"], status="complete", render_payload=json.dumps(metadata))
            repo.create_output(job_id, selection["id"], "thumbnail", Path(metadata["thumbnail"]), "complete", metadata)
            rendered.append(metadata)
        except Exception as exc:
            repo.update_output(output["id"], status="failed", error_message=str(exc))
            raise

    json_path = output_dir / "metadata.json"
    csv_path = output_dir / "metadata.csv"
    zip_path = output_dir / "khutbah_clips_bundle.zip"
    json_path.write_text(json.dumps(rendered, indent=2), encoding="utf-8")
    with csv_path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(
            handle,
            fieldnames=[
                "selection_id",
                "title",
                "start_time",
                "end_time",
                "duration",
                "crop_focus_x",
                "crop_focus_y",
                "subtitle_offset_ms",
                "mp4",
                "thumbnail",
            ],
        )
        writer.writeheader()
        writer.writerows(rendered)
    with zipfile.ZipFile(zip_path, "w", compression=zipfile.ZIP_DEFLATED) as bundle:
        for item in rendered:
            bundle.write(item["mp4"], arcname=Path(item["mp4"]).name)
            bundle.write(item["thumbnail"], arcname=Path(item["thumbnail"]).name)
        bundle.write(json_path, arcname="metadata.json")
        bundle.write(csv_path, arcname="metadata.csv")
    repo.create_output(job_id, None, "metadata_json", json_path, "complete", {"count": len(rendered)})
    repo.create_output(job_id, None, "metadata_csv", csv_path, "complete", {"count": len(rendered)})
    repo.create_output(job_id, None, "zip", zip_path, "complete", {"count": len(rendered)})
    return rendered
