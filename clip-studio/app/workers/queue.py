from __future__ import annotations

from collections import Counter
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
import traceback

from app.config.settings import settings
from app.ingest.youtube import download_video, extract_video_id
from app.render.composer import render_job
from app.selection.candidates import generate_candidates
from app.storage.cleanup import cleanup_jobs_folder
from app.storage import repository as repo
from app.transcript.service import get_or_create_transcript, transcribe_audio


executor = ThreadPoolExecutor(max_workers=2)


def submit_ingest(job_id: str) -> None:
    executor.submit(run_ingest_and_candidates, job_id)


def submit_render(job_id: str) -> None:
    executor.submit(run_render, job_id)


def submit_retime(job_id: str) -> None:
    executor.submit(run_retime, job_id)


def run_ingest_and_candidates(job_id: str) -> None:
    try:
        job = repo.get_job(job_id)
        job_dir = settings.jobs_dir / job_id
        repo.update_job(job_id, status="running", stage="ingest")
        repo.add_log(job_id, "Downloading YouTube media with yt-dlp.")
        video_id = extract_video_id(job["youtube_url"]) or ""
        media = download_video(job["youtube_url"], job_dir)
        repo.update_job(
            job_id,
            video_id=video_id,
            source_video_path=str(media["video_path"]),
            source_audio_path=str(media["audio_path"]),
            stage="transcript",
        )
        repo.add_log(job_id, "Creating transcript and word timings.")
        segments, tokens, transcript_metadata = get_or_create_transcript(job_dir, Path(media["audio_path"]))
        repo.replace_transcript(job_id, segments, tokens, transcript_metadata)
        repo.add_log(
            job_id,
            "Transcript ready from "
            f"{transcript_metadata['transcript_source']} "
            f"({transcript_metadata['timing_source']}): "
            f"{len(segments)} segments, {len(tokens)} tokens.",
        )
        repo.update_job(job_id, stage="candidates")
        repo.add_log(job_id, "Generating review candidates.")
        reference_text = " ".join(str(segment.get("text") or "") for segment in segments)
        learning_context = repo.learning_examples_for_prompt(reference_text)
        if learning_context["stats"]["total"]:
            repo.add_log(
                job_id,
                "Using caption learning examples: "
                f"{len(learning_context['positive_examples'])} selected, "
                f"{len(learning_context['negative_examples'])} rejected.",
            )
        candidates = generate_candidates(
            segments,
            int(job["requested_clip_count"]),
            float(job["min_duration"]),
            float(job["max_duration"]),
            learning_context,
        )
        repo.replace_candidates(job_id, candidates)
        if candidates:
            source_counts = Counter(candidate.get("source", "unknown") for candidate in candidates)
            if source_counts.get("openai"):
                repo.add_log(job_id, f"Generated {len(candidates)} OpenAI-ranked candidates for review.")
            elif settings.openai_api_key:
                repo.add_log(job_id, f"Generated {len(candidates)} fallback candidates for review after AI enhancement returned no usable candidates.", level="warn")
            else:
                repo.add_log(job_id, f"Generated {len(candidates)} fallback candidates for review.")
        else:
            repo.add_log(job_id, "No strong candidates found. Empty is preferred over weak clips.", level="warn")
        repo.update_job(job_id, status="review", stage="review")
        cleanup_jobs_folder()
    except Exception as exc:
        repo.update_job(job_id, status="failed", stage="failed", error_message=str(exc))
        repo.add_log(job_id, f"{exc}\n{traceback.format_exc()}", level="error")
        cleanup_jobs_folder()


def run_retime(job_id: str) -> None:
    try:
        job = repo.get_job(job_id)
        audio_path = job.get("source_audio_path")
        if not audio_path or not Path(audio_path).exists():
            raise RuntimeError("Source audio is not available yet.")
        repo.update_job(job_id, status="retiming", stage="transcript")
        repo.add_log(job_id, "Improving transcript timing with local Whisper word timestamps.")
        segments, tokens, metadata = transcribe_audio(Path(audio_path))
        metadata = {**metadata, "transcript_source": "local_whisper_retime"}
        repo.replace_transcript(job_id, segments, tokens, metadata)
        repo.unlock_job(job_id, reason="Transcript timing changed after lock.")
        repo.update_job(job_id, status="review", stage="review")
        repo.add_log(
            job_id,
            f"Transcript timing improved from {metadata['transcript_source']} "
            f"({metadata['timing_source']}): {len(segments)} segments, {len(tokens)} tokens.",
        )
        cleanup_jobs_folder()
    except Exception as exc:
        repo.update_job(job_id, status="retime_failed", stage="review", error_message=str(exc))
        repo.add_log(job_id, f"Timing repair failed: {exc}\n{traceback.format_exc()}", level="error")
        cleanup_jobs_folder()


def run_render(job_id: str) -> None:
    try:
        repo.validate_render_allowed(job_id)
        repo.update_job(job_id, status="rendering", stage="render")
        repo.add_log(job_id, "Rendering locked approved selections.")
        rendered = render_job(job_id)
        learned = repo.sync_learning_examples_for_job(job_id)
        repo.update_job(job_id, status="complete", stage="complete")
        repo.add_log(job_id, f"Render complete: {len(rendered)} clips.")
        repo.add_log(job_id, f"Learning examples updated: {learned['positive']} selected, {learned['negative']} rejected.")
        cleanup_jobs_folder()
    except Exception as exc:
        repo.update_job(job_id, status="render_failed", stage="render", error_message=str(exc))
        repo.add_log(job_id, f"Render failed: {exc}\n{traceback.format_exc()}", level="error")
        cleanup_jobs_folder()
