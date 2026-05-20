from __future__ import annotations

from pathlib import Path

from fastapi import FastAPI, HTTPException, Request
from fastapi.responses import FileResponse, HTMLResponse, JSONResponse, RedirectResponse
from fastapi.staticfiles import StaticFiles
from fastapi.templating import Jinja2Templates

from app.api.schemas import ApprovalUpdate, JobCreate, LockRequest, SelectionCreate, SelectionPatch
from app.config.settings import settings
from app.storage.db import init_db
from app.storage import repository as repo
from app.system import ai_status, dependency_status
from app.workers.queue import submit_ingest, submit_render


settings.ensure_dirs()
init_db()

app = FastAPI(title="Khutbah Clip Studio")
app.mount("/static", StaticFiles(directory=settings.root / "app" / "static"), name="static")
templates = Jinja2Templates(directory=settings.root / "app" / "templates")


def page_context(request: Request, **extra):
    return {
        "request": request,
        "ai": ai_status(validate=False),
        "deps": dependency_status(),
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
