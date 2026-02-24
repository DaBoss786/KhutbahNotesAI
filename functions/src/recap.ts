import {createHash} from "crypto";

export const RECAP_PROMPT_VERSION = "v1";
export const RECAP_TEXT_MODEL = "gpt-5-mini";
export const RECAP_TTS_MODEL = "gpt-4o-mini-tts";
export const RECAP_DEFAULT_LENGTH_SEC = 180;
export const RECAP_MIN_LENGTH_SEC = 180;
export const RECAP_MAX_LENGTH_SEC = 180;
export const RECAP_LOCK_TTL_MS = 15 * 60 * 1000;

export const RECAP_VOICES = ["male", "female"] as const;
export const RECAP_STYLES = [
  "concise",
  "reflective",
  "action_focused",
] as const;
export type RecapVoice = typeof RECAP_VOICES[number];
export type RecapStyle = typeof RECAP_STYLES[number];
export const RECAP_FIXED_STYLE: RecapStyle = "concise";

export type RecapVariantInput = {
  voice: RecapVoice;
  style: RecapStyle;
  language: string;
  targetLengthSec: number;
  promptVersion?: string;
};

export type NormalizedRecapRequest = {
  voice: RecapVoice;
  style: RecapStyle;
  language: string;
  targetLengthSec: number;
  promptVersion: string;
  variantKey: string;
};

export type RecapAction = "cache_hit" | "in_progress" | "regenerate";

export type RecapStateLite = {
  status?: unknown;
  transcriptHash?: unknown;
  updatedAtMs?: number | null;
  lockExpiresAtMs?: number | null;
};

/**
 * Clamp requested recap duration to a safe, product-capped range.
 *
 * @param {unknown} value Raw seconds input.
 * @return {number} Clamped seconds.
 */
export function clampRecapLengthSec(value: unknown): number {
  const numeric =
    typeof value === "number" && Number.isFinite(value) ?
      Math.floor(value) :
      RECAP_DEFAULT_LENGTH_SEC;
  return Math.min(
    RECAP_MAX_LENGTH_SEC,
    Math.max(RECAP_MIN_LENGTH_SEC, numeric)
  );
}

/**
 * Decide if creating a new recap variant should be blocked.
 *
 * @param {unknown} existingVariantCount Existing variant count for lecture.
 * @param {unknown} maxUniqueVariants Max allowed unique variants.
 * @return {boolean} True when cap is reached.
 */
export function hasReachedUniqueVariantCap(
  existingVariantCount: unknown,
  maxUniqueVariants: unknown
): boolean {
  const count =
    typeof existingVariantCount === "number" &&
      Number.isFinite(existingVariantCount) ?
      Math.max(0, Math.floor(existingVariantCount)) :
      0;
  const cap =
    typeof maxUniqueVariants === "number" &&
      Number.isFinite(maxUniqueVariants) ?
      Math.max(1, Math.floor(maxUniqueVariants)) :
      1;
  return count >= cap;
}

/**
 * Normalize a recap request payload for deterministic caching.
 *
 * @param {unknown} rawPayload Input payload from HTTP body/query.
 * @return {NormalizedRecapRequest} Validated request options.
 */
export function normalizeRecapRequest(
  rawPayload: unknown
): NormalizedRecapRequest {
  const payload =
    rawPayload && typeof rawPayload === "object" && !Array.isArray(rawPayload) ?
      (rawPayload as Record<string, unknown>) :
      {};

  const voiceCandidate =
    typeof payload.voice === "string" ? payload.voice.trim().toLowerCase() : "";
  const languageCandidate =
    typeof payload.language === "string" ?
      payload.language.trim().toLowerCase() :
      "en";
  const promptVersionCandidate =
    typeof payload.promptVersion === "string" &&
      payload.promptVersion.trim().length > 0 ?
      payload.promptVersion.trim() :
      RECAP_PROMPT_VERSION;

  if (!RECAP_VOICES.includes(voiceCandidate as RecapVoice)) {
    throw new Error("Invalid voice. Allowed: male, female.");
  }
  if (!/^[a-z]{2}(?:-[a-z0-9]{2,8})?$/.test(languageCandidate)) {
    throw new Error("Invalid language code.");
  }

  const targetLengthSec = clampRecapLengthSec(payload.targetLengthSec);
  const voice = voiceCandidate as RecapVoice;
  const style = RECAP_FIXED_STYLE;
  const language = languageCandidate;
  const promptVersion = promptVersionCandidate;
  const variantKey = buildRecapVariantKey({
    voice,
    style,
    language,
    targetLengthSec,
    promptVersion,
  });

  return {
    voice,
    style,
    language,
    targetLengthSec,
    promptVersion,
    variantKey,
  };
}

/**
 * Build a deterministic recap variant cache key.
 *
 * @param {RecapVariantInput} input Variant dimensions.
 * @return {string} Stable hashed key.
 */
export function buildRecapVariantKey(input: RecapVariantInput): string {
  const promptVersion = input.promptVersion ?? RECAP_PROMPT_VERSION;
  const canonical = [
    `voice=${input.voice}`,
    `style=${input.style}`,
    `language=${input.language}`,
    `targetLengthSec=${clampRecapLengthSec(input.targetLengthSec)}`,
    `promptVersion=${promptVersion}`,
  ].join("|");
  return createHash("sha256").update(canonical).digest("hex").slice(0, 24);
}

/**
 * Compute transcript hash for cache invalidation.
 *
 * @param {string} transcript Transcript text.
 * @return {string} SHA-256 hash hex.
 */
export function computeTranscriptHash(transcript: string): string {
  return createHash("sha256").update(transcript).digest("hex");
}

/**
 * Derive an approximate spoken-word budget for recap generation.
 *
 * @param {number} targetLengthSec Target spoken duration in seconds.
 * @return {number} Word budget.
 */
export function targetWordBudget(targetLengthSec: number): number {
  const clamped = clampRecapLengthSec(targetLengthSec);
  // ~130 WPM conversational pace => about 2.16 words/sec.
  const estimated = Math.floor(clamped * 2.16);
  return Math.min(420, Math.max(120, estimated));
}

/**
 * Decide whether to reuse cache, wait in-progress, or regenerate.
 *
 * @param {RecapStateLite | null} existing Existing recap metadata snapshot.
 * @param {string} transcriptHash Current transcript hash.
 * @param {number} nowMs Current timestamp in millis.
 * @return {RecapAction} Next action.
 */
export function decideRecapAction(
  existing: RecapStateLite | null,
  transcriptHash: string,
  nowMs: number
): RecapAction {
  if (!existing) {
    return "regenerate";
  }

  const status = typeof existing.status === "string" ?
    existing.status.toLowerCase() :
    "";
  const hashMatches =
    typeof existing.transcriptHash === "string" &&
    existing.transcriptHash === transcriptHash;

  if (status === "ready" && hashMatches) {
    return "cache_hit";
  }

  if ((status === "generating" || status === "processing") && hashMatches) {
    const lockExpiresAtMs =
      typeof existing.lockExpiresAtMs === "number" &&
        Number.isFinite(existing.lockExpiresAtMs) ?
        existing.lockExpiresAtMs :
        null;
    const updatedAtMs =
      typeof existing.updatedAtMs === "number" &&
        Number.isFinite(existing.updatedAtMs) ?
        existing.updatedAtMs :
        null;
    const staleByExpiry =
      lockExpiresAtMs !== null && lockExpiresAtMs <= nowMs;
    const staleByUpdate =
      updatedAtMs !== null && nowMs - updatedAtMs > RECAP_LOCK_TTL_MS;
    if (!staleByExpiry && !staleByUpdate) {
      return "in_progress";
    }
  }

  return "regenerate";
}

/**
 * Normalize transcript text by collapsing whitespace.
 *
 * @param {string} transcript Raw transcript text.
 * @return {string} Normalized text.
 */
export function normalizeTranscriptText(transcript: string): string {
  return transcript.replace(/\r\n/g, "\n").replace(/\s+/g, " ").trim();
}
