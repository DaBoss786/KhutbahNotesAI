const test = require("node:test");
const assert = require("node:assert/strict");
const admin = require("firebase-admin");

const {
  TRANSCRIBE_RATE_LIMIT_FIELDS,
  evaluateRateLimit,
  getRateLimitTier,
} = require("../lib/rateLimit.js");

test("evaluateRateLimit resets minute bucket on new minute", () => {
  const now = new Date("2024-01-01T00:01:30Z");
  const userData = {
    transcribeMinuteKey: "202401010000",
    transcribeMinuteCount: 2,
    transcribeInFlight: 0,
  };

  const decision = evaluateRateLimit(
    userData,
    now,
    {perMinute: 2, maxInFlight: 2},
    TRANSCRIBE_RATE_LIMIT_FIELDS
  );

  assert.equal(decision.allowed, true);
  assert.equal(decision.updates.transcribeMinuteKey, "202401010001");
  assert.equal(decision.updates.transcribeMinuteCount, 1);
  assert.equal(decision.updates.transcribeInFlight, 1);
  assert.ok(
    decision.updates.transcribeInFlightUpdatedAt instanceof
      admin.firestore.Timestamp
  );
});

test("evaluateRateLimit blocks when in-flight limit reached", () => {
  const now = new Date("2024-01-01T00:00:10Z");
  const userData = {
    transcribeInFlight: 2,
    transcribeInFlightUpdatedAt: admin.firestore.Timestamp.fromDate(
      new Date("2024-01-01T00:00:00Z")
    ),
  };

  const decision = evaluateRateLimit(
    userData,
    now,
    {perMinute: 2, maxInFlight: 2},
    TRANSCRIBE_RATE_LIMIT_FIELDS
  );

  assert.equal(decision.allowed, false);
  assert.equal(decision.reason, "in_flight");
});

test("evaluateRateLimit clears stale in-flight counters", () => {
  const now = new Date("2024-01-01T00:30:00Z");
  const userData = {
    transcribeInFlight: 2,
    transcribeInFlightUpdatedAt: admin.firestore.Timestamp.fromDate(
      new Date("2024-01-01T00:00:00Z")
    ),
  };

  const decision = evaluateRateLimit(
    userData,
    now,
    {perMinute: 2, maxInFlight: 2},
    TRANSCRIBE_RATE_LIMIT_FIELDS
  );

  assert.equal(decision.allowed, true);
  assert.equal(decision.updates.transcribeInFlight, 1);
});

test("evaluateRateLimit blocks when per-minute cap reached", () => {
  const now = new Date("2024-01-01T00:02:10Z");
  const userData = {
    transcribeMinuteKey: "202401010002",
    transcribeMinuteCount: 2,
    transcribeInFlight: 0,
  };

  const decision = evaluateRateLimit(
    userData,
    now,
    {perMinute: 2, maxInFlight: 2},
    TRANSCRIBE_RATE_LIMIT_FIELDS
  );

  assert.equal(decision.allowed, false);
  assert.equal(decision.reason, "per_minute");
  assert.ok(
    typeof decision.retryAfterMs === "number" &&
      decision.retryAfterMs > 0 &&
      decision.retryAfterMs <= 60 * 1000
  );
});

test("getRateLimitTier uses premium when plan is premium", () => {
  assert.equal(getRateLimitTier({plan: "premium"}), "premium");
  assert.equal(getRateLimitTier({plan: "free"}), "free");
  assert.equal(getRateLimitTier(null), "free");
});
