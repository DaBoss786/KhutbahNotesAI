import {mkdir, readFile, writeFile} from "fs/promises";
import * as os from "os";
import * as path from "path";
import {
  exportRecentStreamTranscriptsForChannels,
  formatMultiChannelRunSummary,
} from "./youtubeStreamTranscriptExport";
import {
  formatTranscriptPublishSummary,
  publishMasjidTranscriptExports,
  type TranscriptPublishMode,
} from "./publishMasjidTranscriptExports";
import {
  DEFAULT_WEEKLY_MASJID_TITLE_KEYWORDS,
  WEEKLY_MASJID_INGESTION_TARGETS,
  type WeeklyMasjidIngestionTarget,
} from "./weeklyMasjidTargets";

type WeeklyWorkflowOptions = {
  outputDir: string;
  projectId: string;
  publishMode: TranscriptPublishMode;
  maxFileAgeHours: number;
  createdByUid: string;
  firebaseToolsConfigPath: string;
  limit: number;
  titleKeywords: string[];
  targets: WeeklyMasjidIngestionTarget[];
  scheduleGuard: ScheduleGuardOptions | null;
};

type ScheduleGuardOptions = {
  stateFilePath: string;
  scheduledWeekday: number;
  scheduledHour: number;
  scheduledMinute: number;
  catchUpHours: number;
  force: boolean;
};

type ScheduleGuardState = {
  lastCompletedScheduledAt?: string;
  updatedAt?: string;
};

export type ScheduleGuardDecision =
  | {
    shouldRun: true;
    scheduledAt: Date;
    reason: string;
  }
  | {
    shouldRun: false;
    scheduledAt: Date;
    reason: string;
  };

const FIREBASE_TOOLS_CONFIG_PATH = path.join(
  os.homedir(),
  ".config",
  "configstore",
  "firebase-tools.json"
);
const DEFAULT_CREATED_BY_UID = "codex_local_automation";
const DEFAULT_STATE_FILE_PATH = path.join(
  os.homedir(),
  ".local",
  "state",
  "khutbah-notes-ai",
  "weekly-masjid-publishing.json"
);

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
 * Parse CLI options for the weekly workflow.
 *
 * @param {string[]} args Raw argv entries after the script path.
 * @return {WeeklyWorkflowOptions} Parsed options.
 */
export function parseWeeklyWorkflowCliArgs(
  args: string[]
): WeeklyWorkflowOptions {
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

  const outputDir = values.get("output-dir")?.[0]?.trim() ?? "";
  const projectId = values.get("project-id")?.[0]?.trim() ?? "khutbah-notes-ai";
  const publishMode =
    values.get("publish-mode")?.[0]?.trim() ?? "publish";
  const maxFileAgeHoursRaw = values.get("max-file-age-hours")?.[0]?.trim() ??
    "36";
  const createdByUid =
    values.get("created-by-uid")?.[0]?.trim() ?? DEFAULT_CREATED_BY_UID;
  const firebaseToolsConfigPath = expandHome(
    values.get("firebase-tools-config")?.[0]?.trim() ??
      FIREBASE_TOOLS_CONFIG_PATH
  );
  const limitRaw = values.get("limit")?.[0]?.trim() ?? "1";
  const stateFilePath = expandHome(
    values.get("state-file")?.[0]?.trim() ?? DEFAULT_STATE_FILE_PATH
  );
  const scheduledWeekdayRaw =
    values.get("scheduled-weekday")?.[0]?.trim() ?? "6";
  const scheduledHourRaw =
    values.get("scheduled-hour")?.[0]?.trim() ?? "20";
  const scheduledMinuteRaw =
    values.get("scheduled-minute")?.[0]?.trim() ?? "40";
  const catchUpHoursRaw =
    values.get("catch-up-hours")?.[0]?.trim() ?? "72";
  const force = (values.get("force")?.[0]?.trim() ?? "") === "true";
  const useScheduleGuard = (values.get("use-schedule-guard")?.[0]?.trim() ??
    "false") === "true";
  const titleKeywords = (values.get("title-keyword") ?? [])
    .map((value) => value.trim())
    .filter((value) => value.length > 0);
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
  const limit = Number.parseInt(limitRaw, 10);
  const scheduledWeekday = Number.parseInt(scheduledWeekdayRaw, 10);
  const scheduledHour = Number.parseInt(scheduledHourRaw, 10);
  const scheduledMinute = Number.parseInt(scheduledMinuteRaw, 10);
  const catchUpHours = Number.parseInt(catchUpHoursRaw, 10);

  if (!outputDir) {
    throw new Error("Missing required --output-dir value.");
  }
  if (publishMode !== "dry-run" && publishMode !== "publish") {
    throw new Error("--publish-mode must be either dry-run or publish.");
  }
  if (!Number.isInteger(maxFileAgeHours) || maxFileAgeHours <= 0) {
    throw new Error("--max-file-age-hours must be a positive integer.");
  }
  if (!Number.isInteger(limit) || limit <= 0) {
    throw new Error("--limit must be a positive integer.");
  }
  if (
    !Number.isInteger(scheduledWeekday) ||
    scheduledWeekday < 0 ||
    scheduledWeekday > 6
  ) {
    throw new Error("--scheduled-weekday must be an integer from 0 to 6.");
  }
  if (
    !Number.isInteger(scheduledHour) ||
    scheduledHour < 0 ||
    scheduledHour > 23
  ) {
    throw new Error("--scheduled-hour must be an integer from 0 to 23.");
  }
  if (
    !Number.isInteger(scheduledMinute) ||
    scheduledMinute < 0 ||
    scheduledMinute > 59
  ) {
    throw new Error("--scheduled-minute must be an integer from 0 to 59.");
  }
  if (!Number.isInteger(catchUpHours) || catchUpHours <= 0) {
    throw new Error("--catch-up-hours must be a positive integer.");
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
    outputDir,
    projectId,
    publishMode,
    maxFileAgeHours,
    createdByUid,
    firebaseToolsConfigPath,
    limit,
    titleKeywords:
      titleKeywords.length > 0 ?
        titleKeywords :
        DEFAULT_WEEKLY_MASJID_TITLE_KEYWORDS,
    targets,
    scheduleGuard: useScheduleGuard ?
      {
        stateFilePath,
        scheduledWeekday,
        scheduledHour,
        scheduledMinute,
        catchUpHours,
        force,
      } :
      null,
  };
}

/**
 * Compute the most recent scheduled slot at or before now.
 *
 * @param {Date} now Current local time.
 * @param {number} weekday Scheduled weekday, Sunday=0.
 * @param {number} hour Scheduled hour in local time.
 * @param {number} minute Scheduled minute in local time.
 * @return {Date} Most recent scheduled slot.
 */
export function getMostRecentScheduledAt(
  now: Date,
  weekday: number,
  hour: number,
  minute: number
): Date {
  const scheduledAt = new Date(now);
  scheduledAt.setHours(hour, minute, 0, 0);
  const dayDelta = (now.getDay() - weekday + 7) % 7;
  scheduledAt.setDate(scheduledAt.getDate() - dayDelta);
  if (dayDelta === 0 && now.getTime() < scheduledAt.getTime()) {
    scheduledAt.setDate(scheduledAt.getDate() - 7);
  }
  return scheduledAt;
}

/**
 * Read the persisted schedule guard state from disk.
 *
 * @param {string} stateFilePath State file path.
 * @return {Promise<ScheduleGuardState>} Parsed state.
 */
async function readScheduleGuardState(
  stateFilePath: string
): Promise<ScheduleGuardState> {
  try {
    const raw = await readFile(stateFilePath, "utf8");
    return JSON.parse(raw) as ScheduleGuardState;
  } catch {
    return {};
  }
}

/**
 * Persist the completed scheduled slot to disk.
 *
 * @param {string} stateFilePath State file path.
 * @param {Date} scheduledAt Completed scheduled slot.
 * @return {Promise<void>} Resolves when the state is written.
 */
async function writeScheduleGuardState(
  stateFilePath: string,
  scheduledAt: Date
): Promise<void> {
  await mkdir(path.dirname(stateFilePath), {recursive: true});
  await writeFile(
    stateFilePath,
    JSON.stringify(
      {
        lastCompletedScheduledAt: scheduledAt.toISOString(),
        updatedAt: new Date().toISOString(),
      },
      null,
      2
    ) + "\n",
    "utf8"
  );
}

/**
 * Decide whether the guarded weekly workflow should run now.
 *
 * @param {ScheduleGuardOptions} guard Schedule guard options.
 * @param {Date} now Current local time.
 * @param {ScheduleGuardState} state Persisted state.
 * @return {ScheduleGuardDecision} Guard decision.
 */
export function evaluateScheduleGuard(
  guard: ScheduleGuardOptions,
  now: Date,
  state: ScheduleGuardState = {}
): ScheduleGuardDecision {
  const scheduledAt = getMostRecentScheduledAt(
    now,
    guard.scheduledWeekday,
    guard.scheduledHour,
    guard.scheduledMinute
  );
  if (guard.force) {
    return {
      shouldRun: true,
      scheduledAt,
      reason: "Forced run requested.",
    };
  }

  const ageMs = now.getTime() - scheduledAt.getTime();
  const catchUpMs = guard.catchUpHours * 60 * 60 * 1000;
  if (ageMs > catchUpMs) {
    return {
      shouldRun: false,
      scheduledAt,
      reason: "Outside the configured catch-up window.",
    };
  }

  if (state.lastCompletedScheduledAt === scheduledAt.toISOString()) {
    return {
      shouldRun: false,
      scheduledAt,
      reason: "Scheduled slot already completed.",
    };
  }

  return {
    shouldRun: true,
    scheduledAt,
    reason: "Scheduled slot is due.",
  };
}

/**
 * Build a combined summary for the weekly export/publish workflow.
 *
 * @param {string} exportSummary Multi-channel export summary.
 * @param {string} publishSummary Publish summary.
 * @return {string} Human-readable workflow summary.
 */
export function formatWeeklyWorkflowSummary(
  exportSummary: string,
  publishSummary: string
): string {
  return [
    "Export:",
    exportSummary.trim(),
    "",
    "Publish:",
    publishSummary.trim(),
    "",
  ].join("\n");
}

/**
 * Build a concise summary for skipped guarded runs.
 *
 * @param {ScheduleGuardDecision} decision Guard decision.
 * @return {string} Human-readable skip summary.
 */
export function formatScheduleGuardSkipSummary(
  decision: Extract<ScheduleGuardDecision, {shouldRun: false}>
): string {
  return [
    "Skipped:",
    decision.reason,
    `Scheduled slot: ${decision.scheduledAt.toISOString()}`,
    "",
  ].join("\n");
}

/**
 * Execute the weekly transcript export and publish workflow.
 *
 * @return {Promise<void>} Resolves when complete.
 */
export async function main(): Promise<void> {
  const options = parseWeeklyWorkflowCliArgs(process.argv.slice(2));
  let completedScheduledAt: Date | null = null;
  if (options.scheduleGuard) {
    const state = await readScheduleGuardState(
      options.scheduleGuard.stateFilePath
    );
    const decision = evaluateScheduleGuard(
      options.scheduleGuard,
      new Date(),
      state
    );
    if (!decision.shouldRun) {
      process.stdout.write(formatScheduleGuardSkipSummary(decision));
      return;
    }
    completedScheduledAt = decision.scheduledAt;
  }

  const exportResult = await exportRecentStreamTranscriptsForChannels({
    channelUrls: options.targets.map((target) => target.channelUrl),
    limit: options.limit,
    outputDir: options.outputDir,
    mode: "scheduled",
    titleKeywords: options.titleKeywords,
    useChannelSubdirectories: true,
  });
  const publishResult = await publishMasjidTranscriptExports({
    inputDir: options.outputDir,
    mode: options.publishMode,
    projectId: options.projectId,
    maxFileAgeHours: options.maxFileAgeHours,
    createdByUid: options.createdByUid,
    firebaseToolsConfigPath: options.firebaseToolsConfigPath,
    targets: options.targets,
  });

  process.stdout.write(
    formatWeeklyWorkflowSummary(
      formatMultiChannelRunSummary(exportResult),
      formatTranscriptPublishSummary(publishResult)
    )
  );
  if (options.scheduleGuard) {
    await writeScheduleGuardState(
      options.scheduleGuard.stateFilePath,
      completedScheduledAt ??
        getMostRecentScheduledAt(
          new Date(),
          options.scheduleGuard.scheduledWeekday,
          options.scheduleGuard.scheduledHour,
          options.scheduleGuard.scheduledMinute
        )
    );
  }
}

if (require.main === module) {
  main().catch((error: unknown) => {
    const message = error instanceof Error ? error.message : String(error);
    process.stderr.write(`${message}\n`);
    process.exitCode = 1;
  });
}
