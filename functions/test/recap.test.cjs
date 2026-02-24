const test = require("node:test");
const assert = require("node:assert/strict");

const {
  RECAP_LOCK_TTL_MS,
  buildRecapVariantKey,
  clampRecapLengthSec,
  computeTranscriptHash,
  decideRecapAction,
  hasReachedUniqueVariantCap,
  normalizeRecapRequest,
} = require("../lib/recap.js");

test("buildRecapVariantKey is deterministic and prompt-versioned", () => {
  const base = {
    voice: "male",
    style: "concise",
    language: "en",
    targetLengthSec: 180,
    promptVersion: "v1",
  };
  const keyA = buildRecapVariantKey(base);
  const keyB = buildRecapVariantKey(base);
  const keyC = buildRecapVariantKey({...base, promptVersion: "v2"});

  assert.equal(keyA, keyB);
  assert.notEqual(keyA, keyC);
  assert.equal(keyA.length, 24);
});

test("clampRecapLengthSec enforces product limits", () => {
  assert.equal(clampRecapLengthSec(5), 180);
  assert.equal(clampRecapLengthSec(999), 180);
  assert.equal(clampRecapLengthSec(120), 180);
  assert.equal(clampRecapLengthSec("bad"), 180);
});

test("normalizeRecapRequest enforces concise style and computes variant key", () => {
  const parsed = normalizeRecapRequest({
    voice: "female",
    style: "action_focused",
    language: "en",
    targetLengthSec: 150,
  });

  assert.equal(parsed.voice, "female");
  assert.equal(parsed.style, "concise");
  assert.equal(parsed.language, "en");
  assert.equal(parsed.targetLengthSec, 180);
  assert.ok(parsed.variantKey);
});

test("normalizeRecapRequest ignores client length differences", () => {
  const short = normalizeRecapRequest({
    voice: "male",
    style: "concise",
    language: "en",
    targetLengthSec: 60,
  });
  const long = normalizeRecapRequest({
    voice: "male",
    style: "concise",
    language: "en",
    targetLengthSec: 180,
  });

  assert.equal(short.targetLengthSec, 180);
  assert.equal(long.targetLengthSec, 180);
  assert.equal(short.variantKey, long.variantKey);
});

test("hasReachedUniqueVariantCap returns expected decisions", () => {
  assert.equal(hasReachedUniqueVariantCap(0, 2), false);
  assert.equal(hasReachedUniqueVariantCap(1, 2), false);
  assert.equal(hasReachedUniqueVariantCap(2, 2), true);
  assert.equal(hasReachedUniqueVariantCap(5, 4), true);
});

test("normalizeRecapRequest rejects invalid voice", () => {
  assert.throws(
    () =>
      normalizeRecapRequest({
        voice: "robot",
        style: "concise",
      }),
    /Invalid voice/
  );
});

test("normalizeRecapRequest ignores invalid style and forces concise", () => {
  const parsed = normalizeRecapRequest({
    voice: "male",
    style: "rambling",
  });
  assert.equal(parsed.style, "concise");
});

test("decideRecapAction returns cache_hit for ready matching hash", () => {
  const hash = computeTranscriptHash("hello world");
  const action = decideRecapAction(
    {
      status: "ready",
      transcriptHash: hash,
      updatedAtMs: Date.now(),
      lockExpiresAtMs: Date.now() + RECAP_LOCK_TTL_MS,
    },
    hash,
    Date.now()
  );
  assert.equal(action, "cache_hit");
});

test("decideRecapAction returns regenerate when transcript hash changed", () => {
  const oldHash = computeTranscriptHash("old transcript");
  const newHash = computeTranscriptHash("new transcript");
  const action = decideRecapAction(
    {
      status: "ready",
      transcriptHash: oldHash,
      updatedAtMs: Date.now(),
      lockExpiresAtMs: Date.now() + RECAP_LOCK_TTL_MS,
    },
    newHash,
    Date.now()
  );
  assert.equal(action, "regenerate");
});

test("decideRecapAction returns in_progress for active matching generation", () => {
  const now = Date.now();
  const hash = computeTranscriptHash("same transcript");
  const action = decideRecapAction(
    {
      status: "generating",
      transcriptHash: hash,
      updatedAtMs: now,
      lockExpiresAtMs: now + 60_000,
    },
    hash,
    now + 1_000
  );
  assert.equal(action, "in_progress");
});

test("decideRecapAction treats stale generation lock as regenerate", () => {
  const now = Date.now();
  const hash = computeTranscriptHash("same transcript");
  const action = decideRecapAction(
    {
      status: "processing",
      transcriptHash: hash,
      updatedAtMs: now - RECAP_LOCK_TTL_MS - 1,
      lockExpiresAtMs: now - 1,
    },
    hash,
    now
  );
  assert.equal(action, "regenerate");
});

test("simulated concurrent requests produce one regenerate then in_progress", () => {
  const now = Date.now();
  const transcriptHash = computeTranscriptHash("text");

  const first = decideRecapAction(null, transcriptHash, now);
  assert.equal(first, "regenerate");

  const simulatedStateAfterFirstLock = {
    status: "generating",
    transcriptHash,
    updatedAtMs: now,
    lockExpiresAtMs: now + 30_000,
  };
  const second = decideRecapAction(
    simulatedStateAfterFirstLock,
    transcriptHash,
    now + 10
  );
  assert.equal(second, "in_progress");
});
