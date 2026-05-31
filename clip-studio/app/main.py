from __future__ import annotations

from pathlib import Path

from fastapi import FastAPI, HTTPException, Request
from fastapi.responses import FileResponse, HTMLResponse, JSONResponse, RedirectResponse
from fastapi.staticfiles import StaticFiles
from fastapi.templating import Jinja2Templates

from app.api.schemas import ApprovalUpdate, JobCreate, LockRequest, SelectionCreate, SelectionPatch, SubtitlePreviewRenderRequest
from app.config.settings import settings
from app.render.composer import render_subtitle_preview, subtitle_preview_blocks
from app.storage.db import init_db
from app.storage.cleanup import cleanup_jobs_folder
from app.storage import repository as repo
from app.system import ai_status, dependency_status
from app.workers.queue import submit_ingest, submit_render, submit_retime


settings.ensure_dirs()
init_db()
cleanup_jobs_folder()

app = FastAPI(title="Khutbah Clip Studio")
app.mount("/static", StaticFiles(directory=settings.root / "app" / "static"), name="static")
templates = Jinja2Templates(directory=settings.root / "app" / "templates")


def static_version() -> str:
    static_dir = settings.root / "app" / "static"
    mtimes = [path.stat().st_mtime_ns for path in static_dir.glob("*") if path.is_file()]
    return str(max(mtimes) if mtimes else 0)


def timing_label(source: str | None, quality: str | None = None) -> str:
    labels = {
        "youtube_word": "YouTube word timings",
        "whisper_word": "Whisper word timings",
        "estimated": "Estimated timings",
        "unknown": "Timing source unknown",
        "": "Timing source unknown",
    }
    label = labels.get(source or "", source or "Timing source unknown")
    return f"{label} ({quality})" if quality and quality not in {"word", "estimated", "unknown"} else label


def page_context(request: Request, **extra):
    return {
        "request": request,
        "ai": ai_status(validate=False),
        "deps": dependency_status(),
        "learning": repo.learning_stats(),
        "static_version": static_version(),
        "timing_label": timing_label,
        **extra,
    }


@app.get("/", response_class=HTMLResponse)
def index(request: Request):
    return templates.TemplateResponse(
        "new_job.html",
        page_context(
            request,
            defaults={
                "clip_count": settings.default_clip_count,
                "min_duration": settings.default_min_duration,
                "max_duration": settings.default_max_duration,
            },
        ),
    )


@app.get("/jobs/{job_id}", response_class=HTMLResponse)
def job_page(request: Request, job_id: str):
    try:
        job = repo.get_job(job_id)
    except KeyError:
        raise HTTPException(status_code=404, detail="Job not found")
    return templates.TemplateResponse(
        "job.html",
        page_context(
            request,
            job=job,
            logs=repo.logs_for_job(job_id),
            candidates=repo.get_candidates(job_id),
            selections=repo.get_selections(job_id),
            transcript=repo.get_transcript(job_id),
            outputs=repo.get_outputs(job_id),
        ),
    )


@app.get("/history", response_class=HTMLResponse)
def history(request: Request):
    return templates.TemplateResponse("history.html", page_context(request, jobs=repo.list_jobs()))


@app.post("/api/jobs")
def create_job(payload: JobCreate):
    if payload.max_duration < payload.min_duration:
        raise HTTPException(status_code=400, detail="Max duration must be greater than min duration.")
    job = repo.create_job(
        {
            "youtube_url": payload.youtube_url,
            "speaker_name": payload.speaker_name,
            "masjid_name": payload.masjid_name,
            "clip_count": payload.clip_count,
            "min_duration": payload.min_duration,
            "max_duration": payload.max_duration,
            "branding": {"profile": payload.branding_profile},
            "ai_mode": "on" if ai_status()["enabled"] else "fallback",
        }
    )
    submit_ingest(job["id"])
    return job


@app.get("/api/jobs/{job_id}")
def get_job(job_id: str):
    try:
        return {
            "job": repo.get_job(job_id),
            "logs": repo.logs_for_job(job_id),
            "selections": repo.get_selections(job_id),
            "outputs": repo.get_outputs(job_id),
        }
    except KeyError:
        raise HTTPException(status_code=404, detail="Job not found")


@app.get("/api/jobs/{job_id}/candidates")
def get_candidates(job_id: str):
    return {"candidates": repo.get_candidates(job_id)}


@app.post("/api/jobs/{job_id}/approvals")
def approvals(job_id: str, payload: ApprovalUpdate):
    repo.set_candidate_approvals(job_id, payload.approvals)
    return {"candidates": repo.get_candidates(job_id), "selections": repo.get_selections(job_id), "job": repo.get_job(job_id)}


@app.get("/api/jobs/{job_id}/transcript")
def transcript(job_id: str):
    return repo.get_transcript(job_id)


@app.get("/api/jobs/{job_id}/selections/{selection_id}/subtitle-preview")
def subtitle_preview(job_id: str, selection_id: str):
    try:
        selection = repo.get_selection(job_id, selection_id)
    except KeyError:
        raise HTTPException(status_code=404, detail="Selection not found")
    transcript = repo.get_transcript(job_id)
    start = float(selection["start_time"])
    end = float(selection["end_time"])
    metadata = transcript.get("metadata", {})
    return {
        "selection_id": selection_id,
        "start_time": start,
        "end_time": end,
        "subtitle_offset_ms": int(selection.get("subtitle_offset_ms") or 0),
        "timing_source": metadata.get("timing_source") or "unknown",
        "timing_quality": metadata.get("timing_quality") or "unknown",
        "blocks": subtitle_preview_blocks(transcript["tokens"], start, end),
    }


@app.post("/api/jobs/{job_id}/selections/{selection_id}/subtitle-preview-render")
def subtitle_preview_render(job_id: str, selection_id: str, payload: SubtitlePreviewRenderRequest):
    try:
        job = repo.get_job(job_id)
        selection = repo.get_selection(job_id, selection_id)
    except KeyError:
        raise HTTPException(status_code=404, detail="Selection not found")
    if not job.get("source_video_path") or not Path(job["source_video_path"]).exists():
        raise HTTPException(status_code=409, detail="Source video is not ready.")
    transient_selection = dict(selection)
    if payload.crop_focus_x is not None:
        transient_selection["crop_focus_x"] = payload.crop_focus_x
    if payload.crop_focus_y is not None:
        transient_selection["crop_focus_y"] = payload.crop_focus_y
    if payload.subtitle_offset_ms is not None:
        transient_selection["subtitle_offset_ms"] = payload.subtitle_offset_ms
    transcript = repo.get_transcript(job_id)
    preview_dir = settings.tmp_dir / "subtitle_previews" / job_id
    try:
        metadata = render_subtitle_preview(
            job,
            transient_selection,
            transcript["tokens"],
            preview_dir,
            preview_start=payload.preview_start,
            preview_duration=payload.duration,
        )
    except Exception as exc:
        raise HTTPException(status_code=500, detail=f"Preview render failed: {exc}")
    timing = transcript.get("metadata", {})
    filename = Path(metadata["mp4"]).name
    return {
        "preview_url": f"/preview/{job_id}/{filename}",
        "timing_source": timing.get("timing_source") or "unknown",
        "timing_quality": timing.get("timing_quality") or "unknown",
        "subtitle_offset_ms": metadata["subtitle_offset_ms"],
        "start_time": metadata["start_time"],
        "end_time": metadata["end_time"],
        "duration": metadata["duration"],
    }


@app.post("/api/jobs/{job_id}/retime-transcript")
def retime_transcript(job_id: str):
    try:
        repo.get_job(job_id)
    except KeyError:
        raise HTTPException(status_code=404, detail="Job not found")
    submit_retime(job_id)
    return {"ok": True, "job": repo.get_job(job_id)}


@app.post("/api/jobs/{job_id}/selections")
def create_selection(job_id: str, payload: SelectionCreate):
    return repo.create_selection(job_id, payload.model_dump())


@app.patch("/api/jobs/{job_id}/selections/{selection_id}")
def update_selection(job_id: str, selection_id: str, payload: SelectionPatch):
    try:
        return repo.update_selection(
            job_id,
            selection_id,
            {k: v for k, v in payload.model_dump().items() if v is not None},
        )
    except KeyError:
        raise HTTPException(status_code=404, detail="Selection not found")


@app.delete("/api/jobs/{job_id}/selections/{selection_id}")
def delete_selection(job_id: str, selection_id: str):
    repo.delete_selection(job_id, selection_id)
    return {"ok": True, "job": repo.get_job(job_id)}


@app.post("/api/jobs/{job_id}/lock")
def lock(job_id: str, payload: LockRequest):
    try:
        return repo.lock_job(job_id, locked_by=payload.locked_by)
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc))


@app.post("/api/jobs/{job_id}/unlock")
def unlock(job_id: str):
    repo.unlock_job(job_id, reason="Manual unlock.")
    return repo.get_job(job_id)


@app.post("/api/jobs/{job_id}/render")
def render(job_id: str):
    try:
        repo.validate_render_allowed(job_id)
    except ValueError as exc:
        raise HTTPException(status_code=409, detail=str(exc))
    submit_render(job_id)
    return {"ok": True, "job": repo.get_job(job_id)}


@app.get("/api/jobs/{job_id}/outputs")
def outputs(job_id: str):
    return {"outputs": repo.get_outputs(job_id)}


@app.get("/api/learning/status")
def learning_status():
    return repo.learning_stats()


@app.post("/api/jobs/{job_id}/learning/sync")
def sync_learning(job_id: str):
    try:
        return {"learned": repo.sync_learning_examples_for_job(job_id), "stats": repo.learning_stats()}
    except KeyError:
        raise HTTPException(status_code=404, detail="Job not found")


@app.get("/api/system/ai-status")
def get_ai_status(validate: bool = False):
    return ai_status(validate=validate)


@app.get("/download/{job_id}/{filename}")
def download(job_id: str, filename: str):
    base = (settings.outputs_dir / job_id).resolve()
    target = (base / filename).resolve()
    if not str(target).startswith(str(base)) or not target.exists():
        raise HTTPException(status_code=404, detail="File not found")
    return FileResponse(target)


@app.get("/media/jobs/{job_id}/source")
def source_media(job_id: str):
    try:
        job = repo.get_job(job_id)
    except KeyError:
        raise HTTPException(status_code=404, detail="Job not found")
    path = job.get("source_video_path")
    if not path or not Path(path).exists():
        raise HTTPException(status_code=404, detail="Source media not ready")
    return FileResponse(path)


@app.get("/preview/{job_id}/{filename}")
def preview_media(job_id: str, filename: str):
    base = (settings.tmp_dir / "subtitle_previews" / job_id).resolve()
    target = (base / filename).resolve()
    if not str(target).startswith(str(base)) or not target.exists():
        raise HTTPException(status_code=404, detail="Preview not found")
    return FileResponse(target)
