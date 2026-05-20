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
      const stagesToRefresh = ["review", "failed", "complete", "render_failed"];
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
  document.querySelectorAll(".render-copy-card").forEach((form) => {
    form.addEventListener("submit", async (event) => {
      event.preventDefault();
      const state = form.querySelector(".save-state");
      state.textContent = "Saving...";
      const fd = new FormData(form);
      const payload = Object.fromEntries(fd.entries());
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
