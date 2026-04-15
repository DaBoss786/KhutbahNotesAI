const test = require("node:test");
const assert = require("node:assert/strict");

const {
  formatWeeklyWorkflowSummary,
  parseWeeklyWorkflowCliArgs,
} = require("../lib/runWeeklyMasjidWorkflow.js");

test("parseWeeklyWorkflowCliArgs applies defaults and filters targets", () => {
  const parsed = parseWeeklyWorkflowCliArgs([
    "--output-dir",
    "/tmp/transcripts",
    "--publish-mode",
    "dry-run",
    "--masjid-id",
    "epic_masjid",
  ]);

  assert.equal(parsed.outputDir, "/tmp/transcripts");
  assert.equal(parsed.publishMode, "dry-run");
  assert.equal(parsed.projectId, "khutbah-notes-ai");
  assert.equal(parsed.limit, 1);
  assert.equal(parsed.maxFileAgeHours, 36);
  assert.deepEqual(parsed.titleKeywords, [
    "friday",
    "khutbah",
    "khutba",
    "jumma",
    "jummah",
    "jumu'ah",
    "sermon",
  ]);
  assert.deepEqual(
    parsed.targets.map((target) => target.masjidId),
    ["epic_masjid"]
  );
});

test("formatWeeklyWorkflowSummary joins export and publish sections", () => {
  const summary = formatWeeklyWorkflowSummary(
    "Mode: scheduled\nSaved: 1\n",
    "Mode: dry-run\nQueued: 1\n"
  );

  assert.equal(
    summary,
    "Export:\nMode: scheduled\nSaved: 1\n\nPublish:\nMode: dry-run\nQueued: 1\n"
  );
});
