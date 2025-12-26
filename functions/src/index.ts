import {onObjectFinalized} from "firebase-functions/v2/storage";
import {onDocumentWritten} from "firebase-functions/v2/firestore";
import {onRequest} from "firebase-functions/v2/https";
import {onSchedule} from "firebase-functions/v2/scheduler";
import {logger} from "firebase-functions";
import {defineSecret} from "firebase-functions/params";
import type {Request, Response} from "express";
import * as admin from "firebase-admin";
import OpenAI from "openai";
import * as fs from "fs";
import * as os from "os";
import * as path from "path";
import {spawn} from "child_process";
import ffmpegPath from "ffmpeg-static";
import {parseFile} from "music-metadata";
import {DateTime} from "luxon";

admin.initializeApp();
const db = admin.firestore();

const openaiKey = defineSecret("OPENAI_API_KEY");
const rcWebhookSecret = defineSecret("RC_WEBHOOK_SECRET");
const onesignalApiKey = defineSecret("ONESIGNAL_API_KEY");

const storageBucketName = "khutbah-notes-ai.firebasestorage.app";
const REVENUECAT_ENTITLEMENT_ID = "Khutbah Notes Pro";

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
  "  - Up to 500 words total (prefer 7-9 concise sentences split",
  "    into 2-3 paragraphs) describing the",
  "    main topic or message based only on the provided text.",
  "  - If the main theme is not clearly stated, use the exact string",
  "    \"Not mentioned\".",
  "",
  "- keyPoints:",
  "  - Up to 9 concise, complete sentences capturing the main ideas of the",
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
  "  - Up to 5 practical actions clearly and explicitly encouraged in the",
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

const SUMMARY_TRANSLATION_SYSTEM_PROMPT = [
  "You are a careful translation engine for Islamic khutbah summaries.",
  "",
  "Translate the provided summary JSON into the target language.",
  "Preserve the meaning and factual content exactly.",
  "Do NOT add, remove, or infer information.",
  "Keep the JSON structure and keys unchanged.",
  "Translate each list item and keep the same ordering.",
  "If the input contains \"Not mentioned\" or \"No action mentioned\",",
  "translate those phrases into the target language.",
  "If a quote is already written in Arabic script, keep it verbatim.",
  "",
  "Output format:",
  "- Return a single JSON object with exactly these keys:",
  "{",
  "  \"mainTheme\": string,",
  "  \"keyPoints\": string[],",
  "  \"explicitAyatOrHadith\": string[],",
  "  \"weeklyActions\": string[]",
  "}",
  "- Do NOT include any extra keys, comments, or text outside the JSON.",
].join("\n");

const MAX_SUMMARY_OUTPUT_TOKENS = 3000;
const CHUNK_CHAR_TARGET = 4000;
const CHUNK_CHAR_OVERLAP = 300;
const CHUNK_OUTPUT_TOKENS = 2000;
const SUMMARY_MODEL = "gpt-5-mini";
const SUMMARY_TRANSLATION_MAX_OUTPUT_TOKENS = 2000;
const TRANSCRIBE_CHUNK_SECONDS = 1200; // keep under model ~1400s limit

const SUMMARY_TRANSLATION_LANGUAGES: Record<string, string> = {
  ar: "Arabic",
  ur: "Urdu",
  fr: "French",
  tr: "Turkish",
  id: "Indonesian",
  ms: "Malay",
  es: "Spanish",
  bn: "Bengali",
};

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

type UserData = {
  plan?: string;
  monthlyKey?: string;
  monthlyMinutesUsed?: number;
  freeLifetimeMinutesUsed?: number;
  periodStart?: admin.firestore.Timestamp | admin.firestore.FieldValue;
  renewsAt?: admin.firestore.Timestamp | admin.firestore.FieldValue;
};

/**
 * Error to represent quota violations with a structured reason.
 */
class QuotaError extends Error {
  reason: string;

  /**
   * @param {string} message Human-readable message.
   * @param {string} reason Machine-readable reason code.
   */
  constructor(message: string, reason: string) {
    super(message);
    this.name = "QuotaError";
    this.reason = reason;
  }
}

/**
 * Compute a YYYY-MM-DD key for a billing period anchor date.
 *
 * @param {Date} date Anchor date.
 * @return {string} Period key.
 */
export function getMonthlyKey(date: Date): string {
  return [
    date.getFullYear(),
    `${date.getMonth() + 1}`.padStart(2, "0"),
    `${date.getDate()}`.padStart(2, "0"),
  ].join("-");
}

/**
 * Add one month to a date, preserving the day when possible.
 *
 * @param {Date} date Input date.
 * @return {Date} New date one month later.
 */
function addOneMonth(date: Date): Date {
  const next = new Date(date.getTime());
  next.setMonth(next.getMonth() + 1);
  return next;
}

/**
 * Convert a Firestore timestamp into a JS Date.
 *
 * @param {unknown} value Candidate timestamp.
 * @return {Date|null} Converted date or null.
 */
function toDate(value: unknown): Date | null {
  if (value instanceof admin.firestore.Timestamp) {
    return value.toDate();
  }
  return null;
}

/**
 * Compute audio duration in whole minutes from a file path.
 *
 * @param {string} filePath Absolute path to the audio file.
 * @return {Promise<number>} Rounded minutes, minimum of 1.
 */
export async function getAudioDurationMinutes(
  filePath: string
): Promise<number> {
  const metadata = await parseFile(filePath);
  const seconds = metadata.format.duration ?? 0;
  return Math.max(1, Math.round(seconds / 60));
}

/**
 * Run an ffmpeg command and reject on non-zero exit.
 *
 * @param {string} command Binary path.
 * @param {string[]} args Arguments.
 * @return {Promise<void>} Resolves on success.
 */
async function runCommand(command: string, args: string[]): Promise<void> {
  return new Promise((resolve, reject) => {
    const child = spawn(command, args, {stdio: "pipe"});
    const stderr: Buffer[] = [];

    child.stderr?.on("data", (data: Buffer) => {
      stderr.push(data);
    });

    child.on("error", (err) => {
      reject(err);
    });

    child.on("close", (code) => {
      if (code === 0) {
        resolve();
      } else {
        const msg = Buffer.concat(stderr).toString() || "ffmpeg failed";
        reject(new Error(msg));
      }
    });
  });
}

/**
 * Split audio into <=1200s chunks to stay under OpenAI limits.
 *
 * @param {string} filePath Source audio absolute path.
 * @param {number} segmentSeconds Max seconds per chunk.
 * @return {Promise<string[]>} Paths to chunk files in temp dir.
 */
async function chunkAudio(
  filePath: string,
  segmentSeconds = TRANSCRIBE_CHUNK_SECONDS
): Promise<string[]> {
  if (!ffmpegPath) {
    throw new Error("ffmpeg binary not available");
  }

  const base = path.basename(filePath).replace(path.extname(filePath), "");
  const prefix = `chunk-${base}-${Date.now()}`;
  const outputPattern = path.join(os.tmpdir(), `${prefix}-%03d.mp3`);

  const args = [
    "-y",
    "-i",
    filePath,
    "-vn",
    "-ac",
    "1",
    "-ar",
    "16000",
    "-c:a",
    "libmp3lame",
    "-b:a",
    "64k",
    "-f",
    "segment",
    "-segment_time",
    `${segmentSeconds}`,
    "-reset_timestamps",
    "1",
    outputPattern,
  ];

  await runCommand(ffmpegPath, args);

  const chunkFiles = fs
    .readdirSync(os.tmpdir())
    .filter(
      (name) => name.startsWith(prefix) && name.endsWith(".mp3")
    )
    .sort()
    .map((name) => path.join(os.tmpdir(), name));

  if (chunkFiles.length === 0) {
    throw new Error("ffmpeg did not produce any chunks");
  }

  return chunkFiles;
}

/**
 * Reset the user's monthly counters when crossing the renew date.
 *
 * For premium, the cycle is anchored to periodStart/renewsAt (subscription
 * anniversary). For free, it still honors periodStart if present; otherwise it
 * starts from "now".
 *
 * @param {FirebaseFirestore.Transaction} tx Firestore transaction.
 * @param {FirebaseFirestore.DocumentReference} userRef User document ref.
 * @param {UserData} userData User snapshot data.
 * @param {Date} now Current time.
 * @return {{
 *   monthlyKey: string,
 *   monthlyMinutesUsed: number,
 *   periodStart: Date,
 *   renewsAt: Date,
 * }} Updated period info.
 */
export function resetMonthlyIfNeeded(
  tx: FirebaseFirestore.Transaction,
  userRef: FirebaseFirestore.DocumentReference,
  userData: UserData,
  now: Date = new Date()
): {
  monthlyKey: string;
  monthlyMinutesUsed: number;
  periodStart: Date;
  renewsAt: Date;
} {
  const plan = userData.plan === "premium" ? "premium" : "free";

  const snapshotMonthlyUsed =
    typeof userData.monthlyMinutesUsed === "number" ?
      userData.monthlyMinutesUsed :
      0;

  let periodStart =
    toDate(userData.periodStart) ??
    (plan === "premium" ? now : now);

  let renewsAt =
    toDate(userData.renewsAt) ?? addOneMonth(periodStart);

  let monthlyMinutesUsed = snapshotMonthlyUsed;

  // Advance periodStart/renewsAt if we're past the current renew window.
  while (now >= renewsAt) {
    periodStart = renewsAt;
    renewsAt = addOneMonth(periodStart);
    monthlyMinutesUsed = 0;
  }

  const monthlyKey = getMonthlyKey(periodStart);

  const needsUpdate =
    monthlyKey !== userData.monthlyKey ||
    monthlyMinutesUsed !== snapshotMonthlyUsed ||
    !toDate(userData.periodStart) ||
    !toDate(userData.renewsAt);

  if (needsUpdate) {
    tx.update(userRef, {
      monthlyKey,
      monthlyMinutesUsed,
      periodStart: admin.firestore.Timestamp.fromDate(periodStart),
      renewsAt: admin.firestore.Timestamp.fromDate(renewsAt),
    });
  }

  return {monthlyKey, monthlyMinutesUsed, periodStart, renewsAt};
}

/**
 * Enforce per-recording and plan quotas, then debit within the transaction.
 *
 * @param {FirebaseFirestore.Transaction} tx Firestore transaction.
 * @param {FirebaseFirestore.DocumentReference} userRef User document ref.
 * @param {UserData} userData User snapshot data.
 * @param {number} durationMinutes Rounded minutes of the recording.
 * @param {Date} now Current time.
 * @return {number} Charged minutes (equals durationMinutes if successful).
 */
export function checkAndDebitQuota(
  tx: FirebaseFirestore.Transaction,
  userRef: FirebaseFirestore.DocumentReference,
  userData: UserData,
  durationMinutes: number,
  now: Date = new Date()
): number {
  if (durationMinutes > 70) {
    throw new QuotaError(
      "Recording exceeds 70-minute per-file cap.",
      "per_file_cap"
    );
  }

  const plan = userData.plan === "premium" ? "premium" : "free";

  const {
    monthlyMinutesUsed,
    monthlyKey,
    periodStart,
    renewsAt,
  } = resetMonthlyIfNeeded(tx, userRef, userData, now);

  if (plan === "free") {
    const lifetimeUsed =
      typeof userData.freeLifetimeMinutesUsed === "number" ?
        userData.freeLifetimeMinutesUsed :
        0;
    const newLifetimeTotal = lifetimeUsed + durationMinutes;

    if (newLifetimeTotal > 60) {
      throw new QuotaError(
        "Free plan lifetime minutes exceeded.",
        "free_lifetime_exceeded"
      );
    }

    const newMonthlyTotal = monthlyMinutesUsed + durationMinutes;

    tx.update(userRef, {
      plan,
      freeLifetimeMinutesUsed: newLifetimeTotal,
      monthlyMinutesUsed: newMonthlyTotal,
      monthlyKey,
      periodStart: admin.firestore.Timestamp.fromDate(periodStart),
      renewsAt: admin.firestore.Timestamp.fromDate(renewsAt),
    });

    return durationMinutes;
  }

  // Premium path
  const newMonthlyTotal = monthlyMinutesUsed + durationMinutes;
  if (newMonthlyTotal > 500) {
    throw new QuotaError(
      "Premium monthly minutes exceeded.",
      "premium_monthly_exceeded"
    );
  }

  tx.update(userRef, {
    plan,
    monthlyMinutesUsed: newMonthlyTotal,
    monthlyKey,
    periodStart: admin.firestore.Timestamp.fromDate(periodStart),
    renewsAt: admin.firestore.Timestamp.fromDate(renewsAt),
  });

  return durationMinutes;
}

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
    const userRef = db.collection("users").doc(userId);

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
    const now = new Date();
    let durationMinutes = 0;
    let chargedMinutes = 0;
    let chunkPaths: string[] = [];

    const openai = new OpenAI({
      apiKey: openaiKey.value(),
    });

    try {
      console.log("Downloading file to temp path:", filePath);
      await bucket.file(filePath).download({destination: tempFilePath});

      durationMinutes = await getAudioDurationMinutes(tempFilePath);

      // Quota check + debit (transactional)
      await db.runTransaction(async (tx) => {
        const userSnap = await tx.get(userRef);
        const userData = (userSnap.data() as UserData) ?? {};

        if (!userSnap.exists) {
          const periodStart = now;
          const renewsAt = addOneMonth(periodStart);
          tx.set(
            userRef,
            {
              plan: "free",
              monthlyKey: getMonthlyKey(periodStart),
              monthlyMinutesUsed: 0,
              freeLifetimeMinutesUsed: 0,
              periodStart: admin.firestore.Timestamp.fromDate(periodStart),
              renewsAt: admin.firestore.Timestamp.fromDate(renewsAt),
            },
            {merge: true}
          );
        }

        chargedMinutes = checkAndDebitQuota(
          tx,
          userRef,
          userData,
          durationMinutes,
          now
        );

        tx.set(
          lectureRef,
          {
            durationMinutes,
            chargedMinutes,
            status: "processing",
            quotaReason: admin.firestore.FieldValue.delete(),
          },
          {merge: true}
        );
      });

      console.log(
        "Sending audio to OpenAI for transcription:",
        filePath
      );
      chunkPaths = await chunkAudio(tempFilePath);
      const chunkTranscripts: string[] = [];

      for (let i = 0; i < chunkPaths.length; i++) {
        const chunkPath = chunkPaths[i];
        const transcription =
          await openai.audio.transcriptions.create({
            file: fs.createReadStream(chunkPath),
            model: "gpt-4o-mini-transcribe",
          });

        const rawText = (transcription as unknown as {text?: string}).text;
        const chunkText =
          typeof rawText === "string" && rawText.trim().length > 0 ?
            rawText.trim() :
            "";

        if (chunkText) {
          chunkTranscripts.push(chunkText);
        } else {
          console.warn(
            `Empty transcript returned for chunk ${i + 1}/${
              chunkPaths.length
            } of lecture ${lectureId}`
          );
        }
      }

      const transcriptText = chunkTranscripts.join("\n\n").trim();
      const transcriptFormatted = formatTranscriptParagraphs(
        transcriptText,
        3,
        5
      );

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
          transcriptFormatted,
          status: "transcribed", // transcript is ready; summary can run next
          processedAt: admin.firestore.FieldValue.serverTimestamp(),
          durationMinutes,
          chargedMinutes,
        },
        {merge: true}
      );
    } catch (err: unknown) {
      console.error("Error in onAudioUpload:", err);

      if (err instanceof QuotaError) {
        await lectureRef.set(
          {
            status: "blocked_quota",
            quotaReason: err.reason,
            durationMinutes,
            chargedMinutes: 0,
          },
          {merge: true}
        );
        return;
      }

      const message =
        err instanceof Error ?
          err.message :
          "Transcription failed";

      // Refund any debited minutes on failure
      if (chargedMinutes > 0) {
        try {
          await db.runTransaction(async (tx) => {
            const snap = await tx.get(userRef);
            if (!snap.exists) {
              return;
            }
            const data = (snap.data() as UserData) ?? {};
            const reset = resetMonthlyIfNeeded(tx, userRef, data, now);
            const plan = data.plan === "premium" ? "premium" : "free";

            const monthlyUsed =
              typeof reset.monthlyMinutesUsed === "number" ?
                reset.monthlyMinutesUsed :
                0;

            const updates: Record<string, unknown> = {
              monthlyMinutesUsed: Math.max(0, monthlyUsed - chargedMinutes),
              monthlyKey: reset.monthlyKey,
              periodStart: admin.firestore.Timestamp.fromDate(
                reset.periodStart
              ),
              renewsAt: admin.firestore.Timestamp.fromDate(reset.renewsAt),
            };

            if (plan === "free") {
              const lifetimeUsed =
                typeof data.freeLifetimeMinutesUsed === "number" ?
                  data.freeLifetimeMinutesUsed :
                  0;
              updates.freeLifetimeMinutesUsed = Math.max(
                0,
                lifetimeUsed - chargedMinutes
              );
            }

            tx.update(userRef, updates);
          });
        } catch (refundErr: unknown) {
          console.error("Refund failed:", refundErr);
        }
      }

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
        for (const chunkPath of chunkPaths) {
          if (fs.existsSync(chunkPath)) {
            fs.unlinkSync(chunkPath);
          }
        }
      } catch (cleanupErr: unknown) {
        console.error("Error cleaning up temp file:", cleanupErr);
      }
    }
  }
);

/**
 * Delete a user's account and all associated data.
 *
 * @param {Request} req Express request.
 * @param {Response} res Express response.
 */
export const deleteAccount = onRequest(async (req: Request, res: Response) => {
  if (req.method !== "POST") {
    res.status(405).send("Method not allowed.");
    return;
  }

  const authHeader = req.headers.authorization ?? "";
  const match = authHeader.match(/^Bearer (.+)$/);
  if (!match) {
    res.status(401).send("Missing Authorization header.");
    return;
  }

  let uid = "";
  try {
    const decoded = await admin.auth().verifyIdToken(match[1]);
    uid = decoded.uid;
  } catch (error) {
    logger.warn("Invalid auth token for deleteAccount.", error);
    res.status(401).send("Invalid auth token.");
    return;
  }

  try {
    await deleteUserData(uid);
    await deleteUserFeedback(uid);
    await deleteUserAudio(uid);
    await admin.auth().deleteUser(uid);
    res.status(200).json({ok: true});
  } catch (error) {
    logger.error("deleteAccount failed.", error);
    res.status(500).json({ok: false, error: "delete_failed"});
  }
});

/**
 * Remove the user document tree from Firestore.
 *
 * @param {string} uid Firebase Auth user id.
 * @return {Promise<void>} Resolves when deletion completes.
 */
async function deleteUserData(uid: string): Promise<void> {
  const userRef = db.collection("users").doc(uid);
  await db.recursiveDelete(userRef);
}

/**
 * Delete all feedback documents created by the user.
 *
 * @param {string} uid Firebase Auth user id.
 * @return {Promise<void>} Resolves when deletion completes.
 */
async function deleteUserFeedback(uid: string): Promise<void> {
  const snapshot = await db
    .collection("feedback")
    .where("userId", "==", uid)
    .get();
  if (snapshot.empty) {
    return;
  }

  let batch = db.batch();
  let batchCount = 0;

  for (const doc of snapshot.docs) {
    batch.delete(doc.ref);
    batchCount += 1;
    if (batchCount >= 450) {
      await batch.commit();
      batch = db.batch();
      batchCount = 0;
    }
  }

  if (batchCount > 0) {
    await batch.commit();
  }
}

/**
 * Delete all audio files stored for the user.
 *
 * @param {string} uid Firebase Auth user id.
 * @return {Promise<void>} Resolves when deletion completes.
 */
async function deleteUserAudio(uid: string): Promise<void> {
  const bucket = admin.storage().bucket(storageBucketName);
  await bucket.deleteFiles({prefix: `audio/${uid}/`});
}

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
        durationMinutes: lecture.durationMinutes,
        chargedMinutes: lecture.chargedMinutes,
        quotaReason: admin.firestore.FieldValue.delete(),
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

export const translateSummary = onDocumentWritten(
  {
    document: "users/{userId}/lectures/{lectureId}",
    region: "us-central1",
    secrets: [openaiKey],
    timeoutSeconds: 300,
    memory: "512MiB",
  },
  async (event) => {
    const afterSnap = event.data?.after;
    if (!afterSnap?.exists) {
      return;
    }

    const lecture = afterSnap.data();
    if (!lecture?.summary) {
      return;
    }

    const requestedLanguages = extractTranslationCodes(
      lecture.summaryTranslationRequests
    ).filter((code) => isSupportedTranslationLanguage(code));

    const pendingLanguages = requestedLanguages.filter((code) =>
      !hasTranslationEntry(lecture.summaryTranslations, code) &&
      !hasTranslationFlag(lecture.summaryTranslationInProgress, code)
    );

    if (pendingLanguages.length === 0) {
      return;
    }

    const languageCode = pendingLanguages[0];
    const languageName = SUMMARY_TRANSLATION_LANGUAGES[languageCode];
    const docRef = afterSnap.ref;
    if (!languageName) {
      await docRef.update({
        [`summaryTranslationRequests.${languageCode}`]:
          admin.firestore.FieldValue.delete(),
        [`summaryTranslationErrors.${languageCode}`]:
          "Unsupported translation language",
      });
      return;
    }

    const lockAcquired = await db.runTransaction(async (tx) => {
      const snap = await tx.get(docRef);
      const current = snap.data();
      if (!snap.exists || !current?.summary) {
        return false;
      }

      if (
        !hasTranslationFlag(current.summaryTranslationRequests, languageCode)
      ) {
        return false;
      }

      if (hasTranslationEntry(current.summaryTranslations, languageCode)) {
        return false;
      }

      if (
        hasTranslationFlag(current.summaryTranslationInProgress, languageCode)
      ) {
        return false;
      }

      tx.update(docRef, {
        [`summaryTranslationInProgress.${languageCode}`]: true,
      });

      return true;
    });

    if (!lockAcquired) {
      return;
    }

    try {
      const sourceSummary = coerceSummaryForTranslation(lecture.summary);
      if (!sourceSummary) {
        throw new Error("Summary schema invalid for translation");
      }

      const openai = new OpenAI({
        apiKey: openaiKey.value(),
      });

      const translated = await translateSummaryContent(
        openai,
        sourceSummary,
        languageName
      );

      const safeTranslation = enforceTranslatedSummaryLimits(translated);

      await docRef.update({
        [`summaryTranslations.${languageCode}`]: {
          mainTheme: safeTranslation.mainTheme,
          keyPoints: safeTranslation.keyPoints,
          explicitAyatOrHadith: safeTranslation.explicitAyatOrHadith,
          weeklyActions: safeTranslation.weeklyActions,
          generatedAt: admin.firestore.FieldValue.serverTimestamp(),
          model: SUMMARY_MODEL,
        },
        [`summaryTranslationInProgress.${languageCode}`]:
          admin.firestore.FieldValue.delete(),
        [`summaryTranslationRequests.${languageCode}`]:
          admin.firestore.FieldValue.delete(),
        [`summaryTranslationErrors.${languageCode}`]:
          admin.firestore.FieldValue.delete(),
      });
    } catch (err: unknown) {
      console.error("Error in translateSummary:", err);

      const message =
        err instanceof Error ? err.message : "Translation failed";

      await docRef.update({
        [`summaryTranslationInProgress.${languageCode}`]:
          admin.firestore.FieldValue.delete(),
        [`summaryTranslationRequests.${languageCode}`]:
          admin.firestore.FieldValue.delete(),
        [`summaryTranslationErrors.${languageCode}`]: message,
      });
    }
  }
);

export const notifySummaryReady = onDocumentWritten(
  {
    document: "users/{userId}/lectures/{lectureId}",
    region: "us-central1",
    secrets: [onesignalApiKey],
    timeoutSeconds: 60,
    memory: "256MiB",
  },
  async (event) => {
    const afterSnap = event.data?.after;
    if (!afterSnap?.exists) {
      return;
    }

    const beforeStatus = event.data?.before?.data()?.status;
    const afterData = afterSnap.data();
    if (!afterData) {
      return;
    }
    const afterStatus = afterData.status;

    if (afterStatus !== "ready" || beforeStatus === "ready") {
      return;
    }

    if (!afterData.summary) {
      logger.warn("Summary ready without summary content", {
        userId: event.params.userId,
        lectureId: event.params.lectureId,
      });
      return;
    }

    if (afterData.summaryNotificationSentAt) {
      return;
    }

    const {userId, lectureId} = event.params;
    const docRef = afterSnap.ref;

    const lockAcquired = await db.runTransaction(async (tx) => {
      const snap = await tx.get(docRef);
      const current = snap.data();
      if (!snap.exists) {
        return false;
      }
      if (current?.status !== "ready") {
        return false;
      }
      if (current?.summaryNotificationSentAt) {
        return false;
      }
      if (current?.summaryNotificationInProgress === true) {
        return false;
      }

      tx.update(docRef, {
        summaryNotificationInProgress: true,
        summaryNotificationLastAttemptAt:
          admin.firestore.FieldValue.serverTimestamp(),
        summaryNotificationError: admin.firestore.FieldValue.delete(),
        summaryNotificationSkippedAt: admin.firestore.FieldValue.delete(),
        summaryNotificationSkipReason: admin.firestore.FieldValue.delete(),
      });

      return true;
    });

    if (!lockAcquired) {
      return;
    }

    const userSnap = await db.collection("users").doc(userId).get();
    if (!userSnap.exists) {
      await docRef.update({
        summaryNotificationInProgress: admin.firestore.FieldValue.delete(),
        summaryNotificationError: "user_missing",
      });
      return;
    }

    const userData = userSnap.data() as UserDoc;
    const preference = userData.preferences?.notificationPreference;
    if (preference !== "push" && preference !== "provisional") {
      await docRef.update({
        summaryNotificationInProgress: admin.firestore.FieldValue.delete(),
        summaryNotificationSkippedAt:
          admin.firestore.FieldValue.serverTimestamp(),
        summaryNotificationSkipReason: "preference_disabled",
      });
      return;
    }

    const apiKey = onesignalApiKey.value();
    if (!apiKey) {
      await docRef.update({
        summaryNotificationInProgress: admin.firestore.FieldValue.delete(),
        summaryNotificationError: "missing_onesignal_api_key",
      });
      return;
    }

    const lectureTitle =
      typeof afterData.title === "string" ? afterData.title.trim() : "";

    const result = await sendSummaryReadyNotification(
      userId,
      lectureId,
      lectureTitle,
      preference,
      apiKey
    );

    if (result.success) {
      const updates: Record<string, unknown> = {
        summaryNotificationSentAt:
          admin.firestore.FieldValue.serverTimestamp(),
        summaryNotificationPreference: preference,
        summaryNotificationInProgress: admin.firestore.FieldValue.delete(),
        summaryNotificationError: admin.firestore.FieldValue.delete(),
      };

      if (result.id) {
        updates.summaryNotificationId = result.id;
      }

      await docRef.update(updates);
      return;
    }

    await docRef.update({
      summaryNotificationInProgress: admin.firestore.FieldValue.delete(),
      summaryNotificationError: result.error ?? "onesignal_error",
    });
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
 * Validate if a language code is supported for summary translation.
 *
 * @param {string} code Language code to validate.
 * @return {boolean} True when supported.
 */
function isSupportedTranslationLanguage(
  code: string
): code is keyof typeof SUMMARY_TRANSLATION_LANGUAGES {
  return Object.prototype.hasOwnProperty.call(
    SUMMARY_TRANSLATION_LANGUAGES,
    code
  );
}

/**
 * Extract requested translation codes from a request payload.
 *
 * @param {unknown} raw Raw request payload from Firestore.
 * @return {string[]} List of requested language codes.
 */
function extractTranslationCodes(raw: unknown): string[] {
  if (!raw) {
    return [];
  }
  if (typeof raw === "string") {
    return [raw];
  }
  if (Array.isArray(raw)) {
    return raw.filter((item) => typeof item === "string") as string[];
  }
  if (typeof raw === "object") {
    return Object.keys(raw as Record<string, unknown>);
  }
  return [];
}

/**
 * Check if a translation request or in-progress flag is set for a language.
 *
 * @param {unknown} raw Raw request payload.
 * @param {string} code Language code to check.
 * @return {boolean} True when the request or flag is present.
 */
function hasTranslationFlag(raw: unknown, code: string): boolean {
  if (!raw) {
    return false;
  }
  if (typeof raw === "string") {
    return raw === code;
  }
  if (Array.isArray(raw)) {
    return raw.includes(code);
  }
  if (typeof raw === "object") {
    const obj = raw as Record<string, unknown>;
    return obj[code] === true;
  }
  return false;
}

/**
 * Check if a translation already exists for a language.
 *
 * @param {unknown} raw Raw translation map.
 * @param {string} code Language code to check.
 * @return {boolean} True when translation exists.
 */
function hasTranslationEntry(raw: unknown, code: string): boolean {
  if (!raw || typeof raw !== "object" || Array.isArray(raw)) {
    return false;
  }
  const obj = raw as Record<string, unknown>;
  return Boolean(obj[code]);
}

/**
 * Validate and coerce summary payload into a translation-ready shape.
 *
 * @param {unknown} summary Raw summary payload from Firestore.
 * @return {Object|null} Normalized summary or null if invalid.
 */
function coerceSummaryForTranslation(summary: unknown): {
  mainTheme: string;
  keyPoints: string[];
  explicitAyatOrHadith: string[];
  weeklyActions: string[];
} | null {
  if (!summary || typeof summary !== "object") {
    return null;
  }

  const obj = summary as {
    mainTheme?: unknown;
    keyPoints?: unknown;
    explicitAyatOrHadith?: unknown;
    weeklyActions?: unknown;
  };

  if (typeof obj.mainTheme !== "string") {
    return null;
  }

  if (!Array.isArray(obj.keyPoints) ||
    !obj.keyPoints.every((item) => typeof item === "string")) {
    return null;
  }

  if (!Array.isArray(obj.explicitAyatOrHadith) ||
    !obj.explicitAyatOrHadith.every((item) => typeof item === "string")) {
    return null;
  }

  if (!Array.isArray(obj.weeklyActions) ||
    !obj.weeklyActions.every((item) => typeof item === "string")) {
    return null;
  }

  return {
    mainTheme: obj.mainTheme,
    keyPoints: obj.keyPoints,
    explicitAyatOrHadith: obj.explicitAyatOrHadith,
    weeklyActions: obj.weeklyActions,
  };
}

/**
 * Translate a structured summary into the requested language.
 *
 * @param {OpenAI} openai OpenAI client instance.
 * @param {Object} summary Structured summary to translate.
 * @param {string} languageName Human-readable language name.
 * @return {Promise<SummaryShape>} Raw translated summary JSON.
 */
async function translateSummaryContent(
  openai: OpenAI,
  summary: {
    mainTheme: string;
    keyPoints: string[];
    explicitAyatOrHadith: string[];
    weeklyActions: string[];
  },
  languageName: string
): Promise<SummaryShape> {
  const translationInstructions = [
    `Translate the khutbah summary into ${languageName}.`,
    "Keep the meaning, tone, and religious content unchanged.",
    "Do not add, remove, or infer any information.",
    "Return only valid JSON with the required keys.",
  ].join("\n");

  const text = await runJsonSummaryRequest(
    openai,
    [
      {role: "system", content: SUMMARY_TRANSLATION_SYSTEM_PROMPT},
      {role: "user", content: translationInstructions},
      {role: "user", content: JSON.stringify(summary)},
    ],
    SUMMARY_TRANSLATION_MAX_OUTPUT_TOKENS,
    `Translation (${languageName})`
  );

  let parsed: unknown;
  try {
    parsed = JSON.parse(text);
  } catch {
    throw new Error("Translation: Model did not return valid JSON");
  }

  return parsed as SummaryShape;
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
 * Format a transcript into readable paragraphs by sentence count.
 *
 * @param {string} transcript Full transcript text.
 * @param {number} minSentences Minimum sentences per paragraph.
 * @param {number} maxSentences Maximum sentences per paragraph.
 * @return {string} Paragraph-formatted transcript.
 */
function formatTranscriptParagraphs(
  transcript: string,
  minSentences: number,
  maxSentences: number
): string {
  const normalized = transcript.replace(/\s+/g, " ").trim();
  if (!normalized) {
    return "";
  }

  const sentences: string[] = [];
  let current = "";

  for (let i = 0; i < normalized.length; i++) {
    const ch = normalized[i];
    current += ch;

    if (ch === "." || ch === "!" || ch === "?") {
      const next = normalized[i + 1];
      if (next === " " || next === undefined) {
        const trimmed = current.trim();
        if (trimmed) {
          sentences.push(trimmed);
        }
        current = "";
      }
    }
  }

  const tail = current.trim();
  if (tail) {
    sentences.push(tail);
  }

  if (sentences.length === 0) {
    return normalized;
  }

  const paragraphs: string[] = [];
  let idx = 0;

  while (idx < sentences.length) {
    const remaining = sentences.length - idx;
    let take = Math.min(maxSentences, remaining);

    if (remaining > maxSentences && remaining - take < minSentences) {
      take = Math.max(minSentences, remaining - minSentences);
    }

    const block = sentences.slice(idx, idx + take).join(" ");
    paragraphs.push(block);
    idx += take;
  }

  return paragraphs.join("\n\n");
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
 * Enforce limits and validate the translated summary shape.
 *
 * @param {SummaryShape} summaryObj Translated summary object to enforce.
 * @return {{
 *   mainTheme: string,
 *   keyPoints: string[],
 *   explicitAyatOrHadith: string[],
 *   weeklyActions: string[]
 * }} Summary with enforced limits.
 */
function enforceTranslatedSummaryLimits(summaryObj: SummaryShape): {
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
    logger.error("Invalid translated summary schema", {
      summary: safeJson(summaryObj),
    });
    throw new Error("Invalid translated summary schema");
  }

  const dedupedKeyPoints = dedupeStrings(keyPoints).slice(0, 7);
  const dedupedWeekly = dedupeStrings(weeklyActions).slice(0, 3);
  const dedupedQuotes = dedupeStrings(explicitAyatOrHadith).slice(0, 2);

  const trimmedTheme = truncateWords(mainTheme, 400).trim();
  if (!trimmedTheme) {
    throw new Error("Translated summary missing mainTheme");
  }

  return {
    mainTheme: trimmedTheme,
    keyPoints: dedupedKeyPoints,
    explicitAyatOrHadith: dedupedQuotes,
    weeklyActions: dedupedWeekly,
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

// RevenueCat webhook to set premium plan server-side
type RevenueCatEvent = Record<string, unknown>;
type EntitlementInfo = {
  identifier: string | null;
  startsAt: Date | null;
  expiresAt: Date | null;
  periodType: string | null;
  eventType: string | null;
  updatedAt: Date | null;
};

export const revenueCatWebhook = onRequest(
  {
    region: "us-central1",
    secrets: [rcWebhookSecret],
    timeoutSeconds: 15,
  },
  async (req: Request, res: Response) => {
    if (req.method !== "POST") {
      res.status(405).send("Method Not Allowed");
      return;
    }

    const authHeader = req.header("authorization") ?? "";
    const expected = `Bearer ${rcWebhookSecret.value()}`;
    if (authHeader !== expected) {
      logger.warn("RevenueCat webhook unauthorized", {
        hasAuthHeader: Boolean(authHeader),
      });
      res.status(401).send("Unauthorized");
      return;
    }

    const rawBody = req.body as unknown;
    const eventPayload =
      isPlainRecord((rawBody as {event?: unknown}).event) ?
        ((rawBody as {event: RevenueCatEvent}).event) :
        isPlainRecord(rawBody) ?
          (rawBody as RevenueCatEvent) :
          null;

    if (!eventPayload) {
      res.status(400).send("Invalid webhook payload");
      return;
    }

    const {uid, usedAlias} = extractAppUserId(eventPayload);
    if (!uid) {
      res.status(400).send("Missing app_user_id");
      return;
    }

    const entitlement = extractEntitlementInfo(eventPayload);
    if (!entitlement || entitlement.identifier !== REVENUECAT_ENTITLEMENT_ID) {
      res.status(204).send("Ignored entitlement");
      return;
    }

    const now = new Date();
    const active = isEntitlementActive(
      entitlement.eventType,
      entitlement.expiresAt,
      now
    );

    const periodStart = active ?
      entitlement.startsAt ?? now :
      now;
    const renewsAt = active ?
      entitlement.expiresAt ?? addOneMonth(periodStart) :
      addOneMonth(periodStart);
    const monthlyKey = getMonthlyKey(periodStart);

    const metadata = buildRevenueCatMetadata(
      eventPayload,
      entitlement,
      now
    );

    try {
      await db.runTransaction(async (tx) => {
        const userRef = db.collection("users").doc(uid);
        const updates: Record<string, unknown> = {
          plan: active ? "premium" : "free",
          monthlyKey,
          monthlyMinutesUsed: 0,
          periodStart: admin.firestore.Timestamp.fromDate(periodStart),
          renewsAt: admin.firestore.Timestamp.fromDate(renewsAt),
          ...metadata,
        };

        tx.set(userRef, updates, {merge: true});
      });

      logger.info("RevenueCat webhook processed", {
        uid,
        entitlement: entitlement.identifier,
        eventType: entitlement.eventType ?? null,
        active,
        usedAlias,
      });
      res.status(200).send("ok");
    } catch (err: unknown) {
      logger.error("RevenueCat webhook failed", {
        error: safeJson(err),
        uid,
      });
      res.status(500).send("Internal error");
    }
  }
);

/**
 * Extract Firebase UID from RevenueCat payload, falling back to aliases.
 *
 * @param {RevenueCatEvent} event RevenueCat webhook event payload.
 * @return {{uid: (string|null), usedAlias: boolean}} UID and alias usage.
 */
function extractAppUserId(
  event: RevenueCatEvent
): {uid: string | null; usedAlias: boolean} {
  const direct = getStringField(event, ["app_user_id", "appUserId"]);
  if (direct) {
    return {uid: direct, usedAlias: false};
  }

  const aliases = event.aliases;
  if (Array.isArray(aliases)) {
    for (const alias of aliases) {
      if (typeof alias === "string" && alias.trim()) {
        return {uid: alias.trim(), usedAlias: true};
      }
    }
  }

  return {uid: null, usedAlias: false};
}

/**
 * Parse entitlement details from the RC event.
 *
 * @param {RevenueCatEvent} event RevenueCat webhook event payload.
 * @return {EntitlementInfo|null} Parsed entitlement info or null.
 */
function extractEntitlementInfo(
  event: RevenueCatEvent
): EntitlementInfo | null {
  const entitlementObj = pickEntitlementObject(event);
  const source = entitlementObj ?? event;

  let identifier = getStringField(source, [
    "entitlement_identifier",
    "entitlement_id",
    "identifier",
    "product_identifier",
    "productId",
  ]);

  if (!identifier) {
    const entitlementIds = event.entitlement_ids;
    if (Array.isArray(entitlementIds)) {
      for (const id of entitlementIds) {
        if (typeof id === "string" && id.trim()) {
          identifier = id.trim();
          break;
        }
      }
    }
  }

  if (!identifier) {
    return null;
  }

  const startsAt = parseMillisToDate(
    getNumberField(source, [
      "entitlement_started_at_ms",
      "purchased_at_ms",
      "purchase_date_ms",
      "period_started_at_ms",
    ])
  );

  const expiresAt = parseMillisToDate(
    getNumberField(source, [
      "entitlement_expires_at_ms",
      "expires_at_ms",
      "expiration_at_ms",
      "expiration_date_ms",
      "period_ends_at_ms",
    ])
  );

  const periodType = getStringField(source, [
    "entitlement_period_type",
    "period_type",
  ]);

  const eventType = getStringField(event, ["type", "event_type"]);

  const updatedAt =
    parseMillisToDate(
      getNumberField(source, [
        "processed_at_ms",
        "updated_at_ms",
        "event_timestamp_ms",
      ])
    ) ?? parseMillisToDate(
      getNumberField(event, [
        "event_timestamp_ms",
        "occurred_at_ms",
        "sent_at_ms",
        "timestamp_ms",
      ])
    );

  return {
    identifier,
    startsAt,
    expiresAt,
    periodType,
    eventType,
    updatedAt,
  };
}

/**
 * Locate the entitlement object inside the RC payload.
 *
 * @param {RevenueCatEvent} event RevenueCat webhook event payload.
 * @return {RevenueCatEvent|null} Entitlement record or null.
 */
function pickEntitlementObject(event: RevenueCatEvent): RevenueCatEvent | null {
  const entitlement = event.entitlement;
  if (isPlainRecord(entitlement)) {
    return entitlement;
  }

  const entitlements = event.entitlements;
  if (isPlainRecord(entitlements)) {
    const candidate = (entitlements as Record<string, unknown>)[
      REVENUECAT_ENTITLEMENT_ID
    ];
    if (isPlainRecord(candidate)) {
      return candidate;
    }
  }

  return null;
}

/**
 * Get the first non-empty string field from a set of keys.
 *
 * @param {RevenueCatEvent} source Source object.
 * @param {string[]} keys Candidate keys.
 * @return {string|null} Trimmed string value or null.
 */
function getStringField(
  source: RevenueCatEvent,
  keys: string[]
): string | null {
  for (const key of keys) {
    const value = source?.[key];
    if (typeof value === "string" && value.trim()) {
      return value.trim();
    }
  }
  return null;
}

/**
 * Get the first finite number field (accepts numeric strings) from keys.
 *
 * @param {RevenueCatEvent|null} source Source object.
 * @param {string[]} keys Candidate keys.
 * @return {number|null} Parsed number or null.
 */
function getNumberField(
  source: RevenueCatEvent | null,
  keys: string[]
): number | null {
  if (!source) {
    return null;
  }

  for (const key of keys) {
    const value = source[key];
    if (typeof value === "number" && Number.isFinite(value)) {
      return value;
    }
    if (typeof value === "string" && value.trim()) {
      const parsed = Number(value);
      if (Number.isFinite(parsed)) {
        return parsed;
      }
    }
  }

  return null;
}

/**
 * Convert epoch millis to Date, returning null on invalid input.
 *
 * @param {number|null} value Milliseconds since epoch.
 * @return {Date|null} Date or null.
 */
function parseMillisToDate(value: number | null): Date | null {
  if (value === null) {
    return null;
  }
  const date = new Date(value);
  return Number.isFinite(date.getTime()) ? date : null;
}

/**
 * Determine if the entitlement is currently active.
 *
 * @param {string|null} eventType RevenueCat event type.
 * @param {Date|null} expiresAt Expiration date.
 * @param {Date} now Current time.
 * @return {boolean} True if active.
 */
function isEntitlementActive(
  eventType: string | null,
  expiresAt: Date | null,
  now: Date
): boolean {
  if (eventType && eventType.toUpperCase() === "EXPIRATION") {
    return false;
  }

  if (expiresAt) {
    return expiresAt.getTime() > now.getTime();
  }

  return true;
}

/**
 * Build metadata fields to persist from the RC event.
 *
 * @param {RevenueCatEvent} event RevenueCat payload.
 * @param {EntitlementInfo} entitlement Parsed entitlement info.
 * @param {Date} now Current time fallback.
 * @return {Record<string, unknown>} Metadata to merge.
 */
function buildRevenueCatMetadata(
  event: RevenueCatEvent,
  entitlement: EntitlementInfo,
  now: Date
): Record<string, unknown> {
  const metadata: Record<string, unknown> = {};

  if (entitlement.identifier) {
    metadata.rcEntitlement = entitlement.identifier;
  }
  if (entitlement.periodType) {
    metadata.rcPeriodType = entitlement.periodType;
  }

  const environment = getStringField(event, [
    "environment",
    "app_environment",
  ]);
  if (environment) {
    metadata.rcEnvironment = environment;
  }

  const originalAppUserId = getStringField(event, [
    "original_app_user_id",
    "originalAppUserId",
  ]);
  if (originalAppUserId) {
    metadata.rcOriginalAppUserId = originalAppUserId;
  }

  const updatedAt = entitlement.updatedAt ?? now;
  metadata.rcUpdatedAt = admin.firestore.Timestamp.fromDate(updatedAt);

  return metadata;
}

/**
 * Check for a plain object (non-array).
 *
 * @param {unknown} value Value to test.
 * @return {boolean} True if plain record.
 */
function isPlainRecord(value: unknown): value is RevenueCatEvent {
  return Boolean(
    value &&
      typeof value === "object" &&
      !Array.isArray(value)
  );
}

// Your OneSignal App ID
const ONESIGNAL_APP_ID = "290aa0ce-8c6c-4e7d-84c1-914fbdac66f1";
const adminToken = defineSecret("ADMIN_TOKEN");
const FIRESTORE_BATCH_SIZE = 500;

// ============== TYPES ==============

interface UserPreferences {
  jumuahStartTime?: string;
  jumuahTimezone?: string;
  notificationPreference?: "push" | "provisional" | "no";
}

interface UserDoc {
  preferences?: UserPreferences;
  oneSignal?: {
    externalId?: string;
    oneSignalId?: string;
    pushSubscriptionId?: string;
  };
}

interface ScheduleGroup {
  userIds: string[];
  time: string;
  timezone: string;
  sendAfterUtc: string;
}

interface ValidationResult {
  valid: boolean;
  hours?: number;
  minutes?: number;
  error?: string;
}

interface SendResult {
  success: boolean;
  id?: string;
  error?: string;
  invalidAliases?: string[];
}

// ============== VALIDATION ==============

/**
 * Validate and parse time string.
 * Accepts: "13:15", "1:15", "1:15 PM", "13:15:00"
 * Returns validation result with parsed hours/minutes or error.
 *
 * @param {string} timeStr Time string from user preferences.
 * @return {ValidationResult} Parsed hours/minutes or error details.
 */
function validateAndParseTime(timeStr: string): ValidationResult {
  if (!timeStr || typeof timeStr !== "string") {
    return {
      valid: false,
      error: "Time is empty or not a string",
    };
  }

  const trimmed = timeStr.trim();

  const match12 = trimmed.match(
    /^(\d{1,2}):(\d{2})(?::\d{2})?\s*(AM|PM)$/i
  );
  if (match12) {
    let hours = parseInt(match12[1], 10);
    const minutes = parseInt(match12[2], 10);
    const isPM = match12[3].toUpperCase() === "PM";

    if (hours < 1 || hours > 12 || minutes < 0 || minutes > 59) {
      return {
        valid: false,
        error: `Invalid 12-hour time: ${timeStr}`,
      };
    }

    if (isPM && hours !== 12) hours += 12;
    if (!isPM && hours === 12) hours = 0;

    return {
      valid: true,
      hours,
      minutes,
    };
  }

  const match24 = trimmed.match(/^(\d{1,2}):(\d{2})(?::\d{2})?$/);
  if (match24) {
    let hours = parseInt(match24[1], 10);
    const minutes = parseInt(match24[2], 10);

    if (hours < 0 || hours > 23 || minutes < 0 || minutes > 59) {
      return {
        valid: false,
        error: `Invalid 24-hour time: ${timeStr}`,
      };
    }

    // Assume PM for ambiguous times (e.g., "1:00" → 13:00) since Jumu'ah
    // selections are midday slots.
    if (hours >= 1 && hours <= 11) {
      hours += 12;
    }

    return {
      valid: true,
      hours,
      minutes,
    };
  }

  return {
    valid: false,
    error: `Unrecognized time format: ${timeStr}`,
  };
}

/**
 * Validate timezone string using Luxon.
 *
 * @param {string} tz IANA timezone string.
 * @return {boolean} True if valid timezone.
 */
function isValidTimezone(tz: string): boolean {
  if (!tz || typeof tz !== "string") return false;
  const dt = DateTime.now().setZone(tz);
  return dt.isValid;
}

// ============== DATE/TIME CALCULATIONS ==============

/**
 * Get the next Friday, including today if it's Friday and before cutoff.
 *
 * @param {DateTime} fromDate Starting date.
 * @param {number} includeTodayBeforeHour Hour cutoff when day is Friday.
 * @return {DateTime} The next Friday in the given zone.
 */
function getNextFriday(
  fromDate: DateTime,
  includeTodayBeforeHour = 10
): DateTime {
  const dayOfWeek = fromDate.weekday;

  if (dayOfWeek === 5) {
    if (fromDate.hour < includeTodayBeforeHour) {
      return fromDate.startOf("day");
    }
    return fromDate.plus({days: 7}).startOf("day");
  }

  const daysUntilFriday = (5 - dayOfWeek + 7) % 7;
  return fromDate.plus({days: daysUntilFriday || 7}).startOf("day");
}

/**
 * Calculate the exact UTC timestamp for sending the reminder.
 * Uses Luxon for robust timezone and DST handling.
 *
 * @param {string} jumuahTime Local Jumu'ah start time.
 * @param {string} timezone IANA timezone.
 * @param {number} minutesBefore Minutes before Jumu'ah to send.
 * @param {DateTime=} referenceDate Optional reference UTC time.
 * @return {string|null} ISO string for send_after or null on error.
 */
function calculateSendTime(
  jumuahTime: string,
  timezone: string,
  minutesBefore = 3,
  referenceDate?: DateTime
): string | null {
  if (!isValidTimezone(timezone)) {
    logger.error(`Invalid timezone: ${timezone}`);
    return null;
  }

  const parsed = validateAndParseTime(jumuahTime);
  if (
    !parsed.valid ||
    parsed.hours === undefined ||
    parsed.minutes === undefined
  ) {
    logger.error(`Invalid time format: ${jumuahTime} - ${parsed.error}`);
    return null;
  }

  const now = referenceDate || DateTime.utc();
  const nowInTz = now.setZone(timezone);
  const friday = getNextFriday(nowInTz);

  const jumuahDateTime = friday.set({
    hour: parsed.hours,
    minute: parsed.minutes,
    second: 0,
    millisecond: 0,
  });

  const reminderTime = jumuahDateTime.minus({minutes: minutesBefore});
  return reminderTime.toUTC().toISO();
}

/**
 * Create a unique key for grouping users.
 *
 * @param {string} time Local Jumu'ah time.
 * @param {string} timezone User timezone.
 * @return {string} Unique grouping key.
 */
function getGroupKey(time: string, timezone: string): string {
  return `${time}|${timezone}`;
}

// ============== ONESIGNAL API ==============

/**
 * Send scheduled notification via OneSignal.
 *
 * @param {string[]} userIds OneSignal external IDs.
 * @param {string} sendAfterUtc ISO send_after in UTC.
 * @param {string} apiKey OneSignal REST API key.
 * @return {Promise<SendResult>} OneSignal response outcome.
 */
async function sendJumuahNotification(
  userIds: string[],
  sendAfterUtc: string,
  apiKey: string
): Promise<SendResult> {
  const payload = {
    app_id: ONESIGNAL_APP_ID,
    include_aliases: {
      external_id: userIds,
    },
    target_channel: "push",
    headings: {
      en: "Jumu'ah Reminder 🕌",
    },
    contents: {
      en: "Headed to Jumu'ah? Use Khutbah Notes to capture today's khutbah!",
    },
    send_after: sendAfterUtc,
    collapse_id: `jumuah-${sendAfterUtc.substring(0, 16)}`,
    ttl: 7200,
    ios_interruption_level: "time_sensitive",
  };

  try {
    const res = await fetch("https://api.onesignal.com/notifications?c=push", {
      method: "POST",
      headers: {
        "Authorization": `Key ${apiKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify(payload),
    });

    const data = await res.json();

    if (!res.ok) {
      logger.error("OneSignal API error:", data);
      return {success: false, error: JSON.stringify(data)};
    }

    const invalidAliases = data.errors?.invalid_aliases?.external_id;
    if (invalidAliases?.length) {
      logger.warn(`${invalidAliases.length} users not found in OneSignal`);
    }

    return {
      success: true,
      id: data.id,
      invalidAliases,
    };
  } catch (error) {
    return {success: false, error: String(error)};
  }
}

/**
 * Send a summary-ready notification via OneSignal.
 *
 * @param {string} userId OneSignal external ID.
 * @param {string} lectureId Lecture document ID.
 * @param {string} lectureTitle Lecture title (optional).
 * @param {"push" | "provisional"} preference Notification preference.
 * @param {string} apiKey OneSignal REST API key.
 * @return {Promise<SendResult>} OneSignal response outcome.
 */
async function sendSummaryReadyNotification(
  userId: string,
  lectureId: string,
  lectureTitle: string,
  preference: "push" | "provisional",
  apiKey: string
): Promise<SendResult> {
  const trimmedTitle = lectureTitle.trim();
  const body = trimmedTitle.length > 0 ?
    `Your summary for "${trimmedTitle}" is ready.` :
    "Your khutbah summary is ready.";

  const payload = {
    app_id: ONESIGNAL_APP_ID,
    include_aliases: {
      external_id: [userId],
    },
    target_channel: "push",
    headings: {
      en: "Summary Ready",
    },
    contents: {
      en: body,
    },
    data: {
      type: "summary_ready",
      lectureId,
    },
    collapse_id: `summary-ready-${lectureId}`,
    ttl: 86400,
    ios_interruption_level: preference === "provisional" ? "passive" : "active",
  };

  try {
    const res = await fetch("https://api.onesignal.com/notifications?c=push", {
      method: "POST",
      headers: {
        "Authorization": `Key ${apiKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify(payload),
    });

    const data = await res.json();

    if (!res.ok) {
      logger.error("OneSignal API error (summary ready):", data);
      return {success: false, error: JSON.stringify(data)};
    }

    const invalidAliases = data.errors?.invalid_aliases?.external_id;
    if (invalidAliases?.length) {
      logger.warn(
        `${invalidAliases.length} users not found in OneSignal (summary ready)`
      );
    }

    return {
      success: true,
      id: data.id,
      invalidAliases,
    };
  } catch (error) {
    return {success: false, error: String(error)};
  }
}

// ============== SCHEDULED FUNCTIONS ==============

/**
 * Core scheduling runner used by both cron jobs.
 *
 * @param {string} runLabel Label for logging (e.g., "Thursday run").
 * @param {DateTime} now Current UTC time reference.
 * @return {Promise<void>} Resolves when scheduling completes.
 */
async function runJumuahReminderScheduling(
  runLabel: string,
  now: DateTime
): Promise<void> {
  const dayName = now.weekdayLong;
  logger.info(
    `Starting Jumu'ah reminder scheduling (${runLabel}, ${dayName} run)...`
  );

  const apiKey = onesignalApiKey.value();
  if (!apiKey) {
    logger.error("ONESIGNAL_API_KEY not configured");
    return;
  }

  const todayKey = now.toISODate();
  const existingRun = await db
    .collection("notificationLogs")
    .where("type", "==", "jumuah_reminder")
    .where("runDate", "==", todayKey)
    .where("success", "==", true)
    .limit(1)
    .get();

  if (!existingRun.empty) {
    logger.info(`Already ran successfully today (${todayKey}), skipping`);
    return;
  }

  try {
    const groups: Map<string, ScheduleGroup> = new Map();
    let lastDoc: FirebaseFirestore.QueryDocumentSnapshot | null = null;
    let totalProcessed = 0;
    let skippedNoPrefs = 0;
    let skippedNotEnabled = 0;
    let skippedInvalidTime = 0;
    let skippedInvalidTz = 0;

    let hasMore = true;
    while (hasMore) {
      let query = db
        .collection("users")
        .orderBy("__name__")
        .limit(FIRESTORE_BATCH_SIZE);

      if (lastDoc) {
        query = query.startAfter(lastDoc);
      }

      const snapshot = await query.get();

      if (snapshot.empty) {
        hasMore = false;
        break;
      }

      lastDoc = snapshot.docs[snapshot.docs.length - 1];

      for (const doc of snapshot.docs) {
        totalProcessed++;
        const data = doc.data() as UserDoc;
        const prefs = data.preferences;

        if (!prefs) {
          skippedNoPrefs++;
          continue;
        }

        const notifPref = prefs.notificationPreference;
        if (notifPref !== "push" && notifPref !== "provisional") {
          skippedNotEnabled++;
          continue;
        }

        const jumuahTime = prefs.jumuahStartTime;
        const timezone = prefs.jumuahTimezone;

        if (!jumuahTime) {
          skippedInvalidTime++;
          continue;
        }

        if (!timezone || !isValidTimezone(timezone)) {
          skippedInvalidTz++;
          continue;
        }

        const sendAfterUtc = calculateSendTime(jumuahTime, timezone, 3, now);
        if (!sendAfterUtc) {
          skippedInvalidTime++;
          continue;
        }

        if (DateTime.fromISO(sendAfterUtc) < now) {
          logger.debug("Skipping past send time", {
            userId: doc.id,
            sendAfterUtc,
          });
          continue;
        }

        const groupKey = getGroupKey(jumuahTime, timezone);
        if (!groups.has(groupKey)) {
          groups.set(groupKey, {
            userIds: [],
            time: jumuahTime,
            timezone,
            sendAfterUtc,
          });
        }
        const targetGroup = groups.get(groupKey);
        if (targetGroup) {
          targetGroup.userIds.push(doc.id);
        }
      }

      if (totalProcessed > 100000) {
        logger.warn("Reached 100k user limit, stopping pagination");
        break;
      }
    }

    logger.info("Processed users for reminders", {
      totalProcessed,
      groupCount: groups.size,
    });
    logger.info("Skipped users", {
      noPrefs: skippedNoPrefs,
      notEnabled: skippedNotEnabled,
      invalidTime: skippedInvalidTime,
      invalidTz: skippedInvalidTz,
    });

    if (groups.size === 0) {
      logger.info("No users to notify");
      await logRun(now, true, 0, 0, totalProcessed, {
        skipped: {
          noPrefs: skippedNoPrefs,
          notEnabled: skippedNotEnabled,
          invalidTime: skippedInvalidTime,
          invalidTz: skippedInvalidTz,
        },
      });
      return;
    }

    let successfulBatches = 0;
    let failedBatches = 0;
    let totalUsersTargeted = 0;
    let totalInvalidAliases = 0;

    for (const [, group] of groups) {
      for (let i = 0; i < group.userIds.length; i += 2000) {
        const batch = group.userIds.slice(i, i + 2000);

        const result = await sendJumuahNotification(
          batch,
          group.sendAfterUtc,
          apiKey
        );

        if (result.success) {
          successfulBatches++;
          totalUsersTargeted += batch.length;
          if (result.invalidAliases) {
            totalInvalidAliases += result.invalidAliases.length;
          }
          logger.info("Scheduled batch", {
            count: batch.length,
            time: group.time,
            timezone: group.timezone,
            sendAfterUtc: group.sendAfterUtc,
          });
        } else {
          failedBatches++;
          logger.error("Failed batch", {
            time: group.time,
            timezone: group.timezone,
            error: result.error,
          });
        }

        await new Promise((r) => setTimeout(r, 50));
      }
    }

    const success = failedBatches === 0;
    await logRun(
      now,
      success,
      successfulBatches,
      totalUsersTargeted,
      totalProcessed,
      {
        failedBatches,
        invalidAliases: totalInvalidAliases,
        skipped: {
          noPrefs: skippedNoPrefs,
          notEnabled: skippedNotEnabled,
          invalidTime: skippedInvalidTime,
          invalidTz: skippedInvalidTz,
        },
      }
    );

    logger.info("Done scheduling", {
      successfulBatches,
      totalUsersTargeted,
      totalInvalidAliases,
    });
  } catch (error) {
    logger.error("Error scheduling Jumu'ah reminders:", error);
    await logRun(now, false, 0, 0, 0, {error: String(error)});
    throw error;
  }
}

export const scheduleJumuahReminders = onSchedule(
  {
    schedule: "0 20 * * 4",
    timeZone: "UTC",
    secrets: [onesignalApiKey],
    timeoutSeconds: 540,
    retryCount: 2,
    memory: "512MiB",
  },
  async () => {
    await runJumuahReminderScheduling("Thursday 20:00 UTC", DateTime.utc());
  }
);

export const scheduleJumuahRemindersCatchup = onSchedule(
  {
    schedule: "0 6 * * 5",
    timeZone: "UTC",
    secrets: [onesignalApiKey],
    timeoutSeconds: 540,
    retryCount: 2,
    memory: "512MiB",
  },
  async () => {
    await runJumuahReminderScheduling(
      "Friday 06:00 UTC catch-up",
      DateTime.utc()
    );
  }
);

/**
 * Log the run result to Firestore.
 *
 * @param {DateTime} runTime Time of the run.
 * @param {boolean} success Whether the run fully succeeded.
 * @param {number} batches Number of batches sent.
 * @param {number} users Number of users targeted.
 * @param {number} totalProcessed Total users processed.
 * @param {Record<string, unknown>=} extra Optional extra metadata.
 * @return {Promise<void>} Resolves when log is written.
 */
async function logRun(
  runTime: DateTime,
  success: boolean,
  batches: number,
  users: number,
  totalProcessed: number,
  extra?: Record<string, unknown>
): Promise<void> {
  try {
    await db.collection("notificationLogs").add({
      type: "jumuah_reminder",
      runDate: runTime.toISODate(),
      timestamp: admin.firestore.FieldValue.serverTimestamp(),
      success,
      batchesSent: batches,
      usersTargeted: users,
      usersProcessed: totalProcessed,
      ...extra,
    });
  } catch (e) {
    logger.error("Failed to log run:", e);
  }
}

// ============== ADMIN-ONLY ENDPOINTS ==============

/**
 * Test endpoint - protected with admin token.
 */
export const testJumuahReminder = onRequest(
  {
    secrets: [onesignalApiKey, adminToken],
    timeoutSeconds: 60,
  },
  async (req, res) => {
    const providedToken = req.headers["x-admin-token"] as string | undefined;
    const expectedToken = adminToken.value();

    if (!expectedToken) {
      if (process.env.FUNCTIONS_EMULATOR !== "true") {
        res.status(403).json({error: "Endpoint disabled in production"});
        return;
      }
    } else if (providedToken !== expectedToken) {
      res.status(403).json({error: "Invalid admin token"});
      return;
    }

    if (req.method !== "POST") {
      res.status(405).send("POST only");
      return;
    }

    const {userId} = req.body || {};
    if (!userId || typeof userId !== "string") {
      res.status(400).json({error: "Missing or invalid userId"});
      return;
    }

    const userDoc = await db.collection("users").doc(userId).get();
    if (!userDoc.exists) {
      res.status(404).json({error: "User not found"});
      return;
    }

    const apiKey = onesignalApiKey.value();

    try {
      const response = await fetch("https://api.onesignal.com/notifications?c=push", {
        method: "POST",
        headers: {
          "Authorization": `Key ${apiKey}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          app_id: ONESIGNAL_APP_ID,
          include_aliases: {external_id: [userId]},
          target_channel: "push",
          headings: {en: "🧪 Test: Jumu'ah Reminder"},
          contents: {en: "Test notification - Try Khutbah Notes today."},
        }),
      });

      const data = await response.json();
      res
        .status(response.ok ? 200 : 400)
        .json({success: response.ok, ...data});
    } catch (error) {
      res.status(500).json({error: String(error)});
    }
  }
);

/**
 * Preview endpoint - protected with admin token.
 * Shows what would be scheduled without sending.
 */
export const previewJumuahReminders = onRequest(
  {
    secrets: [adminToken],
    timeoutSeconds: 60,
  },
  async (req, res) => {
    const providedToken = req.headers["x-admin-token"] as string | undefined;
    const expectedToken = adminToken.value();

    if (!expectedToken) {
      if (process.env.FUNCTIONS_EMULATOR !== "true") {
        res.status(403).json({error: "Endpoint disabled in production"});
        return;
      }
    } else if (providedToken !== expectedToken) {
      res.status(403).json({error: "Invalid admin token"});
      return;
    }

    try {
      const now = DateTime.utc();
      const groups: Map<string, ScheduleGroup> = new Map();
      let skipped = 0;

      const snapshot = await db.collection("users").limit(1000).get();

      for (const doc of snapshot.docs) {
        const data = doc.data() as UserDoc;
        const prefs = data.preferences;

        if (!prefs) continue;
        const notifPref = prefs.notificationPreference;
        if (!["push", "provisional"].includes(notifPref ?? "")) {
          skipped++;
          continue;
        }
        if (!prefs.jumuahStartTime || !prefs.jumuahTimezone) {
          skipped++;
          continue;
        }
        if (!isValidTimezone(prefs.jumuahTimezone)) {
          skipped++;
          continue;
        }

        const sendAfterUtc = calculateSendTime(
          prefs.jumuahStartTime,
          prefs.jumuahTimezone,
          3,
          now
        );
        if (!sendAfterUtc) {
          skipped++;
          continue;
        }

        const groupKey = getGroupKey(
          prefs.jumuahStartTime,
          prefs.jumuahTimezone
        );

        if (!groups.has(groupKey)) {
          groups.set(groupKey, {
            userIds: [],
            time: prefs.jumuahStartTime,
            timezone: prefs.jumuahTimezone,
            sendAfterUtc,
          });
        }

        const previewGroup = groups.get(groupKey);
        if (previewGroup) {
          previewGroup.userIds.push(doc.id);
        }
      }

      const preview = Array.from(groups.values()).map((g) => ({
        jumuahTime: g.time,
        timezone: g.timezone,
        reminderSendsAtUtc: g.sendAfterUtc,
        userCount: g.userIds.length,
      }));

      res.json({
        nextFriday: getNextFriday(now).toISODate(),
        currentTimeUtc: now.toISO(),
        totalGroups: groups.size,
        totalUsers: preview.reduce((sum, g) => sum + g.userCount, 0),
        skippedUsers: skipped,
        note:
          snapshot.size === 1000 ? "Limited to first 1000 users" : undefined,
        groups: preview,
      });
    } catch (error) {
      res.status(500).json({error: String(error)});
    }
  }
);
