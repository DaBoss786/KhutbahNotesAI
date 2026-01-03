import * as admin from "firebase-admin";
import type {UserData} from "./quota";

const RATE_LIMIT_BUCKET_MS = 60 * 1000;
const RATE_LIMIT_IN_FLIGHT_TTL_MS = 20 * 60 * 1000;

export type RateLimitTier = "free" | "premium";
export type RateLimitConfig = {
  perMinute: number;
  maxInFlight: number;
};
export type RateLimitFields = {
  minuteKey: string;
  minuteCount: string;
  inFlight: string;
  inFlightUpdatedAt: string;
};
export type RateLimitReason = "per_minute" | "in_flight";
export type RateLimitDecision = {
  allowed: boolean;
  reason?: RateLimitReason;
  retryAfterMs?: number;
  updates?: Record<string, unknown>;
};

export const TRANSCRIBE_RATE_LIMIT_FIELDS: RateLimitFields = {
  minuteKey: "transcribeMinuteKey",
  minuteCount: "transcribeMinuteCount",
  inFlight: "transcribeInFlight",
  inFlightUpdatedAt: "transcribeInFlightUpdatedAt",
};
export const SUMMARY_RATE_LIMIT_FIELDS: RateLimitFields = {
  minuteKey: "summaryMinuteKey",
  minuteCount: "summaryMinuteCount",
  inFlight: "summaryInFlight",
  inFlightUpdatedAt: "summaryInFlightUpdatedAt",
};
export const TRANSLATION_RATE_LIMIT_FIELDS: RateLimitFields = {
  minuteKey: "translationMinuteKey",
  minuteCount: "translationMinuteCount",
  inFlight: "translationInFlight",
  inFlightUpdatedAt: "translationInFlightUpdatedAt",
};

export const TRANSCRIBE_RATE_LIMITS: Record<RateLimitTier, RateLimitConfig> = {
  free: {perMinute: 2, maxInFlight: 2},
  premium: {perMinute: 3, maxInFlight: 3},
};
export const SUMMARY_RATE_LIMITS: Record<RateLimitTier, RateLimitConfig> = {
  free: {perMinute: 2, maxInFlight: 2},
  premium: {perMinute: 3, maxInFlight: 3},
};
export const TRANSLATION_RATE_LIMITS: Record<RateLimitTier, RateLimitConfig> = {
  free: {perMinute: 2, maxInFlight: 2},
  premium: {perMinute: 3, maxInFlight: 3},
};

/**
 * Error thrown when a rate limit is exceeded.
 */
export class RateLimitError extends Error {
  reason: RateLimitReason;
  retryAfterMs?: number;

  /**
   * @param {string} message Human-readable error.
   * @param {RateLimitReason} reason Machine-readable reason.
   * @param {number=} retryAfterMs Optional retry delay in millis.
   */
  constructor(message: string, reason: RateLimitReason, retryAfterMs?: number) {
    super(message);
    this.name = "RateLimitError";
    this.reason = reason;
    this.retryAfterMs = retryAfterMs;
  }
}

/**
 * Resolve the rate-limit tier from user data.
 *
 * @param {UserData|null} userData User snapshot data.
 * @return {RateLimitTier} Tier name.
 */
export function getRateLimitTier(userData: UserData | null): RateLimitTier {
  return userData?.plan === "premium" ? "premium" : "free";
}

/**
 * Build a UTC minute bucket key.
 *
 * @param {Date} now Current time.
 * @return {string} UTC minute key.
 */
export function getUtcMinuteKey(now: Date): string {
  const year = now.getUTCFullYear();
  const month = `${now.getUTCMonth() + 1}`.padStart(2, "0");
  const day = `${now.getUTCDate()}`.padStart(2, "0");
  const hour = `${now.getUTCHours()}`.padStart(2, "0");
  const minute = `${now.getUTCMinutes()}`.padStart(2, "0");
  return `${year}${month}${day}${hour}${minute}`;
}

/**
 * Clamp a numeric counter to a non-negative integer.
 *
 * @param {unknown} value Input value.
 * @return {number} Non-negative integer.
 */
export function clampCounter(value: unknown): number {
  if (typeof value !== "number" || !Number.isFinite(value)) {
    return 0;
  }
  return Math.max(0, Math.floor(value));
}

/**
 * Convert a timestamp-like value to epoch millis.
 *
 * @param {unknown} value Candidate timestamp.
 * @return {number|null} Millis value or null when unavailable.
 */
function getTimestampMillis(value: unknown): number | null {
  if (!value) {
    return null;
  }

  if (value instanceof admin.firestore.Timestamp) {
    return value.toMillis();
  }

  if (value instanceof Date) {
    return value.getTime();
  }

  if (typeof (value as {toMillis?: () => number}).toMillis === "function") {
    return (value as {toMillis: () => number}).toMillis();
  }

  return null;
}

/**
 * Evaluate and return the next rate-limit decision.
 *
 * @param {UserData} userData User snapshot data.
 * @param {Date} now Current time.
 * @param {RateLimitConfig} config Rate-limit thresholds.
 * @param {RateLimitFields} fields Field names to read/write.
 * @return {RateLimitDecision} Decision outcome.
 */
export function evaluateRateLimit(
  userData: UserData,
  now: Date,
  config: RateLimitConfig,
  fields: RateLimitFields
): RateLimitDecision {
  const nowMs = now.getTime();
  const minuteKey = getUtcMinuteKey(now);
  const record = userData as Record<string, unknown>;
  const storedMinuteKey =
    typeof record[fields.minuteKey] === "string" ?
      (record[fields.minuteKey] as string) :
      "";
  let minuteCount = clampCounter(record[fields.minuteCount]);
  let inFlight = clampCounter(record[fields.inFlight]);
  const inFlightUpdatedAtMs = getTimestampMillis(
    record[fields.inFlightUpdatedAt]
  );

  if (
    inFlight > 0 &&
    (!inFlightUpdatedAtMs ||
      nowMs - inFlightUpdatedAtMs > RATE_LIMIT_IN_FLIGHT_TTL_MS)
  ) {
    inFlight = 0;
  }

  if (storedMinuteKey !== minuteKey) {
    minuteCount = 0;
  }

  if (inFlight >= config.maxInFlight) {
    return {allowed: false, reason: "in_flight"};
  }

  if (minuteCount >= config.perMinute) {
    const retryAfterMs =
      RATE_LIMIT_BUCKET_MS - (nowMs % RATE_LIMIT_BUCKET_MS);
    return {allowed: false, reason: "per_minute", retryAfterMs};
  }

  return {
    allowed: true,
    updates: {
      [fields.minuteKey]: minuteKey,
      [fields.minuteCount]: minuteCount + 1,
      [fields.inFlight]: inFlight + 1,
      [fields.inFlightUpdatedAt]: admin.firestore.Timestamp.fromDate(now),
    },
  };
}
