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
};

const FIREBASE_TOOLS_CONFIG_PATH = path.join(
  os.homedir(),
  ".config",
  "configstore",
  "firebase-tools.json"
);
const DEFAULT_CREATED_BY_UID = "codex_local_automation";

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
 * Execute the weekly transcript export and publish workflow.
 *
 * @return {Promise<void>} Resolves when complete.
 */
export async function main(): Promise<void> {
  const options = parseWeeklyWorkflowCliArgs(process.argv.slice(2));
  const exportResult = await exportRecentStreamTranscriptsForChannels({
    channelUrls: options.targets.map((target) => target.channelUrl),
    limit: options.limit,
    outputDir: options.outputDir,
    mode: "scheduled",
    titleKeywords: options.titleKeywords,
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
}

if (require.main === module) {
  main().catch((error: unknown) => {
    const message = error instanceof Error ? error.message : String(error);
    process.stderr.write(`${message}\n`);
    process.exitCode = 1;
  });
}
