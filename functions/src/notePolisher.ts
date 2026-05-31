/* eslint-disable max-len, valid-jsdoc */
import {createHmac, scryptSync, timingSafeEqual} from "crypto";
import type {Request, Response} from "express";
import type * as admin from "firebase-admin";
import {FieldValue, Timestamp} from "firebase-admin/firestore";
import {logger} from "firebase-functions";
import OpenAI from "openai";

type PolishType = "hpi" | "ap";

type NotePolisherHandlerOptions = {
  db: admin.firestore.Firestore;
  openaiKey: {value(): string};
  passwordHash: {value(): string};
  sessionSecret: {value(): string};
};

const BASE_PATH = "/note-polisher";
const SESSION_COOKIE = "__session";
const SESSION_TTL_SECONDS = 7 * 24 * 60 * 60;
const LOGIN_LIMIT = 8;
const LOGIN_WINDOW_MS = 15 * 60 * 1000;
const MAX_ROUGH_TEXT_LENGTH = 12000;
const MAX_STYLE_EXAMPLES = 5;
const MAX_STYLE_EXAMPLE_LENGTH = 6000;
const DEFAULT_MODEL = "gpt-5.4";
const RATE_LIMIT_COLLECTION = "notePolisherRateLimits";

const HPI_SYSTEM_INSTRUCTION =
  "You are an expert medical documentation assistant for an otolaryngologist. " +
  "Rewrite the user’s rough HPI into a polished HPI in the physician’s " +
  "preferred style. Use standard medical terminology and concise clinical " +
  "note language. Write 1 to 2 paragraphs. Preserve only facts provided by " +
  "the user. Do not add diagnoses, symptoms, pertinent negatives, exam " +
  "findings, treatments, dates, durations, or clinical interpretations unless " +
  "explicitly present in the input. Do not create a treatment plan. Do not " +
  "include assessment or plan. If the rough input is too sparse, produce a " +
  "clean concise HPI using only available facts.";

const AP_SYSTEM_INSTRUCTION =
  "You are an expert medical documentation assistant for an otolaryngologist. " +
  "Rewrite the user’s rough Assessment & Plan into a polished A/P in the " +
  "physician’s preferred style. Preserve only facts, diagnoses, " +
  "recommendations, medications, procedures, and follow-up instructions " +
  "provided by the user. Do not add new diagnoses, workup, medications, " +
  "treatment options, counseling, risks, or follow-up intervals unless " +
  "explicitly present. Organize clearly by problem when possible. Use concise " +
  "physician-style clinical documentation.";

const STYLE_EXAMPLE_PREAMBLE =
  "Here are examples of the physician’s preferred style. Use these only to " +
  "learn tone, structure, phrasing, and formatting. Do not copy " +
  "patient-specific facts from these examples.";

/**
 * Creates the protected Note Polisher HTTP handler.
 *
 * @param {NotePolisherHandlerOptions} options Runtime dependencies.
 * @return {(req: Request, res: Response) => Promise<void>} Express handler.
 */
export function createNotePolisherHandler(
  options: NotePolisherHandlerOptions
): (req: Request, res: Response) => Promise<void> {
  return async (req: Request, res: Response) => {
    applyNoStoreHeaders(res);

    const path = resolveRoutePath(req);

    try {
      if (req.method === "GET" && (path === "" || path === "/")) {
        if (isAuthenticated(req, options.sessionSecret.value())) {
          sendHtml(res, renderAppShell());
          return;
        }

        sendHtml(res, renderLoginPage());
        return;
      }

      if (req.method === "POST" && path === "/login") {
        await handleLogin(req, res, options);
        return;
      }

      if (req.method === "POST" && path === "/logout") {
        clearSessionCookie(req, res);
        res.status(200).json({ok: true});
        return;
      }

      if (!isAuthenticated(req, options.sessionSecret.value())) {
        res.status(401).json({error: "Unauthorized"});
        return;
      }

      if (req.method === "GET" && path === "/api/settings") {
        res.status(200).json({model: resolveModelName()});
        return;
      }

      if (req.method === "POST" && path === "/api/polish") {
        await handlePolish(req, res, options.openaiKey.value());
        return;
      }

      res.status(404).send("Not found");
    } catch (error: unknown) {
      logger.error("Note Polisher request failed.", {
        path,
        method: req.method,
        error: error instanceof Error ? error.message : "unknown",
      });
      res.status(500).json({
        error: "Unable to complete this request right now.",
      });
    }
  };
}

/**
 * Handles password verification and session creation.
 *
 * @param {Request} req Express request.
 * @param {Response} res Express response.
 * @param {NotePolisherHandlerOptions} options Runtime dependencies.
 */
async function handleLogin(
  req: Request,
  res: Response,
  options: NotePolisherHandlerOptions
): Promise<void> {
  const ipHash = hashIp(req, options.sessionSecret.value());
  const limited = await isLoginLimited(options.db, ipHash);
  if (limited) {
    res.status(429).json({
      error: "Too many attempts. Try again in about 15 minutes.",
    });
    return;
  }

  const password = parsePassword(req.body);
  const valid = verifyPassword(password, options.passwordHash.value());

  if (!valid) {
    await recordFailedLogin(options.db, ipHash);
    res.status(401).json({error: "Incorrect password."});
    return;
  }

  setSessionCookie(req, res, options.sessionSecret.value());
  res.status(200).json({ok: true});
}

/**
 * Handles note polishing. Do not log note text or examples here.
 *
 * @param {Request} req Express request.
 * @param {Response} res Express response.
 * @param {string} apiKey OpenAI API key.
 */
async function handlePolish(
  req: Request,
  res: Response,
  apiKey: string
): Promise<void> {
  const body = req.body as {
    type?: unknown;
    roughText?: unknown;
    styleExamples?: unknown;
  };

  if (body.type !== "hpi" && body.type !== "ap") {
    res.status(400).json({error: "Choose HPI or A/P before polishing."});
    return;
  }

  if (typeof body.roughText !== "string" || !body.roughText.trim()) {
    res.status(400).json({
      error: "Paste or dictate rough text before polishing.",
    });
    return;
  }

  const roughText = body.roughText.trim();
  if (roughText.length > MAX_ROUGH_TEXT_LENGTH) {
    res.status(400).json({
      error: "This note is too long. Shorten it and try again.",
    });
    return;
  }

  const styleExamples = normalizeStyleExamples(body.styleExamples);
  const openai = new OpenAI({apiKey});
  const response = await openai.responses.create({
    model: resolveModelName(),
    instructions: body.type === "hpi" ?
      HPI_SYSTEM_INSTRUCTION :
      AP_SYSTEM_INSTRUCTION,
    input: buildModelInput(body.type, roughText, styleExamples),
  });

  const polishedText = response.output_text?.trim();
  if (!polishedText) {
    res.status(502).json({
      error: "The model returned an empty response. Try again.",
    });
    return;
  }

  res.status(200).json({polishedText});
}

/**
 * Returns a normalized route path inside /note-polisher.
 *
 * @param {Request} req Express request.
 * @return {string} Route path.
 */
function resolveRoutePath(req: Request): string {
  const rawPath = (req.path || req.url.split("?")[0] || "").replace(/\/+$/, "");
  if (rawPath === BASE_PATH) {
    return "";
  }
  if (rawPath.startsWith(`${BASE_PATH}/`)) {
    return rawPath.slice(BASE_PATH.length);
  }
  return rawPath;
}

/**
 * Parses a password from a JSON or form request body.
 *
 * @param {unknown} body Request body.
 * @return {string} Password value.
 */
function parsePassword(body: unknown): string {
  if (!body || typeof body !== "object") {
    return "";
  }
  const password = (body as {password?: unknown}).password;
  return typeof password === "string" ? password : "";
}

/**
 * Verifies a scrypt password hash.
 *
 * @param {string} password Plain password candidate.
 * @param {string} encodedHash Encoded scrypt hash.
 * @return {boolean} Whether the password matches.
 */
function verifyPassword(password: string, encodedHash: string): boolean {
  const parts = encodedHash.split("$");
  if (
    parts.length !== 7 ||
    parts[0] !== "scrypt" ||
    parts[1] !== "v1"
  ) {
    return false;
  }

  const n = Number(parts[2]);
  const r = Number(parts[3]);
  const p = Number(parts[4]);
  const salt = Buffer.from(parts[5], "base64url");
  const expected = Buffer.from(parts[6], "base64url");
  if (!Number.isFinite(n) || !Number.isFinite(r) || !Number.isFinite(p)) {
    return false;
  }

  const actual = scryptSync(password, salt, expected.length, {N: n, r, p});
  return expected.length === actual.length && timingSafeEqual(expected, actual);
}

/**
 * Creates and sets the signed session cookie.
 *
 * @param {Request} req Express request.
 * @param {Response} res Express response.
 * @param {string} secret Session signing secret.
 */
function setSessionCookie(req: Request, res: Response, secret: string): void {
  const now = Math.floor(Date.now() / 1000);
  const payload = Buffer.from(JSON.stringify({
    iat: now,
    exp: now + SESSION_TTL_SECONDS,
  })).toString("base64url");
  const signature = signSessionPayload(payload, secret);
  const secure = shouldUseSecureCookie(req);
  const parts = [
    `${SESSION_COOKIE}=v1.${payload}.${signature}`,
    `Max-Age=${SESSION_TTL_SECONDS}`,
    `Path=${BASE_PATH}`,
    "HttpOnly",
    "SameSite=Lax",
  ];
  if (secure) {
    parts.push("Secure");
  }
  res.setHeader("Set-Cookie", parts.join("; "));
}

/**
 * Clears the session cookie.
 *
 * @param {Request} req Express request.
 * @param {Response} res Express response.
 */
function clearSessionCookie(req: Request, res: Response): void {
  const parts = [
    `${SESSION_COOKIE}=`,
    "Max-Age=0",
    `Path=${BASE_PATH}`,
    "HttpOnly",
    "SameSite=Lax",
  ];
  if (shouldUseSecureCookie(req)) {
    parts.push("Secure");
  }
  res.setHeader("Set-Cookie", parts.join("; "));
}

/**
 * Validates the signed session cookie.
 *
 * @param {Request} req Express request.
 * @param {string} secret Session signing secret.
 * @return {boolean} Whether request is authenticated.
 */
function isAuthenticated(req: Request, secret: string): boolean {
  const cookies = parseCookies(req.headers.cookie || "");
  const value = cookies[SESSION_COOKIE];
  if (!value) {
    return false;
  }

  const parts = value.split(".");
  if (parts.length !== 3 || parts[0] !== "v1") {
    return false;
  }

  const expected = signSessionPayload(parts[1], secret);
  const supplied = Buffer.from(parts[2]);
  const expectedBuffer = Buffer.from(expected);
  if (
    supplied.length !== expectedBuffer.length ||
    !timingSafeEqual(supplied, expectedBuffer)
  ) {
    return false;
  }

  try {
    const payload = JSON.parse(
      Buffer.from(parts[1], "base64url").toString("utf8")
    ) as {exp?: unknown};
    return typeof payload.exp === "number" &&
      payload.exp > Math.floor(Date.now() / 1000);
  } catch {
    return false;
  }
}

/**
 * Signs a session payload.
 *
 * @param {string} payload Base64url payload.
 * @param {string} secret Signing secret.
 * @return {string} Base64url HMAC.
 */
function signSessionPayload(payload: string, secret: string): string {
  return createHmac("sha256", secret).update(payload).digest("base64url");
}

/**
 * Parses cookies from a request header.
 *
 * @param {string} header Cookie header.
 * @return {Record<string, string>} Cookie map.
 */
function parseCookies(header: string): Record<string, string> {
  return header.split(";").reduce<Record<string, string>>((acc, item) => {
    const index = item.indexOf("=");
    if (index === -1) {
      return acc;
    }
    const key = item.slice(0, index).trim();
    const value = item.slice(index + 1).trim();
    if (key) {
      acc[key] = decodeURIComponent(value);
    }
    return acc;
  }, {});
}

/**
 * Determines whether to mark cookies Secure.
 *
 * @param {Request} req Express request.
 * @return {boolean} Whether Secure should be added.
 */
function shouldUseSecureCookie(req: Request): boolean {
  const host = req.hostname || req.headers.host || "";
  return !host.startsWith("localhost") && !host.startsWith("127.0.0.1");
}

/**
 * Returns a privacy-preserving hash of the requester IP.
 *
 * @param {Request} req Express request.
 * @param {string} secret Hash secret.
 * @return {string} IP hash.
 */
function hashIp(req: Request, secret: string): string {
  const forwardedFor = req.headers["x-forwarded-for"];
  const firstForwarded = Array.isArray(forwardedFor) ?
    forwardedFor[0] :
    forwardedFor;
  const ip = firstForwarded?.split(",")[0]?.trim() || req.ip || "unknown";
  return createHmac("sha256", secret).update(ip).digest("hex");
}

/**
 * Checks whether this IP hash has exhausted login attempts.
 *
 * @param {FirebaseFirestore.Firestore} db Firestore instance.
 * @param {string} ipHash Hashed IP.
 * @return {Promise<boolean>} Whether login should be blocked.
 */
async function isLoginLimited(
  db: admin.firestore.Firestore,
  ipHash: string
): Promise<boolean> {
  const windowStart = Math.floor(Date.now() / LOGIN_WINDOW_MS) *
    LOGIN_WINDOW_MS;
  const doc = await db.collection(RATE_LIMIT_COLLECTION)
    .doc(`${ipHash}_${windowStart}`)
    .get();
  const count = Number(doc.data()?.count || 0);
  return count >= LOGIN_LIMIT;
}

/**
 * Records a failed login attempt.
 *
 * @param {FirebaseFirestore.Firestore} db Firestore instance.
 * @param {string} ipHash Hashed IP.
 */
async function recordFailedLogin(
  db: admin.firestore.Firestore,
  ipHash: string
): Promise<void> {
  const now = Date.now();
  const windowStart = Math.floor(now / LOGIN_WINDOW_MS) * LOGIN_WINDOW_MS;
  const windowEnd = windowStart + LOGIN_WINDOW_MS;
  await db.collection(RATE_LIMIT_COLLECTION)
    .doc(`${ipHash}_${windowStart}`)
    .set({
      ipHash,
      windowStart,
      windowEnd,
      count: FieldValue.increment(1),
      updatedAt: FieldValue.serverTimestamp(),
      expiresAt: Timestamp.fromMillis(windowEnd + LOGIN_WINDOW_MS),
    }, {merge: true});
}

/**
 * Normalizes style examples.
 *
 * @param {unknown} styleExamples Incoming examples.
 * @return {string[]} Cleaned examples.
 */
function normalizeStyleExamples(styleExamples: unknown): string[] {
  if (!Array.isArray(styleExamples)) {
    return [];
  }

  return styleExamples
    .filter((example): example is string => typeof example === "string")
    .map((example) => example.trim())
    .filter(Boolean)
    .slice(0, MAX_STYLE_EXAMPLES)
    .map((example) => example.slice(0, MAX_STYLE_EXAMPLE_LENGTH));
}

/**
 * Builds the model input without adding extra facts.
 *
 * @param {PolishType} type Note section type.
 * @param {string} roughText Rough user text.
 * @param {string[]} styleExamples Style examples.
 * @return {string} Model input.
 */
function buildModelInput(
  type: PolishType,
  roughText: string,
  styleExamples: string[]
): string {
  const styleSection = styleExamples.length > 0 ?
    `${STYLE_EXAMPLE_PREAMBLE}\n\n${styleExamples
      .map((example, index) => `Example ${index + 1}:\n${example}`)
      .join("\n\n")}\n\n` :
    "";

  const label = type === "hpi" ? "HPI" : "Assessment & Plan";
  return `${styleSection}Rough ${label}:\n${roughText}`;
}

/**
 * Resolves the OpenAI model.
 *
 * @return {string} Model name.
 */
function resolveModelName(): string {
  return process.env.OPENAI_MODEL || DEFAULT_MODEL;
}

/**
 * Sends HTML.
 *
 * @param {Response} res Express response.
 * @param {string} html HTML body.
 */
function sendHtml(res: Response, html: string): void {
  res.setHeader("Content-Type", "text/html; charset=utf-8");
  res.status(200).send(html);
}

/**
 * Applies security and no-store response headers.
 *
 * @param {Response} res Express response.
 */
function applyNoStoreHeaders(res: Response): void {
  res.setHeader("Cache-Control", "private, no-store, max-age=0");
  res.setHeader("X-Content-Type-Options", "nosniff");
  res.setHeader("Referrer-Policy", "no-referrer");
  res.setHeader("X-Frame-Options", "DENY");
}

/**
 * Renders the password page.
 *
 * @return {string} Login HTML.
 */
function renderLoginPage(): string {
  return htmlPage("Note Polisher Login", `
    <main class="login-shell">
      <section class="login-card">
        <div class="brand-mark">NP</div>
        <h1>Note Polisher</h1>
        <p class="muted">Private access for the personal note polishing tool.</p>
        <form id="loginForm" class="login-form">
          <label for="password">Password</label>
          <input id="password" name="password" type="password"
            autocomplete="current-password" required autofocus>
          <button type="submit">Unlock</button>
          <p id="loginError" class="error" role="alert"></p>
        </form>
        <p class="privacy-copy">
          For personal testing only. Do not enter PHI unless you have
          appropriate compliance, approvals, and vendor agreements in place.
        </p>
      </section>
    </main>
    <script>
      document.getElementById("loginForm").addEventListener("submit", async (event) => {
        event.preventDefault();
        const error = document.getElementById("loginError");
        error.textContent = "";
        const password = document.getElementById("password").value;
        const response = await fetch("${BASE_PATH}/login", {
          method: "POST",
          headers: {"Content-Type": "application/json"},
          body: JSON.stringify({password})
        });
        const data = await response.json().catch(() => ({}));
        if (!response.ok) {
          error.textContent = data.error || "Unable to unlock.";
          return;
        }
        window.location.href = "${BASE_PATH}";
      });
    </script>
  `);
}

/**
 * Renders the app shell.
 *
 * @return {string} App HTML.
 */
function renderAppShell(): string {
  return htmlPage("Note Polisher", `
    <main class="app-shell">
      <header class="top-card">
        <div>
          <div class="title-row">
            <div class="brand-mark">NP</div>
            <h1>Note Polisher</h1>
          </div>
          <p class="muted">Paste or dictate rough text, then convert it into
            your preferred note style.</p>
        </div>
        <div class="status-row">
          <span class="chip" id="modelChip">Model: loading</span>
          <span class="chip warning">Personal testing only</span>
          <button class="secondary small" id="logoutButton">Log out</button>
        </div>
        <nav class="tabs" aria-label="Primary">
          <button class="tab active" data-tab="polish">Polish Notes</button>
          <button class="tab" data-tab="library">Style Library</button>
          <button class="tab" data-tab="settings">Settings/About</button>
        </nav>
      </header>
      <section class="notice">
        For personal testing only. Do not enter PHI unless you have appropriate
        compliance, approvals, and vendor agreements in place.
      </section>
      <section class="tab-panel" id="polishPanel">
        ${notePanel("hpi", "Rough HPI", "Polish HPI", "Polished HPI")}
        ${notePanel(
    "ap",
    "Rough Assessment & Plan",
    "Polish A/P",
    "Polished A/P"
  )}
      </section>
      <section class="tab-panel hidden" id="libraryPanel">
        <div class="card">
          <div class="card-head">
            <div>
              <h2>Style Library</h2>
              <p class="muted">Examples stay in this browser only and persist
                after closing the tab. Export a backup before clearing browser
                data or switching devices.</p>
            </div>
            <div class="button-row">
              <button class="secondary" id="exportButton">Export backup</button>
              <button class="secondary" id="restoreButton">Restore backup</button>
              <button class="secondary" id="clearExamplesButton">
                Clear all examples
              </button>
            </div>
          </div>
          <input id="restoreInput" type="file" accept="application/json,.json"
            hidden>
          <label for="exampleText">Paste example note</label>
          <textarea id="exampleText" class="large-textarea"
            placeholder="Paste an example note in your preferred style. Do not paste PHI unless compliance is in place."></textarea>
          <div class="form-row">
            <label for="exampleType">Type</label>
            <select id="exampleType">
              <option value="hpi">HPI</option>
              <option value="ap">A/P</option>
            </select>
            <button id="saveExampleButton">Save to Style Library</button>
          </div>
          <p class="message" id="libraryMessage"></p>
          <div class="example-grid">
            <div>
              <h3>Saved HPI Examples</h3>
              <div id="hpiExamples" class="example-list"></div>
            </div>
            <div>
              <h3>Saved A/P Examples</h3>
              <div id="apExamples" class="example-list"></div>
            </div>
          </div>
        </div>
      </section>
      <section class="tab-panel hidden" id="settingsPanel">
        <div class="card">
          <h2>Settings/About</h2>
          <p>This app rewrites rough clinical HPI and Assessment & Plan text
            into a preferred style. It does not diagnose, recommend treatment,
            or replace clinical judgment.</p>
          <p>Saved Style Library examples are used only as style references.
            They are stored only in this browser's localStorage.</p>
          <p>This v1 is not HIPAA-compliant. Do not enter PHI unless you have
            appropriate compliance, approvals, and vendor agreements in place.</p>
          <p><strong>Current model:</strong> <span id="settingsModel">loading</span></p>
        </div>
      </section>
    </main>
    <script>
      ${clientScript()}
    </script>
  `);
}

/**
 * Renders a note panel.
 *
 * @param {PolishType} type Note type.
 * @param {string} title Input title.
 * @param {string} button Button label.
 * @param {string} outputTitle Output title.
 * @return {string} HTML fragment.
 */
function notePanel(
  type: PolishType,
  title: string,
  button: string,
  outputTitle: string
): string {
  const placeholder = type === "hpi" ?
    "Paste or dictate a rough HPI here. Native browser, iPhone, Chrome, and Dragon dictation can enter text into this box." :
    "Paste or dictate rough Assessment & Plan text here. Native browser, iPhone, Chrome, and Dragon dictation can enter text into this box.";

  return `
    <div class="card note-card" data-note-type="${type}">
      <div class="card-head">
        <div>
          <h2>${title}</h2>
          <p class="muted" id="${type}ExampleCount">
            Uses the newest 0 saved ${type === "hpi" ? "HPI" : "A/P"}
            style examples.
          </p>
        </div>
        <div class="button-row">
          <button class="secondary" data-action="clear" data-type="${type}">
            Clear
          </button>
          <button data-action="polish" data-type="${type}">${button}</button>
        </div>
      </div>
      <textarea class="large-textarea" id="${type}Rough"
        aria-label="${title}" placeholder="${placeholder}"></textarea>
      <p class="error" id="${type}Error"></p>
      <div class="output-box">
        <div class="output-head">
          <h3>${outputTitle}</h3>
          <button class="secondary small" data-action="copy" data-type="${type}">
            Copy
          </button>
        </div>
        <div class="output-text" id="${type}Output">
          <span class="placeholder">Polished output will appear here.</span>
        </div>
      </div>
    </div>
  `;
}

/**
 * Wraps content in the shared HTML document.
 *
 * @param {string} title Page title.
 * @param {string} body Body content.
 * @return {string} Full HTML.
 */
function htmlPage(title: string, body: string): string {
  return `<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>${escapeHtml(title)}</title>
  <style>${styles()}</style>
</head>
<body>${body}</body>
</html>`;
}

/**
 * Escapes text for HTML.
 *
 * @param {string} value Text.
 * @return {string} Escaped text.
 */
function escapeHtml(value: string): string {
  return value
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");
}

/**
 * Returns CSS for the function-served app.
 *
 * @return {string} CSS.
 */
function styles(): string {
  return `
    * { box-sizing: border-box; }
    body {
      margin: 0;
      background: #f1f5f9;
      color: #0f172a;
      font-family: Arial, Helvetica, sans-serif;
    }
    .app-shell, .login-shell {
      width: min(1180px, calc(100% - 32px));
      margin: 0 auto;
      padding: 24px 0;
    }
    .login-shell {
      min-height: 100vh;
      display: grid;
      place-items: center;
    }
    .login-card, .top-card, .card {
      background: #fff;
      border: 1px solid #d8e0ea;
      border-radius: 8px;
      box-shadow: 0 1px 3px rgba(15, 23, 42, 0.08);
      padding: 20px;
    }
    .login-card { width: min(440px, 100%); }
    .title-row, .card-head, .status-row, .button-row, .form-row {
      display: flex;
      align-items: center;
      gap: 10px;
    }
    .card-head {
      justify-content: space-between;
      align-items: flex-start;
      margin-bottom: 14px;
    }
    .top-card {
      display: grid;
      gap: 16px;
      margin-bottom: 20px;
    }
    .brand-mark {
      display: inline-grid;
      place-items: center;
      width: 36px;
      height: 36px;
      border-radius: 7px;
      background: #0f8a7a;
      color: #fff;
      font-weight: 700;
      font-size: 13px;
    }
    h1, h2, h3, p { margin-top: 0; }
    h1 { margin-bottom: 0; font-size: 28px; }
    h2 { margin-bottom: 6px; font-size: 20px; }
    h3 { margin: 0; font-size: 14px; }
    p { line-height: 1.6; }
    .muted { color: #52627a; margin-bottom: 0; }
    .tabs { display: flex; flex-wrap: wrap; gap: 8px; }
    button, select, input, textarea {
      font: inherit;
    }
    button {
      border: 1px solid #0f8a7a;
      border-radius: 7px;
      background: #0f8a7a;
      color: #fff;
      padding: 10px 14px;
      font-weight: 700;
      cursor: pointer;
    }
    button:disabled { opacity: 0.55; cursor: not-allowed; }
    .secondary, .tab {
      background: #fff;
      color: #26364f;
      border-color: #cbd5e1;
      font-weight: 500;
    }
    .tab.active { background: #0f8a7a; color: #fff; border-color: #0f8a7a; }
    .small { padding: 7px 10px; font-size: 13px; }
    .chip {
      border: 1px solid #8ddfd5;
      background: #e6fffb;
      color: #006b5d;
      border-radius: 7px;
      padding: 7px 10px;
      font-size: 13px;
    }
    .chip.warning {
      border-color: #f6cf7d;
      background: #fff7e6;
      color: #9a4b00;
    }
    .notice {
      border: 1px solid #f6c34b;
      background: #fffbeb;
      color: #823900;
      border-radius: 8px;
      padding: 14px 16px;
      margin-bottom: 16px;
      line-height: 1.6;
    }
    .tab-panel { display: grid; gap: 16px; }
    .hidden { display: none; }
    .large-textarea {
      width: 100%;
      min-height: 210px;
      resize: vertical;
      border: 1px solid #cbd5e1;
      border-radius: 7px;
      padding: 13px;
      line-height: 1.55;
      color: #0f172a;
      outline: none;
    }
    .large-textarea:focus, input:focus, select:focus {
      border-color: #0f8a7a;
      box-shadow: 0 0 0 4px #ccfbf1;
    }
    .output-box {
      margin-top: 16px;
      border: 1px solid #cbd5e1;
      border-radius: 7px;
      background: #f8fafc;
      overflow: hidden;
    }
    .output-head {
      display: flex;
      align-items: center;
      justify-content: space-between;
      border-bottom: 1px solid #e2e8f0;
      background: #fff;
      padding: 10px 12px;
    }
    .output-text {
      min-height: 160px;
      padding: 14px;
      line-height: 1.6;
      white-space: pre-wrap;
    }
    .placeholder { color: #8aa0bf; }
    .error { color: #b42318; min-height: 20px; }
    .message { color: #00796b; min-height: 20px; }
    label { display: block; margin: 12px 0 6px; font-weight: 600; }
    input, select {
      height: 42px;
      border: 1px solid #cbd5e1;
      border-radius: 7px;
      padding: 0 12px;
      background: #fff;
    }
    .login-form button { width: 100%; margin-top: 14px; }
    .privacy-copy { margin-top: 18px; color: #823900; font-size: 14px; }
    .example-grid {
      display: grid;
      grid-template-columns: repeat(2, minmax(0, 1fr));
      gap: 20px;
      margin-top: 24px;
    }
    .example-card {
      border: 1px solid #d8e0ea;
      border-radius: 7px;
      background: #f8fafc;
      padding: 12px;
      margin-bottom: 10px;
    }
    .example-meta {
      display: flex;
      justify-content: space-between;
      gap: 10px;
      color: #52627a;
      font-size: 13px;
      margin-bottom: 8px;
    }
    .empty {
      border: 1px dashed #cbd5e1;
      border-radius: 7px;
      padding: 28px;
      text-align: center;
      color: #52627a;
    }
    @media (max-width: 720px) {
      .app-shell, .login-shell { width: min(100% - 24px, 1180px); }
      .card-head, .status-row, .button-row, .form-row {
        align-items: stretch;
        flex-direction: column;
      }
      .tabs, .tabs button, .button-row button { width: 100%; }
      .example-grid { grid-template-columns: 1fr; }
      h1 { font-size: 25px; }
    }
  `;
}

/**
 * Returns client-side JavaScript for the app.
 *
 * @return {string} JavaScript.
 */
function clientScript(): string {
  return `
    const STORAGE_KEY = "notePolisherStyleExamples";
    let examples = [];

    function loadExamples() {
      try {
        const stored = localStorage.getItem(STORAGE_KEY);
        examples = stored ? JSON.parse(stored) : [];
        if (!Array.isArray(examples)) examples = [];
      } catch {
        examples = [];
      }
    }

    function saveExamples() {
      localStorage.setItem(STORAGE_KEY, JSON.stringify(examples));
      renderExamples();
      updateExampleCounts();
    }

    function newestExamples(type) {
      return examples
        .filter((example) => example.type === type)
        .sort((a, b) => new Date(b.createdAt) - new Date(a.createdAt))
        .slice(0, 5)
        .map((example) => example.text);
    }

    function updateExampleCounts() {
      for (const type of ["hpi", "ap"]) {
        const count = newestExamples(type).length;
        const label = type === "hpi" ? "HPI" : "A/P";
        document.getElementById(type + "ExampleCount").textContent =
          "Uses the newest " + count + " saved " + label + " style " +
          (count === 1 ? "example." : "examples.");
      }
    }

    function switchTab(name) {
      for (const panel of document.querySelectorAll(".tab-panel")) {
        panel.classList.add("hidden");
      }
      document.getElementById(name + "Panel").classList.remove("hidden");
      for (const tab of document.querySelectorAll(".tab")) {
        tab.classList.toggle("active", tab.dataset.tab === name);
      }
    }

    async function polish(type) {
      const rough = document.getElementById(type + "Rough").value;
      const error = document.getElementById(type + "Error");
      const output = document.getElementById(type + "Output");
      const button = document.querySelector('[data-action="polish"][data-type="' + type + '"]');
      error.textContent = "";
      button.disabled = true;
      button.textContent = "Polishing...";
      try {
        const response = await fetch("${BASE_PATH}/api/polish", {
          method: "POST",
          headers: {"Content-Type": "application/json"},
          body: JSON.stringify({
            type,
            roughText: rough,
            styleExamples: newestExamples(type)
          })
        });
        const data = await response.json();
        if (!response.ok) throw new Error(data.error || "Unable to polish.");
        output.textContent = data.polishedText || "";
      } catch (err) {
        error.textContent = err.message || "Unable to polish.";
      } finally {
        button.disabled = false;
        button.textContent = type === "hpi" ? "Polish HPI" : "Polish A/P";
      }
    }

    async function copyOutput(type) {
      const text = document.getElementById(type + "Output").innerText.trim();
      if (!text || text === "Polished output will appear here.") return;
      await navigator.clipboard.writeText(text);
    }

    function clearSection(type) {
      document.getElementById(type + "Rough").value = "";
      document.getElementById(type + "Output").innerHTML =
        '<span class="placeholder">Polished output will appear here.</span>';
      document.getElementById(type + "Error").textContent = "";
    }

    function renderExamples() {
      for (const type of ["hpi", "ap"]) {
        const list = document.getElementById(type + "Examples");
        const matching = examples.filter((example) => example.type === type);
        if (matching.length === 0) {
          list.innerHTML = '<div class="empty">No examples saved yet.</div>';
          continue;
        }
        list.innerHTML = matching.map((example) => {
          const date = new Date(example.createdAt).toLocaleString();
          return '<article class="example-card">' +
            '<div class="example-meta"><span>' + escapeHtml(date) + '</span>' +
            '<button class="secondary small" data-delete="' + example.id + '">Delete</button></div>' +
            '<p>' + escapeHtml(example.text) + '</p></article>';
        }).join("");
      }
    }

    function escapeHtml(value) {
      return String(value)
        .replaceAll("&", "&amp;")
        .replaceAll("<", "&lt;")
        .replaceAll(">", "&gt;")
        .replaceAll('"', "&quot;");
    }

    function saveExample() {
      const text = document.getElementById("exampleText").value.trim();
      const type = document.getElementById("exampleType").value;
      const message = document.getElementById("libraryMessage");
      if (!text) {
        message.className = "error";
        message.textContent = "Paste an example note before saving.";
        return;
      }
      examples.unshift({
        id: crypto.randomUUID(),
        type,
        text,
        createdAt: new Date().toISOString()
      });
      document.getElementById("exampleText").value = "";
      message.className = "message";
      message.textContent = "Saved to Style Library.";
      saveExamples();
    }

    function exportBackup() {
      const blob = new Blob([JSON.stringify({
        exportedAt: new Date().toISOString(),
        storageKey: STORAGE_KEY,
        examples
      }, null, 2)], {type: "application/json"});
      const url = URL.createObjectURL(blob);
      const link = document.createElement("a");
      link.href = url;
      link.download = "note-polisher-style-library-" +
        new Date().toISOString().slice(0, 10) + ".json";
      link.click();
      URL.revokeObjectURL(url);
    }

    async function restoreBackup(file) {
      if (!file) return;
      const message = document.getElementById("libraryMessage");
      try {
        const parsed = JSON.parse(await file.text());
        const incoming = Array.isArray(parsed) ? parsed : parsed.examples;
        if (!Array.isArray(incoming)) throw new Error("Invalid backup file.");
        const existing = new Set(examples.map((example) => example.id));
        const cleaned = incoming.filter((item) =>
          item && (item.type === "hpi" || item.type === "ap") &&
          typeof item.text === "string" && typeof item.createdAt === "string"
        ).map((item) => ({
          id: item.id || crypto.randomUUID(),
          type: item.type,
          text: item.text,
          createdAt: item.createdAt
        }));
        examples = [
          ...cleaned.filter((example) => !existing.has(example.id)),
          ...examples
        ].sort((a, b) => new Date(b.createdAt) - new Date(a.createdAt));
        message.className = "message";
        message.textContent = "Restored " + cleaned.length + " style example(s).";
        saveExamples();
      } catch (err) {
        message.className = "error";
        message.textContent = err.message || "Could not restore that backup.";
      }
    }

    async function loadSettings() {
      const response = await fetch("${BASE_PATH}/api/settings");
      if (!response.ok) return;
      const data = await response.json();
      document.getElementById("modelChip").textContent = "Model: " + data.model;
      document.getElementById("settingsModel").textContent = data.model;
    }

    document.addEventListener("click", async (event) => {
      const target = event.target;
      if (target.matches(".tab")) switchTab(target.dataset.tab);
      if (target.dataset.action === "polish") polish(target.dataset.type);
      if (target.dataset.action === "copy") copyOutput(target.dataset.type);
      if (target.dataset.action === "clear") clearSection(target.dataset.type);
      if (target.dataset.delete) {
        examples = examples.filter((example) => example.id !== target.dataset.delete);
        saveExamples();
      }
    });

    document.getElementById("saveExampleButton").addEventListener("click", saveExample);
    document.getElementById("exportButton").addEventListener("click", exportBackup);
    document.getElementById("restoreButton").addEventListener("click", () =>
      document.getElementById("restoreInput").click()
    );
    document.getElementById("restoreInput").addEventListener("change", (event) =>
      restoreBackup(event.target.files[0])
    );
    document.getElementById("clearExamplesButton").addEventListener("click", () => {
      examples = [];
      saveExamples();
    });
    document.getElementById("logoutButton").addEventListener("click", async () => {
      await fetch("${BASE_PATH}/logout", {method: "POST"});
      window.location.href = "${BASE_PATH}";
    });

    loadExamples();
    renderExamples();
    updateExampleCounts();
    loadSettings();
  `;
}
