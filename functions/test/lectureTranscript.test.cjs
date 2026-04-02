const test = require("node:test");
const assert = require("node:assert/strict");

const {
  normalizeLectureTranscriptForStorage,
  resolveLectureTranscript,
} = require("../lib/lectureTranscript.js");

test("normalizeLectureTranscriptForStorage collapses formatted whitespace", () => {
  assert.equal(
    normalizeLectureTranscriptForStorage(" First line.\n\nSecond\tline.  "),
    "First line. Second line."
  );
});

test("resolveLectureTranscript prefers raw transcript for summary flow", () => {
  const resolved = resolveLectureTranscript(
    {
      transcript: "Raw transcript",
      transcriptFormatted: "Formatted transcript",
    },
    {prefer: "raw"}
  );

  assert.deepEqual(resolved, {
    text: "Raw transcript",
    source: "lecture.transcript",
    repairTranscript: null,
  });
});

test("resolveLectureTranscript falls back to formatted transcript and repairs raw", () => {
  const resolved = resolveLectureTranscript(
    {
      transcript: "   ",
      transcriptFormatted: "First line.\n\nSecond line.",
    },
    {prefer: "raw"}
  );

  assert.deepEqual(resolved, {
    text: "First line.\n\nSecond line.",
    source: "lecture.transcriptFormatted",
    repairTranscript: "First line. Second line.",
  });
});

test("resolveLectureTranscript preserves formatted-first behavior for recap flow", () => {
  const resolved = resolveLectureTranscript({
    transcript: "Raw transcript",
    transcriptFormatted: "Formatted transcript",
  });

  assert.deepEqual(resolved, {
    text: "Formatted transcript",
    source: "lecture.transcriptFormatted",
    repairTranscript: null,
  });
});

test("resolveLectureTranscript returns null when both lecture transcript fields are empty", () => {
  assert.equal(
    resolveLectureTranscript({
      transcript: " \n ",
      transcriptFormatted: "",
    }, {prefer: "raw"}),
    null
  );
});
