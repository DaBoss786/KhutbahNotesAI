const test = require("node:test");
const assert = require("node:assert/strict");

const {
  extractYouTubeVideoIdFromUrl,
  parsePublishCliArgs,
} = require("../lib/publishMasjidTranscriptExports.js");

test("extractYouTubeVideoIdFromUrl parses watch URLs", () => {
  assert.equal(
    extractYouTubeVideoIdFromUrl("https://www.youtube.com/watch?v=RGTx9bLDRx0"),
    "RGTx9bLDRx0"
  );
  assert.equal(
    extractYouTubeVideoIdFromUrl("https://www.youtube.com/watch?v=UglfXtzgz08&pp=0gcJCdoKAYcqIYzv"),
    "UglfXtzgz08"
  );
});

test("parsePublishCliArgs accepts filters and mode", () => {
  const parsed = parsePublishCliArgs([
    "--input-dir",
    "/tmp/transcripts",
    "--mode",
    "publish",
    "--masjid-id",
    "epic_masjid",
    "--project-id",
    "khutbah-notes-ai",
    "--max-file-age-hours",
    "24",
    "--created-by-uid",
    "codex_local_automation",
  ]);

  assert.equal(parsed.inputDir, "/tmp/transcripts");
  assert.equal(parsed.mode, "publish");
  assert.equal(parsed.projectId, "khutbah-notes-ai");
  assert.equal(parsed.maxFileAgeHours, 24);
  assert.equal(parsed.createdByUid, "codex_local_automation");
  assert.deepEqual(
    parsed.targets.map((target) => target.masjidId),
    ["epic_masjid"]
  );
});
