import {
  exportRecentStreamTranscriptsForChannels,
  formatMultiChannelRunSummary,
  type ExportMode,
} from "./youtubeStreamTranscriptExport";

type CliOptions = {
  channelUrls: string[];
  limit: number;
  outputDir: string;
  mode: ExportMode;
  titleKeywords: string[];
};

/**
 * Parse CLI options from argv.
 *
 * @param {string[]} args Raw argv entries after the script path.
 * @return {CliOptions} Parsed options.
 */
export function parseCliArgs(args: string[]): CliOptions {
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

  const channelUrls = (values.get("channel-url") ?? [])
    .map((value) => value.trim())
    .filter((value) => value.length > 0);
  const outputDir = values.get("output-dir")?.[0]?.trim() ?? "";
  const limitRaw = values.get("limit")?.[0]?.trim() ?? "3";
  const modeRaw = values.get("mode")?.[0]?.trim() ?? "dry-run";
  const titleKeywords = (values.get("title-keyword") ?? [])
    .map((value) => value.trim())
    .filter((value) => value.length > 0);
  const limit = Number.parseInt(limitRaw, 10);

  if (channelUrls.length === 0) {
    throw new Error("Missing at least one required --channel-url value.");
  }
  if (!outputDir) {
    throw new Error("Missing required --output-dir value.");
  }
  if (!Number.isInteger(limit) || limit <= 0) {
    throw new Error("--limit must be a positive integer.");
  }
  if (modeRaw !== "dry-run" && modeRaw !== "scheduled") {
    throw new Error("--mode must be either dry-run or scheduled.");
  }

  return {
    channelUrls,
    outputDir,
    limit,
    mode: modeRaw,
    titleKeywords,
  };
}

/**
 * Execute the CLI command.
 *
 * @return {Promise<void>} Resolves when complete.
 */
export async function main(): Promise<void> {
  const options = parseCliArgs(process.argv.slice(2));
  const result = await exportRecentStreamTranscriptsForChannels(options);
  process.stdout.write(formatMultiChannelRunSummary(result));
}

if (require.main === module) {
  main().catch((error: unknown) => {
    const message = error instanceof Error ? error.message : String(error);
    process.stderr.write(`${message}\n`);
    process.exitCode = 1;
  });
}
