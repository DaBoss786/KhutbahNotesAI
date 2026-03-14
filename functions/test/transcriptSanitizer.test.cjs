const test = require("node:test");
const assert = require("node:assert/strict");

const {
  isPromptEcho,
  sanitizeChunkTranscript,
  stripPromptEchoLeakage,
} = require("../lib/transcriptSanitizer.js");

const PROMPT =
  "Audio may include multiple languages. Transcribe each segment " +
  "in its original language as spoken. Do not translate.";

test("stripPromptEchoLeakage removes repeated exact prompt", () => {
  const leaked = `${PROMPT} ${PROMPT} ${PROMPT}`;
  const cleaned = stripPromptEchoLeakage(leaked, PROMPT);
  assert.equal(cleaned, "");
});

test("stripPromptEchoLeakage removes prompt variants with casing and punctuation", () => {
  const leaked =
    "AUDIO may include multiple languages!!! " +
    "TRANSCRIBE each segment in its original language as spoken... DO not translate??";
  const cleaned = stripPromptEchoLeakage(leaked, PROMPT);
  assert.equal(cleaned, "");
});

test("sanitizeChunkTranscript preserves real content while removing leaked prompt", () => {
  const mixed =
    "The imam emphasized taqwa today. " +
    `${PROMPT} ` +
    "He also advised sincere repentance.";
  const sanitized = sanitizeChunkTranscript(mixed, PROMPT);

  assert.equal(
    sanitized.cleanedText,
    "The imam emphasized taqwa today. He also advised sincere repentance."
  );
  assert.equal(sanitized.removed, true);
  assert.equal(sanitized.hardEcho, false);
});

test("sanitizeChunkTranscript flags pure prompt echo as hard echo", () => {
  const sanitized = sanitizeChunkTranscript(PROMPT, PROMPT);
  assert.equal(sanitized.cleanedText, "");
  assert.equal(sanitized.removed, true);
  assert.equal(sanitized.hardEcho, true);
});

test("sanitizeChunkTranscript leaves legitimate transcript text unchanged", () => {
  const text =
    "In Surah Al-Asr, the khutbah focused on patience, truth, and good deeds.";
  const sanitized = sanitizeChunkTranscript(text, PROMPT);
  assert.equal(sanitized.cleanedText, text);
  assert.equal(sanitized.removed, false);
  assert.equal(sanitized.hardEcho, false);
});

test("stripPromptEchoLeakage removes single embedded prompt without erasing context", () => {
  const text =
    "Opening reminder. " +
    `${PROMPT} ` +
    "Closing dua and action points.";
  const cleaned = stripPromptEchoLeakage(text, PROMPT);
  assert.equal(cleaned, "Opening reminder. Closing dua and action points.");
});

test("isPromptEcho detects expanded prompt repetition via includes check", () => {
  const expanded =
    `${PROMPT} ` +
    "Transcribe each segment in its original language as spoken. " +
    "Transcribe each segment in its original language as spoken.";
  assert.equal(isPromptEcho(expanded, PROMPT), true);
});
