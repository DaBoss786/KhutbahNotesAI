import {readFile, readdir, stat} from "fs/promises";
import * as os from "os";
import * as path from "path";
import {
  inferSpeakerFromTitle,
  parseTranscriptDocument,
  slugifyChannelUrl,
} from "./youtubeStreamTranscriptExport";
import {
  WEEKLY_MASJID_INGESTION_TARGETS,
  type WeeklyMasjidIngestionTarget,
} from "./weeklyMasjidTargets";

export type TranscriptPublishMode = "dry-run" | "publish";

export type TranscriptPublishOptions = {
  inputDir: string;
  mode: TranscriptPublishMode;
  projectId: string;
  maxFileAgeHours: number;
  createdByUid: string;
  firebaseToolsConfigPath: string;
  targets: WeeklyMasjidIngestionTarget[];
};

export type TranscriptPublishTargetResult = {
  masjidId: string;
  channelUrl: string;
  channelSlug: string;
  decision: "would-queue" | "queued" | "would-dedupe" | "deduped" | "skipped";
  reason: string | null;
  sourceFilePath: string | null;
  youtubeVideoId: string | null;
  youtubeUrl: string | null;
  title: string | null;
  transcriptCharCount: number;
  existingStatus: string | null;
};

export type TranscriptPublishSummary = {
  mode: TranscriptPublishMode;
  projectId: string;
  targetCount: number;
  queueCount: number;
  dedupeCount: number;
  skippedCount: number;
  results: TranscriptPublishTargetResult[];
};

type FirebaseToolsConfig = {
  user?: {
    aud?: string;
  };
  tokens?: {
    access_token?: string;
    expires_at?: number;
    refresh_token?: string;
  };
};

type TranscriptExportCandidate = {
  filePath: string;
  fetchedAt: Date;
  title: string;
  youtubeUrl: string;
  youtubeVideoId: string;
  speaker: string | null;
  publishedAt: Date | null;
  transcriptText: string;
};

type FirestoreValue =
  | {stringValue: string}
  | {timestampValue: string};

type FirestoreFields = Record<string, FirestoreValue>;

const FIREBASE_CLI_CLIENT_ID =
  "563584335869-fgrhgmd47bqnekij5i8b5pr03ho849e6.apps.googleusercontent.com";
const FIREBASE_CLI_CLIENT_SECRET = "j9iVZfS8kkCEFUPaAeJV0sAi";
const FIREBASE_TOOLS_CONFIG_PATH = path.join(
  os.homedir(),
  ".config",
  "configstore",
  "firebase-tools.json"
);
const ACCESS_TOKEN_REFRESH_BUFFER_MS = 5 * 60 * 1000;
const DEFAULT_MAX_FILE_AGE_HOURS = 36;
const DEFAULT_CREATED_BY_UID = "codex_local_automation";

/**
 * Expand a leading tilde in a filesystem path.
 *
 * @param {string} value Input path.
 * @return {string} Expanded path.
 */
function expandHome(value: string): string {
  return value.startsWith("~/") ?
    path.join(os.homedir(), value.slice(2)) :
    value;
}

/**
 * Parse a YouTube video ID from a URL.
 *
 * @param {string} value Candidate YouTube URL.
 * @return {string | null} YouTube video ID.
 */
export function extractYouTubeVideoIdFromUrl(value: string): string | null {
  try {
    const parsed = new URL(value);
    const directId = parsed.searchParams.get("v");
    if (directId) {
      return directId.trim() || null;
    }

    const segments = parsed.pathname.split("/").filter(Boolean);
    if (
      segments.length >= 2 &&
      ["embed", "shorts", "live"].includes(segments[0])
    ) {
      return segments[1].trim() || null;
    }
  } catch {
    return null;
  }
  return null;
}

/**
 * Determine whether a parsed date is valid.
 *
 * @param {Date | null} value Candidate date.
 * @return {Date | null} Valid date or null.
 */
function normalizeDate(value: Date | null): Date | null {
  return value && !Number.isNaN(value.getTime()) ? value : null;
}

/**
 * Read and parse a transcript export file.
 *
 * @param {string} filePath Transcript file path.
 * @param {Date} fallbackFetchedAt File timestamp fallback.
 * @return {Promise<TranscriptExportCandidate | null>} Parsed transcript export.
 */
async function readTranscriptExportCandidate(
  filePath: string,
  fallbackFetchedAt: Date
): Promise<TranscriptExportCandidate | null> {
  const contents = await readFile(filePath, "utf8");
  const parsed = parseTranscriptDocument(contents);
  const title = parsed.metadata.title.trim();
  const youtubeUrl = parsed.metadata.videoUrl.trim();
  const youtubeVideoId = extractYouTubeVideoIdFromUrl(youtubeUrl);
  const transcriptText = parsed.transcriptText.trim();
  const fetchedAt =
    normalizeDate(parsed.metadata.fetchedAt) ?? fallbackFetchedAt;
  const publishedAt = normalizeDate(parsed.metadata.publishedAt);
  const speaker =
    parsed.metadata.speaker?.trim() ||
    inferSpeakerFromTitle(title) ||
    null;

  if (!title || !youtubeUrl || !youtubeVideoId || !transcriptText) {
    return null;
  }

  return {
    filePath,
    fetchedAt,
    title,
    youtubeUrl,
    youtubeVideoId,
    speaker,
    publishedAt,
    transcriptText,
  };
}

/**
 * Load the newest recent transcript export for a mapped channel.
 *
 * @param {string} inputDir Base transcript directory.
 * @param {WeeklyMasjidIngestionTarget} target Channel target.
 * @param {number} maxFileAgeHours Freshness limit.
 * @return {Promise<TranscriptExportCandidate | null>} Transcript export.
 */
async function loadLatestTranscriptExportForTarget(
  inputDir: string,
  target: WeeklyMasjidIngestionTarget,
  maxFileAgeHours: number
): Promise<TranscriptExportCandidate | null> {
  const channelSlug = slugifyChannelUrl(target.channelUrl);
  const channelDir = path.join(inputDir, channelSlug);
  let filenames: string[] = [];
  try {
    filenames = await readdir(channelDir);
  } catch {
    return null;
  }

  const candidates = await Promise.all(
    filenames
      .filter((filename) => filename.endsWith(".txt"))
      .map(async (filename) => {
        const filePath = path.join(channelDir, filename);
        try {
          const fileStat = await stat(filePath);
          const parsed = await readTranscriptExportCandidate(
            filePath,
            fileStat.mtime
          );
          if (!parsed) {
            return null;
          }
          return {
            parsed,
            fetchedAtMs: parsed.fetchedAt.getTime(),
          };
        } catch {
          return null;
        }
      })
  );

  const maxAgeMs = maxFileAgeHours * 60 * 60 * 1000;
  const now = Date.now();
  const eligible = candidates
    .filter(
      (
        item
      ): item is {
        parsed: TranscriptExportCandidate;
        fetchedAtMs: number;
      } => item !== null
    )
    .filter((item) => now - item.fetchedAtMs <= maxAgeMs)
    .sort((lhs, rhs) => rhs.fetchedAtMs - lhs.fetchedAtMs);

  return eligible[0]?.parsed ?? null;
}

/**
 * Read the local Firebase CLI config used for project deployments.
 *
 * @param {string} configPath Firebase CLI config path.
 * @return {Promise<FirebaseToolsConfig>} Parsed config.
 */
async function readFirebaseToolsConfig(
  configPath: string
): Promise<FirebaseToolsConfig> {
  const raw = await readFile(configPath, "utf8");
  return JSON.parse(raw) as FirebaseToolsConfig;
}

/**
 * Refresh a Google OAuth access token from the Firebase CLI refresh token.
 *
 * @param {string} refreshToken Firebase CLI refresh token.
 * @param {string} clientId OAuth client ID.
 * @return {Promise<string>} Google access token.
 */
async function refreshGoogleAccessToken(
  refreshToken: string,
  clientId: string
): Promise<string> {
  const response = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: {
      "Content-Type": "application/x-www-form-urlencoded",
    },
    body: new URLSearchParams({
      grant_type: "refresh_token",
      refresh_token: refreshToken,
      client_id: clientId,
      client_secret: FIREBASE_CLI_CLIENT_SECRET,
    }),
  });
  if (!response.ok) {
    const message = await response.text();
    throw new Error(`Failed to refresh Google access token: ${message}`);
  }

  const parsed = await response.json() as {access_token?: string};
  if (!parsed.access_token) {
    throw new Error("Google access token refresh returned no access token.");
  }
  return parsed.access_token;
}

/**
 * Resolve a valid Google access token from the local Firebase CLI login.
 *
 * @param {string} configPath Firebase CLI config path.
 * @return {Promise<string>} Google access token.
 */
async function resolveGoogleAccessToken(configPath: string): Promise<string> {
  const config = await readFirebaseToolsConfig(configPath);
  const accessToken = config.tokens?.access_token?.trim() ?? "";
  const expiresAt = config.tokens?.expires_at ?? 0;
  if (
    accessToken &&
    expiresAt > Date.now() + ACCESS_TOKEN_REFRESH_BUFFER_MS
  ) {
    return accessToken;
  }

  const refreshToken = config.tokens?.refresh_token?.trim() ?? "";
  if (!refreshToken) {
    throw new Error("Missing Firebase CLI refresh token.");
  }

  const clientId = config.user?.aud?.trim() || FIREBASE_CLI_CLIENT_ID;
  return refreshGoogleAccessToken(refreshToken, clientId);
}

/**
 * Encode a document path for the Firestore REST API.
 *
 * @param {string} documentPath Firestore document path.
 * @return {string} URL-safe document path.
 */
function encodeDocumentPath(documentPath: string): string {
  return documentPath
    .split("/")
    .map((segment) => encodeURIComponent(segment))
    .join("/");
}

/**
 * Encode JS values into Firestore REST field values.
 *
 * @param {Record<string, unknown>} input Plain object fields.
 * @return {FirestoreFields} Firestore REST fields.
 */
function encodeFirestoreFields(
  input: Record<string, unknown>
): FirestoreFields {
  const fields: FirestoreFields = {};
  for (const [key, value] of Object.entries(input)) {
    if (typeof value === "string") {
      fields[key] = {stringValue: value};
      continue;
    }
    if (value instanceof Date) {
      fields[key] = {timestampValue: value.toISOString()};
    }
  }
  return fields;
}

/**
 * Read a Firestore document via REST.
 *
 * @param {string} projectId Firebase project ID.
 * @param {string} accessToken Google access token.
 * @param {string} documentPath Firestore document path.
 * @return {Promise<Record<string, unknown> | null>} Document payload.
 */
async function getFirestoreDocument(
  projectId: string,
  accessToken: string,
  documentPath: string
): Promise<Record<string, unknown> | null> {
  const url =
    `https://firestore.googleapis.com/v1/projects/${projectId}/databases/` +
    `(default)/documents/${encodeDocumentPath(documentPath)}`;
  const response = await fetch(url, {
    method: "GET",
    headers: {
      Authorization: `Bearer ${accessToken}`,
    },
  });
  if (response.status === 404) {
    return null;
  }
  if (!response.ok) {
    const message = await response.text();
    throw new Error(`Firestore GET failed for ${documentPath}: ${message}`);
  }
  return await response.json() as Record<string, unknown>;
}

/**
 * Extract a string field from a Firestore REST document response.
 *
 * @param {Record<string, unknown> | null} document Firestore document.
 * @param {string} fieldName Field name.
 * @return {string | null} String value or null.
 */
function getFirestoreStringField(
  document: Record<string, unknown> | null,
  fieldName: string
): string | null {
  const fields = document?.fields as Record<string, unknown> | undefined;
  const field = fields?.[fieldName] as Record<string, unknown> | undefined;
  return typeof field?.stringValue === "string" ? field.stringValue : null;
}

/**
 * Patch a Firestore document via REST with the provided field mask.
 *
 * @param {string} projectId Firebase project ID.
 * @param {string} accessToken Google access token.
 * @param {string} documentPath Firestore document path.
 * @param {Record<string, unknown>} fields Field values to patch.
 * @return {Promise<void>} Resolves when the patch completes.
 */
async function patchFirestoreDocument(
  projectId: string,
  accessToken: string,
  documentPath: string,
  fields: Record<string, unknown>
): Promise<void> {
  const updateMask = Object.keys(fields)
    .map(
      (fieldName) =>
        `updateMask.fieldPaths=${encodeURIComponent(fieldName)}`
    )
    .join("&");
  const url =
    `https://firestore.googleapis.com/v1/projects/${projectId}/databases/` +
    `(default)/documents/${encodeDocumentPath(documentPath)}?${updateMask}`;
  const response = await fetch(url, {
    method: "PATCH",
    headers: {
      "Authorization": `Bearer ${accessToken}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      fields: encodeFirestoreFields(fields),
    }),
  });
  if (!response.ok) {
    const message = await response.text();
    throw new Error(`Firestore PATCH failed for ${documentPath}: ${message}`);
  }
}

/**
 * Publish transcript exports into Firestore queue documents.
 *
 * @param {TranscriptPublishOptions} options Publish options.
 * @return {Promise<TranscriptPublishSummary>} Publish summary.
 */
export async function publishMasjidTranscriptExports(
  options: TranscriptPublishOptions
): Promise<TranscriptPublishSummary> {
  const accessToken = await resolveGoogleAccessToken(
    options.firebaseToolsConfigPath
  );
  const results: TranscriptPublishTargetResult[] = [];
  let queueCount = 0;
  let dedupeCount = 0;
  let skippedCount = 0;

  for (const target of options.targets) {
    const channelSlug = slugifyChannelUrl(target.channelUrl);
    const transcriptExport = await loadLatestTranscriptExportForTarget(
      options.inputDir,
      target,
      options.maxFileAgeHours
    );
    if (!transcriptExport) {
      skippedCount++;
      results.push({
        masjidId: target.masjidId,
        channelUrl: target.channelUrl,
        channelSlug,
        decision: "skipped",
        reason: "No recent transcript export file was found.",
        sourceFilePath: null,
        youtubeVideoId: null,
        youtubeUrl: null,
        title: null,
        transcriptCharCount: 0,
        existingStatus: null,
      });
      continue;
    }

    const masjidPath = `masjids/${target.masjidId}`;
    const masjidDoc = await getFirestoreDocument(
      options.projectId,
      accessToken,
      masjidPath
    );
    if (!masjidDoc) {
      skippedCount++;
      results.push({
        masjidId: target.masjidId,
        channelUrl: target.channelUrl,
        channelSlug,
        decision: "skipped",
        reason: "Masjid document not found.",
        sourceFilePath: transcriptExport.filePath,
        youtubeVideoId: transcriptExport.youtubeVideoId,
        youtubeUrl: transcriptExport.youtubeUrl,
        title: transcriptExport.title,
        transcriptCharCount: transcriptExport.transcriptText.length,
        existingStatus: null,
      });
      continue;
    }

    const khutbahPath =
      `masjids/${target.masjidId}/khutbahs/${transcriptExport.youtubeVideoId}`;
    const existingDoc = await getFirestoreDocument(
      options.projectId,
      accessToken,
      khutbahPath
    );
    const existingStatus = getFirestoreStringField(existingDoc, "status");
    if (
      existingStatus &&
      ["queued", "processing", "ready"].includes(existingStatus)
    ) {
      dedupeCount++;
      results.push({
        masjidId: target.masjidId,
        channelUrl: target.channelUrl,
        channelSlug,
        decision: options.mode === "publish" ? "deduped" : "would-dedupe",
        reason: `Existing khutbah already ${existingStatus}.`,
        sourceFilePath: transcriptExport.filePath,
        youtubeVideoId: transcriptExport.youtubeVideoId,
        youtubeUrl: transcriptExport.youtubeUrl,
        title: transcriptExport.title,
        transcriptCharCount: transcriptExport.transcriptText.length,
        existingStatus,
      });
      continue;
    }

    if (options.mode === "publish") {
      const now = new Date();
      await patchFirestoreDocument(
        options.projectId,
        accessToken,
        khutbahPath,
        {
          youtubeUrl: transcriptExport.youtubeUrl,
          youtubeVideoId: transcriptExport.youtubeVideoId,
          title: transcriptExport.title,
          status: "queued",
          createdByUid: options.createdByUid,
          createdAt: now,
          updatedAt: now,
          manualTranscript: transcriptExport.transcriptText,
          ...(transcriptExport.speaker ?
            {speaker: transcriptExport.speaker} :
            {}),
          ...(transcriptExport.publishedAt ?
            {date: transcriptExport.publishedAt} :
            {}),
        }
      );
      await patchFirestoreDocument(
        options.projectId,
        accessToken,
        masjidPath,
        {
          updatedAt: now,
          lastUpdatedAt: now,
        }
      );
    }

    queueCount++;
    results.push({
      masjidId: target.masjidId,
      channelUrl: target.channelUrl,
      channelSlug,
      decision: options.mode === "publish" ? "queued" : "would-queue",
      reason: null,
      sourceFilePath: transcriptExport.filePath,
      youtubeVideoId: transcriptExport.youtubeVideoId,
      youtubeUrl: transcriptExport.youtubeUrl,
      title: transcriptExport.title,
      transcriptCharCount: transcriptExport.transcriptText.length,
      existingStatus,
    });
  }

  return {
    mode: options.mode,
    projectId: options.projectId,
    targetCount: options.targets.length,
    queueCount,
    dedupeCount,
    skippedCount,
    results,
  };
}

/**
 * Build a readable summary for transcript publish runs.
 *
 * @param {TranscriptPublishSummary} summary Publish summary.
 * @return {string} Human-readable summary.
 */
export function formatTranscriptPublishSummary(
  summary: TranscriptPublishSummary
): string {
  const lines = [
    `Mode: ${summary.mode}`,
    `Project: ${summary.projectId}`,
    `Targets: ${summary.targetCount}`,
    `Queued: ${summary.queueCount}`,
    `Deduped: ${summary.dedupeCount}`,
    `Skipped: ${summary.skippedCount}`,
    "",
    "Results:",
  ];

  for (const result of summary.results) {
    const suffix = result.reason ? ` (${result.reason})` : "";
    lines.push(
      `- ${result.channelSlug}: ${result.decision}${suffix}`
    );
    if (result.title) {
      lines.push(`  title: ${result.title}`);
    }
    if (result.youtubeUrl) {
      lines.push(`  video: ${result.youtubeUrl}`);
    }
    if (result.sourceFilePath) {
      lines.push(`  file: ${result.sourceFilePath}`);
    }
  }

  return `${lines.join("\n")}\n`;
}

/**
 * Parse publish CLI args.
 *
 * @param {string[]} args Raw argv entries after the script path.
 * @return {TranscriptPublishOptions} Parsed options.
 */
export function parsePublishCliArgs(
  args: string[]
): TranscriptPublishOptions {
  const values = new Map<string, string[]>();
  for (let i = 0; i < args.length; i++) {
    const arg = args[i];
    if (!arg.startsWith("--")) {
      throw new Error(`Unexpected argument: ${arg}`);
    }
    const key = arg.slice(2);
    const value = args[i + 1];
    if (!value || value.startsWith("--")) {
      throw new Error(`Missing value for --${key}`);
    }
    values.set(key, [...(values.get(key) ?? []), value]);
    i++;
  }

  const inputDir = values.get("input-dir")?.[0]?.trim() ?? "";
  const projectId = values.get("project-id")?.[0]?.trim() ?? "khutbah-notes-ai";
  const mode = values.get("mode")?.[0]?.trim() ?? "dry-run";
  const maxFileAgeHoursRaw = values.get("max-file-age-hours")?.[0]?.trim() ??
    String(DEFAULT_MAX_FILE_AGE_HOURS);
  const createdByUid =
    values.get("created-by-uid")?.[0]?.trim() ?? DEFAULT_CREATED_BY_UID;
  const firebaseToolsConfigPath = expandHome(
    values.get("firebase-tools-config")?.[0]?.trim() ??
      FIREBASE_TOOLS_CONFIG_PATH
  );
  const masjidIds = new Set(
    (values.get("masjid-id") ?? [])
      .map((value) => value.trim())
      .filter((value) => value.length > 0)
  );
  const channelUrls = new Set(
    (values.get("channel-url") ?? [])
      .map((value) => value.trim())
      .filter((value) => value.length > 0)
  );
  const maxFileAgeHours = Number.parseInt(maxFileAgeHoursRaw, 10);

  if (!inputDir) {
    throw new Error("Missing required --input-dir value.");
  }
  if (mode !== "dry-run" && mode !== "publish") {
    throw new Error("--mode must be either dry-run or publish.");
  }
  if (!Number.isInteger(maxFileAgeHours) || maxFileAgeHours <= 0) {
    throw new Error("--max-file-age-hours must be a positive integer.");
  }

  const targets = WEEKLY_MASJID_INGESTION_TARGETS.filter((target) => {
    const matchesMasjid = masjidIds.size === 0 ||
      masjidIds.has(target.masjidId);
    const matchesChannel = channelUrls.size === 0 ||
      channelUrls.has(target.channelUrl);
    return matchesMasjid && matchesChannel;
  });
  if (targets.length === 0) {
    throw new Error("No weekly masjid targets matched the provided filters.");
  }

  return {
    inputDir,
    mode,
    projectId,
    maxFileAgeHours,
    createdByUid,
    firebaseToolsConfigPath,
    targets,
  };
}

/**
 * Execute the local transcript publish CLI.
 *
 * @return {Promise<void>} Resolves when complete.
 */
export async function main(): Promise<void> {
  const options = parsePublishCliArgs(process.argv.slice(2));
  const summary = await publishMasjidTranscriptExports(options);
  process.stdout.write(formatTranscriptPublishSummary(summary));
}

if (require.main === module) {
  main().catch((error: unknown) => {
    const message = error instanceof Error ? error.message : String(error);
    process.stderr.write(`${message}\n`);
    process.exitCode = 1;
  });
}
