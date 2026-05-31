async function api(url, options = {}) {
  const res = await fetch(url, {
    headers: { "Content-Type": "application/json", ...(options.headers || {}) },
    ...options,
  });
  const data = await res.json().catch(() => ({}));
  if (!res.ok) throw new Error(data.detail || data.message || `Request failed: ${res.status}`);
  return data;
}

function setupTabs() {
  const tabs = document.querySelector("[data-tabs]");
  if (!tabs) return;
  tabs.addEventListener("click", (event) => {
    const button = event.target.closest("[data-tab]");
    if (!button) return;
    document.querySelectorAll("[data-tab]").forEach((b) => b.classList.remove("active"));
    document.querySelectorAll(".tab-page").forEach((p) => p.classList.remove("active"));
    button.classList.add("active");
    document.getElementById(button.dataset.tab)?.classList.add("active");
  });
}

function setupNewJob() {
  const form = document.getElementById("new-job-form");
  if (!form) return;
  const message = document.getElementById("new-job-message");
  form.addEventListener("submit", async (event) => {
    event.preventDefault();
    message.textContent = "Starting job...";
    const fd = new FormData(form);
    const payload = Object.fromEntries(fd.entries());
    payload.clip_count = Number(payload.clip_count || 5);
    payload.min_duration = Number(payload.min_duration || 20);
    payload.max_duration = Number(payload.max_duration || 60);
    try {
      const job = await api("/api/jobs", { method: "POST", body: JSON.stringify(payload) });
      window.location.href = `/jobs/${job.id}`;
    } catch (error) {
      message.textContent = error.message;
    }
  });
}

function setupPolling() {
  const jobId = window.KHUTBAH_JOB_ID;
  if (!jobId) return;
  setInterval(async () => {
    try {
      const data = await api(`/api/jobs/${jobId}`);
      const job = data.job;
      const stagesToRefresh = ["review", "failed", "complete", "render_failed", "retime_failed"];
      if (stagesToRefresh.includes(job.status) && document.hidden === false) {
        const logs = document.getElementById("logs");
        if (logs) {
          logs.innerHTML = data.logs.map((log) => `<div class="log ${log.level}"><span>${log.created_at}</span>${escapeHtml(log.message)}</div>`).join("");
        }
      }
    } catch {}
  }, 4000);
}

function escapeHtml(text) {
  return String(text).replace(/[&<>"']/g, (ch) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#039;" }[ch]));
}

function timingLabel(source) {
  return {
    youtube_word: "YouTube word timings",
    whisper_word: "Whisper word timings",
    estimated: "Estimated timings",
    unknown: "Timing source unknown",
  }[source || "unknown"] || source || "Timing source unknown";
}

function setupCandidates() {
  const list = document.getElementById("candidate-list");
  if (!list) return;
  const jobId = list.dataset.jobId;
  const pending = {};

  list.addEventListener("click", async (event) => {
    const card = event.target.closest(".candidate-card");
    if (!card) return;
    const preview = document.getElementById("preview-video");
    if (event.target.closest("[data-approval]")) {
      const status = event.target.dataset.approval;
      pending[card.dataset.candidateId] = status;
      await api(`/api/jobs/${jobId}/approvals`, {
        method: "POST",
        body: JSON.stringify({ approvals: pending }),
      });
      card.querySelectorAll("[data-approval]").forEach((button) => button.classList.toggle("selected", button.dataset.approval === status));
      return;
    }
    if (preview && card.dataset.start) {
      preview.currentTime = Number(card.dataset.start);
      preview.play().catch(() => {});
    }
  });

  document.querySelectorAll("[data-bulk]").forEach((button) => {
    button.addEventListener("click", async () => {
      const status = button.dataset.bulk;
      document.querySelectorAll(".candidate-card").forEach((card) => {
        pending[card.dataset.candidateId] = status;
      });
      await api(`/api/jobs/${jobId}/approvals`, {
        method: "POST",
        body: JSON.stringify({ approvals: pending }),
      });
      window.location.reload();
    });
  });
}

function setupTranscript() {
  const body = document.getElementById("transcript-body");
  if (!body) return;
  const jobId = document.getElementById("create-selection")?.dataset.jobId;
  body.addEventListener("click", (event) => {
    const token = event.target.closest(".token");
    const preview = document.getElementById("preview-video");
    if (token && preview) {
      preview.currentTime = Number(token.dataset.time);
      preview.play().catch(() => {});
    }
  });
  document.querySelectorAll(".selection-card").forEach((card, index) => {
    const start = Number(card.dataset.start);
    const end = Number(card.dataset.end);
    document.querySelectorAll(".token").forEach((token) => {
      const t = Number(token.dataset.time);
      if (t >= start && t <= end) token.classList.add(`selected-range-${index % 4}`);
    });
  });
  document.getElementById("create-selection")?.addEventListener("click", async () => {
    const selection = window.getSelection();
    const text = selection?.toString().trim();
    if (!text) return alert("Highlight transcript text first.");
    const range = selection.getRangeAt(0);
    const spans = [...body.querySelectorAll(".token")].filter((span) => range.intersectsNode(span));
    if (!spans.length) return alert("Highlight transcript tokens first.");
    const start = Number(spans[0].dataset.time);
    const end = Number(spans[spans.length - 1].dataset.end);
    await api(`/api/jobs/${jobId}/selections`, {
      method: "POST",
      body: JSON.stringify({ start_time: start, end_time: end, text_excerpt: text, source: "manual", status: "draft" }),
    });
    window.location.reload();
  });
  document.querySelectorAll(".selection-card").forEach((card) => {
    const selectionId = card.dataset.selectionId;
    card.addEventListener("click", async (event) => {
      if (event.target.matches("[data-nudge]")) {
        const delta = Number(event.target.dataset.nudge);
        const start = Math.max(0, Number(card.dataset.start) + delta);
        const end = Math.max(start + 1, Number(card.dataset.end) + delta);
        await api(`/api/jobs/${jobId}/selections/${selectionId}`, {
          method: "PATCH",
          body: JSON.stringify({ start_time: start, end_time: end }),
        });
        window.location.reload();
      }
      if (event.target.matches("[data-status]")) {
        await api(`/api/jobs/${jobId}/selections/${selectionId}`, {
          method: "PATCH",
          body: JSON.stringify({ status: event.target.dataset.status }),
        });
        window.location.reload();
      }
      if (event.target.matches("[data-delete]")) {
        await api(`/api/jobs/${jobId}/selections/${selectionId}`, { method: "DELETE" });
        window.location.reload();
      }
    });
  });
}

function setupLockRender() {
  const lockButton = document.getElementById("lock-job");
  const unlockButton = document.getElementById("unlock-job");
  const renderButton = document.getElementById("render-job");
  const msg = document.getElementById("lock-message");
  lockButton?.addEventListener("click", async () => {
    try {
      await api(`/api/jobs/${lockButton.dataset.jobId}/lock`, { method: "POST", body: JSON.stringify({ locked_by: "local-user" }) });
      window.location.reload();
    } catch (error) {
      msg.textContent = error.message;
    }
  });
  unlockButton?.addEventListener("click", async () => {
    await api(`/api/jobs/${unlockButton.dataset.jobId}/unlock`, { method: "POST" });
    window.location.reload();
  });
  document.getElementById("retime-transcript")?.addEventListener("click", async (event) => {
    const button = event.currentTarget;
    if (!confirm("Improve timing with local Whisper word timestamps? This may take a few minutes and will unlock the job if it is locked.")) return;
    button.disabled = true;
    const previous = button.textContent;
    button.textContent = "Timing repair queued...";
    try {
      await api(`/api/jobs/${button.dataset.jobId}/retime-transcript`, { method: "POST" });
      if (msg) msg.textContent = "Timing repair started. Logs will update when it finishes.";
    } catch (error) {
      button.textContent = error.message;
      setTimeout(() => {
        button.disabled = false;
        button.textContent = previous;
      }, 2200);
    }
  });
  renderButton?.addEventListener("click", async () => {
    if (!confirm("Render locked approved clips now? This creates MP4 files locally and may take several minutes.")) return;
    try {
      await api(`/api/jobs/${renderButton.dataset.jobId}/render`, { method: "POST" });
      window.location.reload();
    } catch (error) {
      alert(error.message);
    }
  });
}

function setupRenderCopy() {
  document.getElementById("sync-learning")?.addEventListener("click", async (event) => {
    const button = event.currentTarget;
    const panel = button.closest("[data-learning-panel]");
    const status = panel?.querySelector("span");
    button.disabled = true;
    const previous = button.textContent;
    button.textContent = "Updating...";
    try {
      const data = await api(`/api/jobs/${button.dataset.jobId}/learning/sync`, { method: "POST" });
      if (status) {
        status.textContent = `${data.stats.positive} selected examples / ${data.stats.negative} rejected examples saved locally.`;
      }
      button.textContent = "Updated";
    } catch (error) {
      button.textContent = error.message;
    } finally {
      setTimeout(() => {
        button.disabled = false;
        button.textContent = previous;
      }, 1800);
    }
  });
  document.querySelectorAll(".render-copy-card").forEach((form) => {
    const preview = form.querySelector(".reframe-preview");
    const subtitleShell = form.querySelector("[data-subtitle-preview]");
    const subtitleVideo = form.querySelector(".subtitle-preview-video");
    const subtitleOverlay = form.querySelector(".subtitle-preview-overlay");
    const exactPreviewVideo = form.querySelector(".exact-preview-video");
    const exactPreviewState = form.querySelector(".exact-preview-state");
    let subtitleBlocks = null;

    const loadSubtitleBlocks = async () => {
      if (!subtitleVideo || subtitleBlocks) return subtitleBlocks;
      const data = await api(`/api/jobs/${form.dataset.jobId}/selections/${form.dataset.selectionId}/subtitle-preview`);
      subtitleBlocks = data.blocks || [];
      const timingSource = document.querySelector("[data-timing-source]");
      if (timingSource && data.timing_source) {
        timingSource.textContent = timingLabel(data.timing_source);
      }
      return subtitleBlocks;
    };

    const renderSubtitlePreview = () => {
      if (!subtitleVideo || !subtitleOverlay || !subtitleBlocks) return;
      const offsetMs = Number(form.querySelector("input[name='subtitle_offset_ms']")?.value || 0);
      const adjustedTime = subtitleVideo.currentTime - offsetMs / 1000;
      let block = subtitleBlocks.find((candidate) => adjustedTime >= candidate.start_time && adjustedTime < candidate.end_time);
      if (!block) {
        if (!subtitleBlocks.length) {
          subtitleOverlay.innerHTML = "";
          return;
        }
        block = adjustedTime < subtitleBlocks[0].start_time ? subtitleBlocks[0] : subtitleBlocks[subtitleBlocks.length - 1];
      }
      let activeIndex = 0;
      block.tokens.forEach((token, index) => {
        if (adjustedTime >= token.start_time) activeIndex = index;
      });
      subtitleOverlay.innerHTML = block.tokens.map((token, index) => {
        const cls = index === activeIndex ? "active" : "";
        return `<span class="${cls}">${escapeHtml(token.text)}</span>`;
      }).join(" ");
    };

    const syncSubtitlePreviewCrop = () => {
      if (!subtitleVideo) return;
      const x = Number(form.querySelector("input[name='crop_focus_x']")?.value || 0.5) * 100;
      const y = Number(form.querySelector("input[name='crop_focus_y']")?.value || 0.5) * 100;
      subtitleVideo.style.objectPosition = `${x}% ${y}%`;
    };

    const updatePreviewFrame = () => {
      const x = Number(form.querySelector("input[name='crop_focus_x']")?.value || 0.5) * 100;
      const y = Number(form.querySelector("input[name='crop_focus_y']")?.value || 0.5) * 100;
      if (preview) preview.style.objectPosition = `${x}% ${y}%`;
      syncSubtitlePreviewCrop();
    };
    if (preview) {
      preview.addEventListener("loadedmetadata", () => {
        const targetTime = Number(preview.dataset.previewTime || 0);
        if (Number.isFinite(targetTime)) preview.currentTime = Math.max(0, targetTime);
      });
    }
    if (subtitleVideo) {
      subtitleVideo.addEventListener("loadedmetadata", () => {
        const start = Number(subtitleVideo.dataset.start || 0);
        if (Number.isFinite(start)) subtitleVideo.currentTime = Math.max(0, start);
        loadSubtitleBlocks().then(renderSubtitlePreview).catch(() => {});
      });
      subtitleVideo.addEventListener("timeupdate", () => {
        const end = Number(subtitleVideo.dataset.end || 0);
        if (end && subtitleVideo.currentTime >= end) {
          subtitleVideo.pause();
          subtitleVideo.currentTime = Number(subtitleVideo.dataset.start || 0);
        }
        renderSubtitlePreview();
      });
      subtitleVideo.addEventListener("seeked", renderSubtitlePreview);
      subtitleVideo.addEventListener("play", () => {
        loadSubtitleBlocks().then(renderSubtitlePreview).catch(() => {});
      });
    }
    form.querySelector("[data-play-subtitle-preview]")?.addEventListener("click", async () => {
      if (!subtitleVideo) return;
      await loadSubtitleBlocks();
      subtitleVideo.currentTime = Number(subtitleVideo.dataset.start || 0);
      renderSubtitlePreview();
      subtitleVideo.play().catch(() => {});
    });
    form.querySelectorAll("input[type='range'][data-range-value]").forEach((input) => {
      const output = document.getElementById(input.dataset.rangeValue);
      const sync = () => {
        if (output) {
          output.textContent = input.dataset.rangeFormat === "ms"
            ? String(Math.round(Number(input.value)))
            : String(Math.round(Number(input.value) * 100));
        }
        updatePreviewFrame();
        renderSubtitlePreview();
      };
      input.addEventListener("input", sync);
      sync();
    });
    form.querySelectorAll("[data-framing-x]").forEach((button) => {
      button.addEventListener("click", () => {
        const input = form.querySelector("input[name='crop_focus_x']");
        if (!input) return;
        input.value = button.dataset.framingX;
        input.dispatchEvent(new Event("input"));
      });
    });
    form.querySelectorAll("[data-subtitle-offset]").forEach((button) => {
      button.addEventListener("click", () => {
        const input = form.querySelector("input[name='subtitle_offset_ms']");
        if (!input) return;
        input.value = button.dataset.subtitleOffset;
        input.dispatchEvent(new Event("input"));
      });
    });
    form.querySelector("[data-render-subtitle-preview]")?.addEventListener("click", async (event) => {
      const button = event.currentTarget;
      const fd = new FormData(form);
      const payload = Object.fromEntries(fd.entries());
      payload.crop_focus_x = Number(payload.crop_focus_x || 0.5);
      payload.crop_focus_y = Number(payload.crop_focus_y || 0.5);
      payload.subtitle_offset_ms = Number(payload.subtitle_offset_ms || 0);
      payload.duration = 8;
      if (subtitleVideo && Number.isFinite(subtitleVideo.currentTime)) {
        payload.preview_start = subtitleVideo.currentTime;
      }
      button.disabled = true;
      if (exactPreviewState) exactPreviewState.textContent = "Rendering exact preview...";
      try {
        const data = await api(`/api/jobs/${form.dataset.jobId}/selections/${form.dataset.selectionId}/subtitle-preview-render`, {
          method: "POST",
          body: JSON.stringify(payload),
        });
        if (exactPreviewVideo) {
          exactPreviewVideo.src = `${data.preview_url}?v=${Date.now()}`;
          exactPreviewVideo.hidden = false;
          exactPreviewVideo.load();
        }
        if (exactPreviewState) {
          exactPreviewState.textContent = `Exact preview ready (${timingLabel(data.timing_source)}, ${data.subtitle_offset_ms}ms).`;
        }
      } catch (error) {
        if (exactPreviewState) exactPreviewState.textContent = error.message;
      } finally {
        button.disabled = false;
      }
    });
    form.addEventListener("submit", async (event) => {
      event.preventDefault();
      const state = form.querySelector(".save-state");
      state.textContent = "Saving...";
      const fd = new FormData(form);
      const payload = Object.fromEntries(fd.entries());
      if (payload.crop_focus_x !== undefined) payload.crop_focus_x = Number(payload.crop_focus_x);
      if (payload.crop_focus_y !== undefined) payload.crop_focus_y = Number(payload.crop_focus_y);
      if (payload.subtitle_offset_ms !== undefined) payload.subtitle_offset_ms = Number(payload.subtitle_offset_ms);
      try {
        await api(`/api/jobs/${form.dataset.jobId}/selections/${form.dataset.selectionId}`, {
          method: "PATCH",
          body: JSON.stringify(payload),
        });
        state.textContent = "Saved. Relock before render if this was already locked.";
      } catch (error) {
        state.textContent = error.message;
      }
    });
  });
}

setupTabs();
setupNewJob();
setupPolling();
setupCandidates();
setupTranscript();
setupLockRender();
setupRenderCopy();
