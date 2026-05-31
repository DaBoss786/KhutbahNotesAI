from __future__ import annotations

from pathlib import Path
import re
import uuid

from app.storage.db import db, json_dumps, now_iso, row_to_dict


def new_id(prefix: str) -> str:
    return f"{prefix}_{uuid.uuid4().hex[:12]}"


def add_log(job_id: str, message: str, level: str = "info") -> None:
    with db() as conn:
        conn.execute(
            "INSERT INTO logs(job_id, level, message, created_at) VALUES (?, ?, ?, ?)",
            (job_id, level, message, now_iso()),
        )


def create_job(payload: dict) -> dict:
    job_id = new_id("job")
    now = now_iso()
    branding = payload.get("branding") or {}
    with db() as conn:
        conn.execute(
            """
            INSERT INTO jobs (
                id, youtube_url, speaker_name, masjid_name, requested_clip_count,
                min_duration, max_duration, branding, status, stage, ai_mode,
                created_at, updated_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            (
                job_id,
                payload["youtube_url"],
                payload.get("speaker_name") or "",
                payload.get("masjid_name") or "",
                int(payload.get("clip_count") or 5),
                float(payload.get("min_duration") or 20),
                float(payload.get("max_duration") or 60),
                json_dumps(branding),
                "queued",
                "ingest",
                payload.get("ai_mode") or "unknown",
                now,
                now,
            ),
        )
    add_log(job_id, "Job queued.")
    return get_job(job_id)


def get_job(job_id: str) -> dict:
    with db() as conn:
        row = conn.execute("SELECT * FROM jobs WHERE id = ?", (job_id,)).fetchone()
    found = row_to_dict(row)
    if not found:
        raise KeyError(job_id)
    return found


def list_jobs() -> list[dict]:
    with db() as conn:
        rows = conn.execute(
            "SELECT * FROM jobs ORDER BY created_at DESC LIMIT 100"
        ).fetchall()
    return [row_to_dict(row) for row in rows if row]


def update_job(job_id: str, **fields) -> None:
    if not fields:
        return
    fields["updated_at"] = now_iso()
    keys = list(fields.keys())
    values = [fields[key] for key in keys]
    sql = ", ".join(f"{key} = ?" for key in keys)
    with db() as conn:
        conn.execute(f"UPDATE jobs SET {sql} WHERE id = ?", (*values, job_id))


def logs_for_job(job_id: str) -> list[dict]:
    with db() as conn:
        rows = conn.execute(
            "SELECT * FROM logs WHERE job_id = ? ORDER BY id ASC", (job_id,)
        ).fetchall()
    return [row_to_dict(row) for row in rows if row]


def normalized_text(text: str | None) -> str:
    return re.sub(r"\s+", " ", text or "").strip()


def word_set(text: str | None) -> set[str]:
    return {w.lower() for w in re.findall(r"[A-Za-z]{4,}", text or "")}


def default_render_copy(job: dict, selection: dict) -> dict:
    title = selection.get("candidate_title") or selection.get("title") or ""
    if not title:
        words = [w for w in (selection.get("text_excerpt") or "").split() if len(w) > 3][:7]
        title = " ".join(words).title() or "Khutbah Insight"
    speaker = job.get("speaker_name") or "Khutbah"
    masjid = job.get("masjid_name") or "Khutbah Notes"
    return {
        "intro_title": f"Khutbah Insight: {title}",
        "intro_subtitle": f"{speaker} - {masjid}",
        "outro_title": "See this khutbah + summaries, key points, and Quranic references",
        "outro_subtitle": "Khutbah Notes app - Available on iOS",
    }


def hydrate_selection(job: dict, selection: dict) -> dict:
    defaults = default_render_copy(job, selection)
    for key, value in defaults.items():
        if not selection.get(key):
            selection[key] = value
    if selection.get("crop_focus_x") is None:
        selection["crop_focus_x"] = 0.5
    if selection.get("crop_focus_y") is None:
        selection["crop_focus_y"] = 0.5
    if selection.get("subtitle_offset_ms") is None:
        selection["subtitle_offset_ms"] = 0
    return selection


def replace_transcript(job_id: str, segments: list[dict], tokens: list[dict], metadata: dict | None = None) -> None:
    with db() as conn:
        conn.execute("DELETE FROM transcript_tokens WHERE job_id = ?", (job_id,))
        conn.execute("DELETE FROM transcript_segments WHERE job_id = ?", (job_id,))
        segment_ids: list[int] = []
        for seg in segments:
            cur = conn.execute(
                """
                INSERT INTO transcript_segments(job_id, start_time, end_time, text)
                VALUES (?, ?, ?, ?)
                """,
                (job_id, seg["start_time"], seg["end_time"], seg["text"]),
            )
            segment_ids.append(int(cur.lastrowid))
        for idx, tok in enumerate(tokens):
            segment_id = segment_ids[min(tok.get("segment_index", 0), len(segment_ids) - 1)] if segment_ids else None
            conn.execute(
                """
                INSERT INTO transcript_tokens(
                    job_id, segment_id, start_time, end_time, text, token_index
                ) VALUES (?, ?, ?, ?, ?, ?)
                """,
                (job_id, segment_id, tok["start_time"], tok["end_time"], tok["text"], idx),
            )
        if metadata:
            conn.execute(
                """
                UPDATE jobs
                SET transcript_source = ?, timing_source = ?, timing_quality = ?, updated_at = ?
                WHERE id = ?
                """,
                (
                    metadata.get("transcript_source") or "",
                    metadata.get("timing_source") or "",
                    metadata.get("timing_quality") or "",
                    now_iso(),
                    job_id,
                ),
            )


def get_transcript(job_id: str) -> dict:
    job = get_job(job_id)
    with db() as conn:
        segs = conn.execute(
            "SELECT * FROM transcript_segments WHERE job_id = ? ORDER BY start_time ASC",
            (job_id,),
        ).fetchall()
        toks = conn.execute(
            "SELECT * FROM transcript_tokens WHERE job_id = ? ORDER BY token_index ASC",
            (job_id,),
        ).fetchall()
    return {
        "segments": [row_to_dict(row) for row in segs],
        "tokens": [row_to_dict(row) for row in toks],
        "metadata": {
            "transcript_source": job.get("transcript_source") or "",
            "timing_source": job.get("timing_source") or "unknown",
            "timing_quality": job.get("timing_quality") or "unknown",
        },
    }


def replace_candidates(job_id: str, candidates: list[dict]) -> None:
    now = now_iso()
    with db() as conn:
        conn.execute("DELETE FROM candidates WHERE job_id = ?", (job_id,))
        conn.execute("DELETE FROM selections WHERE job_id = ? AND source = 'auto'", (job_id,))
        for candidate in candidates:
            candidate_id = candidate.get("id") or new_id("cand")
            conn.execute(
                """
                INSERT INTO candidates(
                    id, job_id, start_time, end_time, title, text_excerpt,
                    quality_score, status, scores, rationale, source, created_at, updated_at
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                (
                    candidate_id,
                    job_id,
                    candidate["start_time"],
                    candidate["end_time"],
                    candidate["title"],
                    candidate["text_excerpt"],
                    candidate["quality_score"],
                    "draft",
                    json_dumps(candidate.get("scores", {})),
                    json_dumps(candidate.get("rationale", {})),
                    candidate.get("source", "auto"),
                    now,
                    now,
                ),
            )
            conn.execute(
                """
                INSERT INTO selections(
                    id, job_id, candidate_id, start_time, end_time, text_excerpt,
                    source, status, edited_at, created_at
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                (
                    new_id("sel"),
                    job_id,
                    candidate_id,
                    candidate["start_time"],
                    candidate["end_time"],
                    candidate["text_excerpt"],
                    "auto",
                    "draft",
                    now,
                    now,
                ),
            )


def get_candidates(job_id: str) -> list[dict]:
    with db() as conn:
        rows = conn.execute(
            "SELECT * FROM candidates WHERE job_id = ? ORDER BY quality_score DESC",
            (job_id,),
        ).fetchall()
    return [row_to_dict(row) for row in rows if row]


def get_selections(job_id: str) -> list[dict]:
    job = get_job(job_id)
    with db() as conn:
        rows = conn.execute(
            """
            SELECT selections.*, candidates.title AS candidate_title
            FROM selections
            LEFT JOIN candidates ON candidates.id = selections.candidate_id
            WHERE selections.job_id = ?
            ORDER BY selections.start_time ASC
            """,
            (job_id,),
        ).fetchall()
    return [hydrate_selection(job, row_to_dict(row)) for row in rows if row]


def set_candidate_approvals(job_id: str, approvals: dict[str, str]) -> None:
    now = now_iso()
    with db() as conn:
        for candidate_id, status in approvals.items():
            if status not in {"approved", "rejected", "draft"}:
                continue
            conn.execute(
                "UPDATE candidates SET status = ?, updated_at = ? WHERE job_id = ? AND id = ?",
                (status, now, job_id, candidate_id),
            )
            conn.execute(
                """
                UPDATE selections SET status = ?, edited_at = ?
                WHERE job_id = ? AND candidate_id = ?
                """,
                (status, now, job_id, candidate_id),
            )
    sync_learning_examples_for_job(job_id)
    unlock_job(job_id, reason="Approval changed after lock.")


def create_selection(job_id: str, payload: dict) -> dict:
    now = now_iso()
    selection_id = new_id("sel")
    with db() as conn:
        conn.execute(
            """
            INSERT INTO selections(
                id, job_id, start_time, end_time, text_excerpt, source,
                status, edited_at, created_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            (
                selection_id,
                job_id,
                payload["start_time"],
                payload["end_time"],
                payload.get("text_excerpt") or "",
                payload.get("source") or "manual",
                payload.get("status") or "draft",
                now,
                now,
            ),
        )
    unlock_job(job_id, reason="Selection created after lock.")
    return get_selection(job_id, selection_id)


def get_selection(job_id: str, selection_id: str) -> dict:
    job = get_job(job_id)
    with db() as conn:
        row = conn.execute(
            """
            SELECT selections.*, candidates.title AS candidate_title
            FROM selections
            LEFT JOIN candidates ON candidates.id = selections.candidate_id
            WHERE selections.job_id = ? AND selections.id = ?
            """,
            (job_id, selection_id),
        ).fetchone()
    found = row_to_dict(row)
    if not found:
        raise KeyError(selection_id)
    return hydrate_selection(job, found)


def update_selection(job_id: str, selection_id: str, payload: dict) -> dict:
    allowed = {
        k: payload[k]
        for k in [
            "start_time",
            "end_time",
            "text_excerpt",
            "status",
            "intro_title",
            "intro_subtitle",
            "outro_title",
            "outro_subtitle",
            "crop_focus_x",
            "crop_focus_y",
            "subtitle_offset_ms",
        ]
        if k in payload
    }
    if allowed:
        allowed["edited_at"] = now_iso()
        keys = list(allowed.keys())
        values = [allowed[key] for key in keys]
        sql = ", ".join(f"{key} = ?" for key in keys)
        with db() as conn:
            conn.execute(
                f"UPDATE selections SET {sql} WHERE job_id = ? AND id = ?",
                (*values, job_id, selection_id),
            )
        unlock_job(job_id, reason="Selection edited after lock.")
    return get_selection(job_id, selection_id)


def delete_selection(job_id: str, selection_id: str) -> None:
    with db() as conn:
        conn.execute(
            "DELETE FROM selections WHERE job_id = ? AND id = ?", (job_id, selection_id)
        )
    unlock_job(job_id, reason="Selection deleted after lock.")


def approved_selection_count(job_id: str) -> int:
    with db() as conn:
        row = conn.execute(
            "SELECT COUNT(*) AS count FROM selections WHERE job_id = ? AND status = 'approved'",
            (job_id,),
        ).fetchone()
    return int(row["count"])


def lock_job(job_id: str, locked_by: str = "local-user") -> dict:
    if approved_selection_count(job_id) < 1:
        raise ValueError("At least one approved selection is required before locking.")
    now = now_iso()
    with db() as conn:
        conn.execute(
            "UPDATE jobs SET locked_at = ?, locked_by = ?, stage = ?, updated_at = ? WHERE id = ?",
            (now, locked_by, "locked", now, job_id),
        )
        conn.execute(
            """
            UPDATE selections SET locked_at = ?, locked_by = ?
            WHERE job_id = ? AND status = 'approved'
            """,
            (now, locked_by, job_id),
        )
    sync_learning_examples_for_job(job_id)
    add_log(job_id, "Final selections locked.")
    return get_job(job_id)


def unlock_job(job_id: str, reason: str = "Selections unlocked.") -> None:
    job = None
    try:
        job = get_job(job_id)
    except KeyError:
        return
    if not job.get("locked_at"):
        return
    with db() as conn:
        conn.execute(
            """
            UPDATE jobs SET locked_at = NULL, locked_by = NULL,
                render_confirmed_at = NULL, status = ?, stage = ?, updated_at = ?
            WHERE id = ?
            """,
            ("review", "review", now_iso(), job_id),
        )
        conn.execute(
            "UPDATE selections SET locked_at = NULL, locked_by = NULL WHERE job_id = ?",
            (job_id,),
        )
    add_log(job_id, reason, level="warn")


def validate_render_allowed(job_id: str) -> None:
    job = get_job(job_id)
    if approved_selection_count(job_id) < 1:
        raise ValueError("Render blocked: approve at least one selection first.")
    if not job.get("locked_at"):
        raise ValueError("Render blocked: lock final selections first.")


def create_output(job_id: str, selection_id: str | None, kind: str, path: Path, status: str, payload: dict | None = None) -> dict:
    output_id = new_id("out")
    now = now_iso()
    with db() as conn:
        conn.execute(
            """
            INSERT INTO outputs(
                id, job_id, selection_id, kind, path, status, render_payload,
                created_at, updated_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            (
                output_id,
                job_id,
                selection_id,
                kind,
                str(path),
                status,
                json_dumps(payload or {}),
                now,
                now,
            ),
        )
    return get_output(output_id)


def update_output(output_id: str, **fields) -> None:
    fields["updated_at"] = now_iso()
    keys = list(fields.keys())
    values = [fields[key] for key in keys]
    sql = ", ".join(f"{key} = ?" for key in keys)
    with db() as conn:
        conn.execute(f"UPDATE outputs SET {sql} WHERE id = ?", (*values, output_id))


def get_output(output_id: str) -> dict:
    with db() as conn:
        row = conn.execute("SELECT * FROM outputs WHERE id = ?", (output_id,)).fetchone()
    found = row_to_dict(row)
    if not found:
        raise KeyError(output_id)
    return found


def get_outputs(job_id: str) -> list[dict]:
    with db() as conn:
        rows = conn.execute(
            "SELECT * FROM outputs WHERE job_id = ? ORDER BY created_at ASC",
            (job_id,),
        ).fetchall()
    return [row_to_dict(row) for row in rows if row]


def sync_learning_examples_for_job(job_id: str) -> dict:
    job = get_job(job_id)
    now = now_iso()
    positive_count = 0
    negative_count = 0
    with db() as conn:
        conn.execute("DELETE FROM learning_examples WHERE source_job_id = ?", (job_id,))

        positive_rows = conn.execute(
            """
            SELECT
                selections.*,
                candidates.title AS candidate_title,
                candidates.text_excerpt AS candidate_text,
                candidates.start_time AS candidate_start_time,
                candidates.end_time AS candidate_end_time,
                EXISTS(
                    SELECT 1 FROM outputs
                    WHERE outputs.selection_id = selections.id
                      AND outputs.kind = 'mp4'
                      AND outputs.status = 'complete'
                ) AS rendered
            FROM selections
            LEFT JOIN candidates ON candidates.id = selections.candidate_id
            WHERE selections.job_id = ?
              AND selections.status = 'approved'
            """,
            (job_id,),
        ).fetchall()
        for row in positive_rows:
            item = row_to_dict(row)
            rendered = bool(item.get("rendered"))
            if not rendered and not item.get("locked_at") and not job.get("locked_at"):
                continue
            final_text = normalized_text(item.get("text_excerpt"))
            if not final_text:
                continue
            candidate_start = item.get("candidate_start_time")
            candidate_end = item.get("candidate_end_time")
            boundary_start_delta = (
                float(item["start_time"]) - float(candidate_start)
                if candidate_start is not None
                else None
            )
            boundary_end_delta = (
                float(item["end_time"]) - float(candidate_end)
                if candidate_end is not None
                else None
            )
            metadata = {
                "speaker_name": job.get("speaker_name") or "",
                "masjid_name": job.get("masjid_name") or "",
                "youtube_url": job.get("youtube_url") or "",
                "boundary_start_delta": boundary_start_delta,
                "boundary_end_delta": boundary_end_delta,
            }
            conn.execute(
                """
                INSERT INTO learning_examples(
                    id, source_key, source_job_id, source_selection_id, source_candidate_id,
                    label, outcome, text, candidate_text, final_text, title,
                    start_time, end_time, duration, boundary_start_delta, boundary_end_delta,
                    metadata, created_at, updated_at
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                (
                    new_id("learn"),
                    f"{job_id}:{item['id']}:positive",
                    job_id,
                    item["id"],
                    item.get("candidate_id"),
                    "positive",
                    "rendered" if rendered else "locked",
                    final_text,
                    normalized_text(item.get("candidate_text")),
                    final_text,
                    item.get("candidate_title") or "",
                    item["start_time"],
                    item["end_time"],
                    float(item["end_time"]) - float(item["start_time"]),
                    boundary_start_delta,
                    boundary_end_delta,
                    json_dumps(metadata),
                    now,
                    now,
                ),
            )
            positive_count += 1

        rejected_candidates = conn.execute(
            """
            SELECT * FROM candidates
            WHERE job_id = ? AND status = 'rejected'
            """,
            (job_id,),
        ).fetchall()
        for row in rejected_candidates:
            item = row_to_dict(row)
            text = normalized_text(item.get("text_excerpt"))
            if not text:
                continue
            conn.execute(
                """
                INSERT INTO learning_examples(
                    id, source_key, source_job_id, source_candidate_id,
                    label, outcome, text, candidate_text, final_text, title,
                    start_time, end_time, duration, metadata, created_at, updated_at
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                (
                    new_id("learn"),
                    f"{job_id}:{item['id']}:negative-candidate",
                    job_id,
                    item["id"],
                    "negative",
                    "rejected_candidate",
                    text,
                    text,
                    "",
                    item.get("title") or "",
                    item["start_time"],
                    item["end_time"],
                    float(item["end_time"]) - float(item["start_time"]),
                    json_dumps({"reason": "Rejected during candidate review."}),
                    now,
                    now,
                ),
            )
            negative_count += 1

        rejected_selections = conn.execute(
            """
            SELECT selections.*, candidates.title AS candidate_title
            FROM selections
            LEFT JOIN candidates ON candidates.id = selections.candidate_id
            WHERE selections.job_id = ?
              AND selections.status = 'rejected'
              AND selections.candidate_id IS NULL
            """,
            (job_id,),
        ).fetchall()
        for row in rejected_selections:
            item = row_to_dict(row)
            text = normalized_text(item.get("text_excerpt"))
            if not text:
                continue
            conn.execute(
                """
                INSERT INTO learning_examples(
                    id, source_key, source_job_id, source_selection_id,
                    label, outcome, text, candidate_text, final_text, title,
                    start_time, end_time, duration, metadata, created_at, updated_at
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                (
                    new_id("learn"),
                    f"{job_id}:{item['id']}:negative-selection",
                    job_id,
                    item["id"],
                    "negative",
                    "rejected_selection",
                    text,
                    text,
                    "",
                    item.get("candidate_title") or "",
                    item["start_time"],
                    item["end_time"],
                    float(item["end_time"]) - float(item["start_time"]),
                    json_dumps({"reason": "Rejected during transcript selection review."}),
                    now,
                    now,
                ),
            )
            negative_count += 1
    return {"positive": positive_count, "negative": negative_count}


def learning_stats() -> dict:
    with db() as conn:
        rows = conn.execute(
            """
            SELECT label, COUNT(*) AS count
            FROM learning_examples
            GROUP BY label
            """
        ).fetchall()
    counts = {row["label"]: int(row["count"]) for row in rows}
    return {
        "positive": counts.get("positive", 0),
        "negative": counts.get("negative", 0),
        "total": sum(counts.values()),
    }


def learning_examples_for_prompt(reference_text: str = "", positive_limit: int = 8, negative_limit: int = 5) -> dict:
    query_words = word_set(reference_text)
    with db() as conn:
        rows = conn.execute(
            """
            SELECT *
            FROM learning_examples
            ORDER BY updated_at DESC
            LIMIT 250
            """
        ).fetchall()
    examples = [row_to_dict(row) for row in rows if row]

    def score(example: dict) -> tuple[int, str]:
        if not query_words:
            return (0, example.get("updated_at") or "")
        overlap = len(query_words & word_set(example.get("text")))
        return (overlap, example.get("updated_at") or "")

    positives = [item for item in examples if item.get("label") == "positive"]
    negatives = [item for item in examples if item.get("label") == "negative"]
    positives.sort(key=score, reverse=True)
    negatives.sort(key=score, reverse=True)

    def compact(item: dict) -> dict:
        return {
            "outcome": item.get("outcome"),
            "title": item.get("title") or "",
            "text": item.get("text") or "",
            "duration": round(float(item.get("duration") or 0), 1),
            "boundary_start_delta": item.get("boundary_start_delta"),
            "boundary_end_delta": item.get("boundary_end_delta"),
        }

    return {
        "stats": learning_stats(),
        "positive_examples": [compact(item) for item in positives[:positive_limit]],
        "negative_examples": [compact(item) for item in negatives[:negative_limit]],
    }
