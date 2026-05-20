from __future__ import annotations

from pathlib import Path
import re
import subprocess


YOUTUBE_ID_RE = re.compile(r"(?:v=|youtu\.be/|shorts/|live/|embed/)([A-Za-z0-9_-]{11})")


def extract_video_id(url: str) -> str | None:
    clean = url.strip()
    if re.fullmatch(r"[A-Za-z0-9_-]{11}", clean):
        return clean
    match = YOUTUBE_ID_RE.search(clean)
    return match.group(1) if match else None


def run_command(args: list[str], cwd: Path | None = None) -> str:
    proc = subprocess.run(
        args,
        cwd=cwd,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        check=False,
    )
    if proc.returncode != 0:
        raise RuntimeError(proc.stdout.strip() or f"Command failed: {' '.join(args)}")
    return proc.stdout.strip()


def download_video(url: str, job_dir: Path) -> dict:
    job_dir.mkdir(parents=True, exist_ok=True)
    output_template = str(job_dir / "source.%(ext)s")
    video_log = run_command(
        [
            "yt-dlp",
            "--no-playlist",
            "--write-info-json",
            "-f",
            "bv*[height<=1080]+ba/b[height<=1080]/b",
            "--merge-output-format",
            "mp4",
            "-o",
            output_template,
            url,
        ]
    )
    caption_log = ""
    try:
        caption_log = run_command(
            [
                "yt-dlp",
                "--no-playlist",
                "--skip-download",
                "--write-auto-subs",
                "--write-subs",
                "--sub-lang",
                "en,en-US,en-orig",
                "--sub-format",
                "vtt",
                "-o",
                output_template,
                url,
            ]
        )
    except RuntimeError as exc:
        caption_log = f"Caption download skipped; local Whisper will be used if no captions were saved. {exc}"
    video = next(job_dir.glob("source.mp4"), None)
    if not video:
        candidates = sorted(job_dir.glob("source.*"))
        video = next((p for p in candidates if p.suffix.lower() in {".mp4", ".mkv", ".webm"}), None)
    if not video:
        raise RuntimeError("yt-dlp completed but no source video was found.")
    audio = job_dir / "source.wav"
    run_command(
        [
            "ffmpeg",
            "-y",
            "-i",
            str(video),
            "-vn",
            "-ac",
            "1",
            "-ar",
            "16000",
            str(audio),
        ]
    )
    return {
        "video_path": video,
        "audio_path": audio,
        "log": "\n".join(part for part in [video_log, caption_log] if part),
    }
