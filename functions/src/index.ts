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
  "You are a summarization engine.",
  "",
  "Summarize the khutbah using ONLY the transcript provided.",
  "",
  "Do not interpret, explain, infer, or add religious meaning.",
  "Do not add Qur’an, hadith, rulings, or advice unless they are explicitly",
  "stated in the transcript.",
  "Do not use phrases such as “Islam teaches,” “Muslims should,” or similar",
  "normative language unless those exact words appear in the",
  "transcript.",
  "If information is missing or unclear, say so explicitly.",
  "",
  "If a requested section is not present in the transcript, write",
  "“Not mentioned” or “None mentioned” exactly.",
  "You must output ONLY valid JSON.",
  "Do not include markdown, explanations, or extra text.",
  "Your entire response must be a single JSON object.",
  "You must output ONLY valid JSON.",
  "Do not include markdown, explanations, comments, or extra text.",
  "Your entire response must be a single JSON object and nothing else.",
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

      const response = await openai.responses.create({
        model: "gpt-5-mini",
        input: [
          {role: "system", content: SUMMARY_SYSTEM_PROMPT},
          {role: "user", content: transcript},
        ],
        max_output_tokens: 1800,
        text: {format: {type: "json_object"}},
      });

      const incomplete =
        (response as {incomplete_details?: {reason?: string}})
          .incomplete_details?.reason;
      if (incomplete) {
        throw new Error(`OpenAI stopped early: ${incomplete}`);
      }

      const {text, refusal, debug} = extractTextOrRefusal(response);
      if (!text) {
        const apiError = (response as {error?: {message?: string}}).error;
        const reason = apiError?.message ??
          (refusal ?
            `Model refusal: ${refusal}` :
            "Empty response from OpenAI");
        logger.error("OpenAI empty output", {
          reason,
          refusal,
          hasOutputText: debug.hasOutputText,
          outputLength: debug.outputLength,
          incompleteDetails:
            (response as {incomplete_details?: unknown}).incomplete_details ??
            null,
          rawResponse: safeJson(response),
        });
        throw new Error(reason);
      }

      // ---- Parse and validate JSON summary ----
      let parsed: unknown;
      try {
        parsed = JSON.parse(text);
      } catch {
        throw new Error("Model did not return valid JSON");
      }

      type SummaryShape = {
        mainTheme: unknown;
        keyPoints: unknown;
        explicitAyatOrHadith: unknown;
        characterTraits: unknown;
        weeklyAction: unknown;
        // Alternate keys we may map
        topic?: unknown;
        main_points?: unknown;
        quote?: unknown;
        closing_advice?: unknown;
      };

      const summaryObj = normalizeSummary(parsed as SummaryShape);

      const mainTheme = summaryObj.mainTheme;
      const keyPoints = summaryObj.keyPoints;
      const explicitAyatOrHadith = summaryObj.explicitAyatOrHadith;
      const characterTraits = summaryObj.characterTraits;
      const weeklyAction = summaryObj.weeklyAction;

      const isValid =
        typeof mainTheme === "string" &&
        Array.isArray(keyPoints) &&
        keyPoints.every((i) => typeof i === "string") &&
        Array.isArray(explicitAyatOrHadith) &&
        explicitAyatOrHadith.every((i) => typeof i === "string") &&
        Array.isArray(characterTraits) &&
        characterTraits.every((i) => typeof i === "string") &&
        typeof weeklyAction === "string";

      if (!isValid) {
        logger.error("Invalid summary schema", {
          summary: safeJson(summaryObj),
        });
        throw new Error("Invalid summary schema");
      }

      const safeSummary = {
        mainTheme: mainTheme as string,
        keyPoints: (keyPoints as string[]).slice(0, 7),
        explicitAyatOrHadith: explicitAyatOrHadith as string[],
        characterTraits: characterTraits as string[],
        weeklyAction: weeklyAction as string,
      };

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
  characterTraits: unknown;
  weeklyAction: unknown;
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
    !normalized.weeklyAction &&
    typeof raw.closing_advice === "string" &&
    raw.closing_advice.trim()
  ) {
    normalized.weeklyAction = raw.closing_advice.trim();
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

  // If characterTraits is missing, set empty array (as per requirements)
  if (normalized.characterTraits === undefined) {
    normalized.characterTraits = [];
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

  if (typeof normalized.weeklyAction !== "string") {
    normalized.weeklyAction = "No action mentioned";
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
