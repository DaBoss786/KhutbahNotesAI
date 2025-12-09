import {onObjectFinalized} from "firebase-functions/v2/storage";
import {onDocumentWritten} from "firebase-functions/v2/firestore";
import {logger} from "firebase-functions";
import {defineSecret} from "firebase-functions/params";
import * as admin from "firebase-admin";
import OpenAI from "openai";
import * as fs from "fs";
import * as os from "os";
import * as path from "path";

admin.initializeApp();
const db = admin.firestore();

const openaiKey = defineSecret("OPENAI_API_KEY");

const storageBucketName = "khutbah-notes-ai.firebasestorage.app";

const SUMMARY_SYSTEM_PROMPT = [
  "You are a careful summarization engine for Islamic khutbah (sermon)",
  "content.",
  "",
  "Your ONLY source of information is the khutbah material provided below.",
  "Do NOT rely on prior knowledge.",
  "",
  "Rules about content:",
  "- Use ONLY information that appears in the provided material.",
  "- Do NOT interpret, explain, infer, or add new religious meaning.",
  "- Do NOT add Qur'an verses, hadith, rulings, stories, or advice unless",
  "  they are explicitly stated in the provided text.",
  "- Do NOT use phrases such as \"Islam teaches\" or \"Muslims should\" unless",
  "  those exact words appear in the provided text.",
  "- If information is missing or unclear, say that it was not mentioned.",
  "",
  "Output format:",
  "- You MUST return a single JSON object.",
  "- Do NOT include markdown, prose explanations, comments, or any text",
  "  outside the JSON.",
  "- Do NOT include any keys other than the ones listed below.",
  "",
  "The JSON object MUST have EXACTLY these keys and value types:",
  "{",
  "  \"mainTheme\": string,",
  "  \"keyPoints\": string[],",
  "  \"explicitAyatOrHadith\": string[],",
  "  \"weeklyActions\": string[]",
  "}",
  "",
  "Field rules:",
  "- mainTheme:",
  "  - Up to 400 words total (prefer 3–5 concise sentences) describing the",
  "    main topic or message based only on the provided text.",
  "  - If the main theme is not clearly stated, use the exact string",
  "    \"Not mentioned\".",
  "",
  "- keyPoints:",
  "  - Up to 7 concise, complete sentences capturing the main ideas of the",
  "    khutbah.",
  "  - Each array item should stay under about 35 words to conserve tokens.",
  "  - If fewer points are clear, return what is available (at least 1).",
  "",
  "- explicitAyatOrHadith:",
  "  - Include at most 2 explicit Qur'an verses or hadith that are clearly",
  "    quoted in the provided text and most central to the khutbah's message.",
  "  - Copy each quote verbatim without paraphrasing or truncating it.",
  "  - If none are mentioned, return an empty array: [].",
  "",
  "- weeklyActions:",
  "  - Up to 3 practical actions clearly and explicitly encouraged in the",
  "    khutbah, written as complete sentences.",
  "  - If no explicit action is given, return an array with a single item:",
  "    \"No action mentioned\".",
  "",
  "Constraints:",
  "- Keep the entire output compact so it fits within the output token limit.",
  "- Use short, direct sentences and avoid repetition.",
  "- Output ONLY valid JSON. No markdown, explanations, comments, or extra",
  "  text. The entire response must be a single JSON object and nothing else.",
].join("\n");

const MAX_SUMMARY_OUTPUT_TOKENS = 3000;
const CHUNK_CHAR_TARGET = 4000;
const CHUNK_CHAR_OVERLAP = 300;
const CHUNK_OUTPUT_TOKENS = 2000;
const SUMMARY_MODEL = "gpt-5-mini";

const COMPACT_RETRY_INSTRUCTIONS = [
  "Your previous attempt exceeded the output token limit.",
  "Retry with an ultra-compact JSON summary that MUST fit well under the",
  "token budget.",
  "",
  "Hard limits:",
  "- mainTheme: max 200 words (2–3 short sentences).",
  "- keyPoints: max 6 sentences, each under ~22 words.",
  "- weeklyActions: max 3 sentences, each under ~16 words.",
  "- explicitAyatOrHadith: include up to 2 verbatim quotes most central to",
  "  the khutbah; no paraphrasing.",
].join("\n");

const ULTRA_COMPACT_INSTRUCTIONS = [
  "Your previous attempt still exceeded the output token limit.",
  "Return an ultra-compact JSON summary that MUST fit comfortably under the",
  "token budget.",
  "",
  "Hard limits:",
  "- mainTheme: max 120 words (1–2 sentences).",
  "- keyPoints: max 4 sentences, each under ~18 words.",
  "- weeklyActions: max 2 sentences, each under ~12 words.",
  "- explicitAyatOrHadith: include up to 2 verbatim quotes, prioritizing the",
  "  most central; avoid duplicates.",
].join("\n");

export const onAudioUpload = onObjectFinalized(
  {
    bucket: storageBucketName,
    region: "us-central1",
    timeoutSeconds: 300,
    memory: "1GiB",
    secrets: [openaiKey],
  },
  async (event) => {
    const filePath = event.data.name;
    if (!filePath) {
      console.log("No file path, exiting.");
      return;
    }

    // Only process files in audio/
    if (!filePath.startsWith("audio/")) {
      console.log("Ignoring file not in audio/:", filePath);
      return;
    }

    const contentType = event.data.contentType || "";
    if (!contentType.startsWith("audio/")) {
      console.log(
        "Ignoring non-audio file:",
        filePath,
        "(",
        contentType,
        ")"
      );
      return;
    }

    // Optional: size guard to avoid huge files (e.g., >100MB)
    const sizeBytes = event.data.size ? Number(event.data.size) : 0;
    if (sizeBytes > 100 * 1024 * 1024) {
      console.log(
        "File too large for transcription, skipping:",
        filePath,
        "sizeBytes:",
        sizeBytes
      );
      return;
    }

    const parts = filePath.split("/");
    if (parts.length < 3) {
      console.error("Unexpected audio path format:", filePath);
      return;
    }

    const userId = parts[1];
    const fileName = parts[2];
    const lectureId = fileName.replace(path.extname(fileName), "");

    const lectureRef = db
      .collection("users")
      .doc(userId)
      .collection("lectures")
      .doc(lectureId);

    // Idempotency check: if we've already completed this once, skip
    const existingDoc = await lectureRef.get();
    if (
      existingDoc.exists &&
      existingDoc.data()?.status === "transcribed"
    ) {
      console.log("Lecture already processed, skipping:", lectureId);
      return;
    }

    const bucket = admin.storage().bucket(event.data.bucket);
    const tempFilePath = path.join(
      os.tmpdir(),
      path.basename(filePath)
    );

    const openai = new OpenAI({
      apiKey: openaiKey.value(),
    });

    try {
      // Mark as processing as soon as we start
      await lectureRef.set({status: "processing"}, {merge: true});

      console.log("Downloading file to temp path:", filePath);
      await bucket.file(filePath).download({destination: tempFilePath});

      console.log(
        "Sending audio to OpenAI for transcription:",
        filePath
      );
      const transcription =
        await openai.audio.transcriptions.create({
          file: fs.createReadStream(tempFilePath),
          model: "whisper-1",
        });

      const rawText = (transcription as unknown as {text?: string})
        .text;
      const transcriptText =
        typeof rawText === "string" &&
        rawText.trim().length > 0 ?
          rawText.trim() :
          "";

      if (!transcriptText) {
        console.warn(
          "Empty transcript returned for lecture:",
          lectureId,
          "Marking as failed."
        );
        await lectureRef.set(
          {
            status: "failed",
            errorMessage: "Transcription returned empty text.",
          },
          {merge: true}
        );
        return;
      }

      console.log("Updating Firestore for lecture:", lectureId);
      await lectureRef.set(
        {
          transcript: transcriptText,
          status: "transcribed", // transcript is ready; summary can run next
          processedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        {merge: true}
      );
    } catch (err: unknown) {
      console.error("Error in onAudioUpload:", err);

      const message =
        err instanceof Error ?
          err.message :
          "Transcription failed";

      await lectureRef.set(
        {
          status: "failed",
          errorMessage: message,
        },
        {merge: true}
      );
    } finally {
      try {
        if (fs.existsSync(tempFilePath)) {
          fs.unlinkSync(tempFilePath);
        }
      } catch (cleanupErr: unknown) {
        console.error("Error cleaning up temp file:", cleanupErr);
      }
    }
  }
);

export const summarizeKhutbah = onDocumentWritten(
  {
    document: "users/{userId}/lectures/{lectureId}",
    region: "us-central1",
    secrets: [openaiKey],
    timeoutSeconds: 540,
    memory: "1GiB",
  },
  async (event) => {
    const afterSnap = event.data?.after;
    if (!afterSnap?.exists) {
      return;
    }

    const lecture = afterSnap.data();
    if (!lecture || lecture.status !== "transcribed") {
      return;
    }

    const transcript = typeof lecture.transcript === "string" ?
      lecture.transcript.trim() :
      "";

    if (!transcript) {
      return;
    }

    // Already summarized or in progress? Exit.
    if (lecture.summary || lecture.summaryInProgress === true) {
      return;
    }

    const docRef = afterSnap.ref;

    // ---- Acquire a transactional lock so only one worker summarizes ----
    const lockAcquired = await db.runTransaction(async (tx) => {
      const snap = await tx.get(docRef);
      const current = snap.data();

      if (
        !snap.exists ||
        current?.status !== "transcribed" ||
        current?.summary ||
        current?.summaryInProgress === true
      ) {
        return false;
      }

      tx.update(docRef, {
        summaryInProgress: true,
        status: "summarizing",
      });

      return true;
    });

    if (!lockAcquired) {
      return;
    }

    try {
      const openai = new OpenAI({
        apiKey: openaiKey.value(),
      });

      const chunks = chunkTranscript(
        transcript,
        CHUNK_CHAR_TARGET,
        CHUNK_CHAR_OVERLAP
      );

      const perChunkTokenLimit =
        chunks.length === 1 ?
          MAX_SUMMARY_OUTPUT_TOKENS :
          CHUNK_OUTPUT_TOKENS;

      const chunkSummaries: SummaryShape[] = [];
      for (let i = 0; i < chunks.length; i++) {
        const chunkSummary = await summarizeChunk(
          openai,
          chunks[i],
          i + 1,
          chunks.length,
          perChunkTokenLimit
        );
        chunkSummaries.push(chunkSummary);
      }

      const combinedSummary =
        chunks.length === 1 ?
          chunkSummaries[0] :
          await aggregateChunkSummaries(openai, chunkSummaries);

      const normalized = normalizeSummary(combinedSummary);
      const safeSummary = enforceSummaryLimits(normalized);

      await docRef.update({
        summary: safeSummary,
        status: "ready",
        summarizedAt: admin.firestore.FieldValue.serverTimestamp(),
        summaryInProgress: admin.firestore.FieldValue.delete(),
        errorMessage: admin.firestore.FieldValue.delete(),
      });
    } catch (err: unknown) {
      console.error("Error in summarizeKhutbah:", err);

      const message =
        err instanceof Error ? err.message : "Summarization failed";

      await docRef.update({
        status: "failed",
        errorMessage: message,
        summaryInProgress: admin.firestore.FieldValue.delete(),
      });
    }
  }
);

type ResponseMessage = {role: "system" | "user"; content: string};

/**
 * Summarize a single transcript chunk using a tight token budget.
 *
 * @param {OpenAI} openai OpenAI client instance.
 * @param {string} chunk Transcript chunk text.
 * @param {number} chunkIndex 1-based index of this chunk.
 * @param {number} totalChunks Total number of chunks.
 * @param {number} maxOutputTokens Output token budget for this request.
 * @return {Promise<SummaryShape>} Parsed summary for the chunk.
 */
async function summarizeChunk(
  openai: OpenAI,
  chunk: string,
  chunkIndex: number,
  totalChunks: number,
  maxOutputTokens = CHUNK_OUTPUT_TOKENS
): Promise<SummaryShape> {
  const chunkContext = [
    `You are summarizing chunk ${chunkIndex} of ${totalChunks} of a khutbah`,
    "transcript.",
    totalChunks > 1 ?
      "Focus only on this chunk. Do not speculate about missing context." :
      "This is the full transcript.",
    "Keep the output brief to conserve tokens:",
    "- mainTheme: up to ~200 words (3–4 sentences).",
    "- keyPoints: up to 5 complete sentences, each kept concise.",
    "- explicitAyatOrHadith: include a maximum of 2 explicit quotes",
    "  verbatim from this chunk, prioritizing the most central to the",
    "  khutbah's message.",
    "- weeklyActions: up to 2 explicit actions or \"No action mentioned\".",
  ].join("\n");

  let text: string;
  try {
    text = await runJsonSummaryRequest(
      openai,
      [
        {role: "system", content: SUMMARY_SYSTEM_PROMPT},
        {role: "user", content: chunkContext},
        {role: "user", content: chunk},
      ],
      maxOutputTokens,
      `Chunk ${chunkIndex}/${totalChunks}`
    );
  } catch (err: unknown) {
    if (!isMaxOutputTokensError(err)) {
      throw err;
    }

    // First retry: add more tokens with compact instructions
    try {
      text = await runJsonSummaryRequest(
        openai,
        [
          {role: "system", content: SUMMARY_SYSTEM_PROMPT},
          {role: "user", content: COMPACT_RETRY_INSTRUCTIONS},
          {role: "user", content: chunkContext},
          {role: "user", content: chunk},
        ],
        maxOutputTokens + 500,
        `Chunk ${chunkIndex}/${totalChunks} (compact)`
      );
    } catch (err2: unknown) {
      if (!isMaxOutputTokensError(err2)) {
        throw err2;
      }

      // Second retry: even more tokens with ultra-compact instructions
      text = await runJsonSummaryRequest(
        openai,
        [
          {role: "system", content: SUMMARY_SYSTEM_PROMPT},
          {role: "user", content: ULTRA_COMPACT_INSTRUCTIONS},
          {role: "user", content: chunkContext},
          {role: "user", content: chunk},
        ],
        maxOutputTokens + 1000,
        `Chunk ${chunkIndex}/${totalChunks} (ultra-compact)`
      );
    }
  }

  let parsed: unknown;
  try {
    parsed = JSON.parse(text);
  } catch {
    const invalidJsonMsg =
      `Chunk ${chunkIndex}/${totalChunks}: Model did not return valid JSON`;
    throw new Error(invalidJsonMsg);
  }

  return normalizeSummary(parsed as SummaryShape);
}

/**
 * Combine multiple chunk-level summaries into a final summary within limits.
 *
 * @param {OpenAI} openai OpenAI client instance.
 * @param {SummaryShape[]} summaries Chunk-level summaries to merge.
 * @return {Promise<SummaryShape>} Combined summary.
 */
async function aggregateChunkSummaries(
  openai: OpenAI,
  summaries: SummaryShape[]
): Promise<SummaryShape> {
  const combineInstructions = [
    "Combine the chunk-level summaries into one final khutbah summary using",
    "the required JSON schema.",
    "The next message is a JSON array of chunk summaries; use only that",
    "content.",
    "",
    "Rules for combining:",
    "- Merge overlapping ideas and remove duplicates.",
    "- Keep explicitAyatOrHadith verbatim; include up to 2 unique quotes that",
    "  are most central across chunks.",
    "- Keep the final limits: mainTheme <= 400 words, keyPoints <= 7 complete",
    "  sentences, weeklyActions <= 3 complete sentences, explicitAyatOrHadith",
    "  <= 2 quotes.",
    "- Prefer concise wording to stay within the output token limit.",
  ].join("\n");

  let text: string;
  try {
    text = await runJsonSummaryRequest(
      openai,
      [
        {role: "system", content: SUMMARY_SYSTEM_PROMPT},
        {role: "user", content: combineInstructions},
        {role: "user", content: JSON.stringify(summaries)},
      ],
      MAX_SUMMARY_OUTPUT_TOKENS,
      "Aggregation"
    );
  } catch (err: unknown) {
    if (!isMaxOutputTokensError(err)) {
      throw err;
    }

    // First retry: add more tokens with compact instructions
    try {
      text = await runJsonSummaryRequest(
        openai,
        [
          {role: "system", content: SUMMARY_SYSTEM_PROMPT},
          {role: "user", content: COMPACT_RETRY_INSTRUCTIONS},
          {role: "user", content: combineInstructions},
          {role: "user", content: JSON.stringify(summaries)},
        ],
        MAX_SUMMARY_OUTPUT_TOKENS + 500,
        "Aggregation (compact)"
      );
    } catch (err2: unknown) {
      if (!isMaxOutputTokensError(err2)) {
        throw err2;
      }

      // Second retry: even more tokens with ultra-compact instructions
      text = await runJsonSummaryRequest(
        openai,
        [
          {role: "system", content: SUMMARY_SYSTEM_PROMPT},
          {role: "user", content: ULTRA_COMPACT_INSTRUCTIONS},
          {role: "user", content: combineInstructions},
          {role: "user", content: JSON.stringify(summaries)},
        ],
        MAX_SUMMARY_OUTPUT_TOKENS + 1000,
        "Aggregation (ultra-compact)"
      );
    }
  }

  let parsed: unknown;
  try {
    parsed = JSON.parse(text);
  } catch {
    throw new Error("Aggregation: Model did not return valid JSON");
  }

  return parsed as SummaryShape;
}

/**
 * Invoke the OpenAI Responses API enforcing JSON and surfacing incomplete
 * errors.
 *
 * @param {OpenAI} openai OpenAI client instance.
 * @param {ResponseMessage[]} messages Messages to send to the model.
 * @param {number} maxOutputTokens Output token budget.
 * @param {string} stage Friendly label for logging/errors.
 * @return {Promise<string>} Raw JSON string from the model.
 */
async function runJsonSummaryRequest(
  openai: OpenAI,
  messages: ResponseMessage[],
  maxOutputTokens: number,
  stage: string
): Promise<string> {
  const response = await openai.responses.create({
    model: SUMMARY_MODEL,
    input: messages,
    max_output_tokens: maxOutputTokens,
    text: {format: {type: "json_object"}},
  });

  const incomplete =
    (response as {incomplete_details?: {reason?: string}})
      .incomplete_details?.reason;
  if (incomplete) {
    throw new Error(`${stage}: OpenAI stopped early: ${incomplete}`);
  }

  const {text, refusal, debug} = extractTextOrRefusal(response);
  if (!text) {
    const apiError = (response as {error?: {message?: string}}).error;
    const reason = apiError?.message ??
      (refusal ? `Model refusal: ${refusal}` : "Empty response from OpenAI");
    logger.error(`${stage} empty output`, {
      reason,
      refusal,
      hasOutputText: debug.hasOutputText,
      outputLength: debug.outputLength,
      incompleteDetails:
        (response as {incomplete_details?: unknown}).incomplete_details ?? null,
      rawResponse: safeJson(response),
    });
    throw new Error(`${stage}: ${reason}`);
  }

  return text;
}

/**
 * Detect whether an error came from a max_output_tokens cutoff.
 *
 * @param {unknown} err Error to inspect.
 * @return {boolean} True if the error message mentions max_output_tokens.
 */
function isMaxOutputTokensError(err: unknown): boolean {
  const message =
    err instanceof Error ? err.message : typeof err === "string" ? err : "";
  return message.includes("max_output_tokens");
}

/**
 * Split long transcripts into overlapping character-based chunks.
 *
 * @param {string} transcript Full transcript text.
 * @param {number} targetChars Target characters per chunk.
 * @param {number} overlapChars Overlap characters between chunks.
 * @return {string[]} Array of chunk strings.
 */
function chunkTranscript(
  transcript: string,
  targetChars: number,
  overlapChars: number
): string[] {
  const cleaned = transcript.replace(/\r\n/g, "\n").trim();
  if (cleaned.length === 0) {
    return [];
  }

  if (cleaned.length <= targetChars) {
    return [cleaned];
  }

  const chunks: string[] = [];
  let start = 0;

  while (start < cleaned.length) {
    const end = Math.min(cleaned.length, start + targetChars);
    const chunk = cleaned.slice(start, end).trim();
    if (chunk.length > 0) {
      chunks.push(chunk);
    }

    if (end >= cleaned.length) {
      break;
    }

    start = Math.max(0, end - overlapChars);
  }

  return chunks;
}

/**
 * Enforce field limits and validate the final summary shape.
 *
 * @param {SummaryShape} summaryObj Summary object to enforce.
 * @return {{
 *   mainTheme: string,
 *   keyPoints: string[],
 *   explicitAyatOrHadith: string[],
 *   weeklyActions: string[]
 * }} Summary with enforced limits.
 */
function enforceSummaryLimits(summaryObj: SummaryShape): {
  mainTheme: string;
  keyPoints: string[];
  explicitAyatOrHadith: string[];
  weeklyActions: string[];
} {
  const mainTheme = summaryObj.mainTheme;
  const keyPoints = summaryObj.keyPoints;
  const explicitAyatOrHadith = summaryObj.explicitAyatOrHadith;
  const weeklyActions = summaryObj.weeklyActions;

  const isValid =
    typeof mainTheme === "string" &&
    Array.isArray(keyPoints) &&
    keyPoints.every((i) => typeof i === "string") &&
    Array.isArray(explicitAyatOrHadith) &&
    explicitAyatOrHadith.every((i) => typeof i === "string") &&
    Array.isArray(weeklyActions) &&
    weeklyActions.every((i) => typeof i === "string");

  if (!isValid) {
    logger.error("Invalid summary schema", {
      summary: safeJson(summaryObj),
    });
    throw new Error("Invalid summary schema");
  }

  const dedupedKeyPoints = dedupeStrings(keyPoints).slice(0, 7);
  const dedupedWeekly = dedupeStrings(weeklyActions).slice(0, 3);
  const dedupedQuotes = dedupeStrings(explicitAyatOrHadith).slice(0, 2);

  const trimmedTheme = truncateWords(mainTheme, 400).trim();

  return {
    mainTheme: trimmedTheme.length > 0 ? trimmedTheme : "Not mentioned",
    keyPoints: dedupedKeyPoints,
    explicitAyatOrHadith: dedupedQuotes,
    weeklyActions:
      dedupedWeekly.length > 0 ? dedupedWeekly : ["No action mentioned"],
  };
}

/**
 * Remove duplicates and empty strings from a string array while preserving
 * order.
 *
 * @param {unknown} items Candidate list of strings.
 * @return {string[]} Deduped string array.
 */
function dedupeStrings(items: unknown): string[] {
  if (!Array.isArray(items)) {
    return [];
  }

  const seen = new Set<string>();
  const result: string[] = [];

  for (const item of items) {
    if (typeof item !== "string") {
      continue;
    }
    const trimmed = item.trim();
    if (!trimmed || seen.has(trimmed)) {
      continue;
    }
    seen.add(trimmed);
    result.push(trimmed);
  }

  return result;
}

/**
 * Truncate a string to a maximum number of words.
 *
 * @param {string} text Text to truncate.
 * @param {number} maxWords Maximum words to keep.
 * @return {string} Truncated text.
 */
function truncateWords(text: string, maxWords: number): string {
  const words = text.trim().split(/\s+/);
  if (words.length <= maxWords) {
    return text.trim();
  }
  return words.slice(0, maxWords).join(" ");
}

/**
 * Extract plain text or refusal reason from an OpenAI Responses API response.
 *
 * @param {*} response Raw response payload from OpenAI Responses API.
 * @return {Object} Parsed text and refusal.
 * @return {string|null} return.text Trimmed text content if available.
 * @return {string|null} return.refusal Refusal reason if present.
 * @return {Object} return.debug Debug flags for logging.
 */
function extractTextOrRefusal(response: unknown): {
  text: string | null;
  refusal: string | null;
  debug: {hasOutputText: boolean; outputLength: number};
} {
  const anyResp = response as {
    output_text?: string | null;
    output?: Array<{
      refusal?: string;
      content?: Array<{
        type?: string;
        text?: string;
        refusal?: string;
      }>;
    }>;
  };

  const debug = {
    hasOutputText:
      typeof anyResp.output_text === "string" &&
      anyResp.output_text.trim().length > 0,
    outputLength: Array.isArray(anyResp.output) ? anyResp.output.length : 0,
  };

  // 1) Prefer the convenience helper if present (documented in OpenAI JS SDK)
  if (
    typeof anyResp.output_text === "string" &&
    anyResp.output_text.trim().length > 0
  ) {
    return {text: anyResp.output_text.trim(), refusal: null, debug};
  }

  // 2) Fallback: walk the output array manually
  if (!Array.isArray(anyResp.output) || anyResp.output.length === 0) {
    return {text: null, refusal: null, debug};
  }

  for (const item of anyResp.output) {
    if (typeof item?.refusal === "string" && item.refusal.trim().length > 0) {
      return {text: null, refusal: item.refusal.trim(), debug};
    }

    if (!item || !Array.isArray(item.content)) {
      continue;
    }

    for (const piece of item.content) {
      if (typeof piece?.text === "string" && piece.text.trim().length > 0) {
        return {text: piece.text.trim(), refusal: null, debug};
      }

      if (piece?.type === "refusal" || typeof piece?.refusal === "string") {
        const reason =
          (typeof piece.refusal === "string" &&
            piece.refusal.trim().length > 0 ?
            piece.refusal.trim() :
            null) ??
          "Refusal with no reason provided";
        return {text: null, refusal: reason, debug};
      }
    }
  }

  return {text: null, refusal: null, debug};
}

/**
 * Safe JSON stringify with truncation to avoid log bloat.
 *
 * @param {*} value Arbitrary value to stringify.
 * @return {string} Safe stringified and truncated value.
 */
function safeJson(value: unknown): string {
  try {
    const str = JSON.stringify(value);
    return str.length > 2000 ? `${str.slice(0, 2000)}...<truncated>` : str;
  } catch (err) {
    return `Unserializable response: ${String(err)}`;
  }
}

// Types used by normalization helpers
type SummaryShape = {
  mainTheme: unknown;
  keyPoints: unknown;
  explicitAyatOrHadith: unknown;
  weeklyActions: unknown;
  topic?: unknown;
  main_theme?: unknown;
  main_points?: unknown;
  quote?: unknown;
  quoted_verse?: unknown;
  closing_advice?: unknown;
};

/**
 * Normalize alternate summary field names into the required schema.
 *
 * @param {SummaryShape} raw Raw summary object from the model.
 * @return {SummaryShape} Normalized summary.
 */
function normalizeSummary(raw: SummaryShape): SummaryShape {
  const normalized = {...raw};

  if (!normalized.mainTheme && typeof raw.topic === "string") {
    normalized.mainTheme = raw.topic;
  }

  if (!normalized.mainTheme && typeof raw.main_theme === "string") {
    normalized.mainTheme = raw.main_theme;
  }

  if (!normalized.keyPoints && Array.isArray(raw.main_points)) {
    normalized.keyPoints = raw.main_points;
  }

  // Backward compatibility for single weeklyAction key
  if (
    !normalized.weeklyActions &&
    typeof (raw as {weeklyAction?: unknown}).weeklyAction === "string"
  ) {
    const action = (raw as {weeklyAction?: string}).weeklyAction;
    if (action && action.trim()) {
      normalized.weeklyActions = [action.trim()];
    }
  }

  if (
    !normalized.explicitAyatOrHadith &&
    typeof raw.quote === "string" &&
    raw.quote.trim()
  ) {
    normalized.explicitAyatOrHadith = [raw.quote.trim()];
  }

  if (
    !normalized.explicitAyatOrHadith &&
    typeof raw.quoted_verse === "string" &&
    raw.quoted_verse.trim()
  ) {
    normalized.explicitAyatOrHadith = [raw.quoted_verse.trim()];
  }

  if (
    !normalized.weeklyActions &&
    typeof raw.closing_advice === "string" &&
    raw.closing_advice.trim()
  ) {
    normalized.weeklyActions = [raw.closing_advice.trim()];
  }

  // If explicitAyatOrHadith is a single string, wrap into array
  if (
    typeof normalized.explicitAyatOrHadith === "string" &&
    normalized.explicitAyatOrHadith.trim()
  ) {
    normalized.explicitAyatOrHadith = [normalized.explicitAyatOrHadith.trim()];
  }

  // If keyPoints is a single string, wrap into array
  if (
    typeof normalized.keyPoints === "string" &&
    normalized.keyPoints.trim()
  ) {
    normalized.keyPoints = [normalized.keyPoints.trim()];
  }

  // If weeklyActions is a single string, wrap into array
  if (
    typeof normalized.weeklyActions === "string" &&
    normalized.weeklyActions.trim()
  ) {
    normalized.weeklyActions = [normalized.weeklyActions.trim()];
  }

  // If mainTheme is missing but we have keyPoints, fall back to first point
  if (
    typeof normalized.mainTheme !== "string" &&
    Array.isArray(normalized.keyPoints) &&
    normalized.keyPoints.length > 0 &&
    typeof normalized.keyPoints[0] === "string"
  ) {
    normalized.mainTheme = normalized.keyPoints[0];
  }

  // Fill defaults per spec if still missing
  if (typeof normalized.mainTheme !== "string") {
    normalized.mainTheme = "Not mentioned";
  }

  if (!Array.isArray(normalized.explicitAyatOrHadith)) {
    normalized.explicitAyatOrHadith = [];
  }

  if (!Array.isArray(normalized.keyPoints)) {
    normalized.keyPoints = [];
  }

  if (!Array.isArray(normalized.weeklyActions)) {
    normalized.weeklyActions = ["No action mentioned"];
  }

  return normalized;
}

// Reserved for future use: derive weekly action if model omits it
// function extractActionFromTranscript(transcript: string): string | null {
//   const sentences = transcript.split(/(?<=[.!?])\s+/);
//   for (const sentence of sentences) {
//     const lower = sentence.toLowerCase();
//     if (
//       lower.includes("check in") ||
//       (lower.includes("advise") && lower.includes("week"))
//     ) {
//       const trimmed = sentence.trim();
//       if (trimmed.length > 0) {
//         return trimmed;
//       }
//     }
//   }
//   return null;
// }
