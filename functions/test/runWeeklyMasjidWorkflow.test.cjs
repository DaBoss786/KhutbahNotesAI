const test = require("node:test");
const assert = require("node:assert/strict");

const {
  evaluateScheduleGuard,
  formatWeeklyWorkflowSummary,
  formatScheduleGuardSkipSummary,
  getMostRecentScheduledAt,
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
  assert.equal(parsed.scheduleGuard, null);
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

test("getMostRecentScheduledAt returns prior week before slot time", () => {
  const now = new Date(2026, 3, 18, 18, 0, 0, 0);
  const scheduledAt = getMostRecentScheduledAt(now, 6, 20, 40);

  assert.equal(scheduledAt.getFullYear(), 2026);
  assert.equal(scheduledAt.getMonth(), 3);
  assert.equal(scheduledAt.getDate(), 11);
  assert.equal(scheduledAt.getHours(), 20);
  assert.equal(scheduledAt.getMinutes(), 40);
});

test("evaluateScheduleGuard runs when current slot is due", () => {
  const now = new Date(2026, 3, 18, 21, 0, 0, 0);
  const decision = evaluateScheduleGuard({
    stateFilePath: "/tmp/state.json",
    scheduledWeekday: 6,
    scheduledHour: 20,
    scheduledMinute: 40,
    catchUpHours: 72,
    force: false,
  }, now, {});

  assert.equal(decision.shouldRun, true);
  assert.equal(decision.reason, "Scheduled slot is due.");
});

test("evaluateScheduleGuard skips completed slot", () => {
  const now = new Date(2026, 3, 18, 21, 0, 0, 0);
  const slot = getMostRecentScheduledAt(now, 6, 20, 40);
  const decision = evaluateScheduleGuard({
    stateFilePath: "/tmp/state.json",
    scheduledWeekday: 6,
    scheduledHour: 20,
    scheduledMinute: 40,
    catchUpHours: 72,
    force: false,
  }, now, {
    lastCompletedScheduledAt: slot.toISOString(),
  });

  assert.equal(decision.shouldRun, false);
  assert.equal(decision.reason, "Scheduled slot already completed.");
  assert.equal(
    formatScheduleGuardSkipSummary(decision),
    `Skipped:\nScheduled slot already completed.\nScheduled slot: ${slot.toISOString()}\n`
  );
});

test("evaluateScheduleGuard skips stale missed slots", () => {
  const now = new Date(2026, 3, 21, 21, 0, 0, 0);
  const decision = evaluateScheduleGuard({
    stateFilePath: "/tmp/state.json",
    scheduledWeekday: 6,
    scheduledHour: 20,
    scheduledMinute: 40,
    catchUpHours: 24,
    force: false,
  }, now, {});

  assert.equal(decision.shouldRun, false);
  assert.equal(decision.reason, "Outside the configured catch-up window.");
});
