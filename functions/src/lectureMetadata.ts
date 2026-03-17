import * as admin from "firebase-admin";
import * as path from "path";

export const DEFAULT_LECTURE_TITLE = "Khutbah Summary";

/**
 * Parse the storage object path for top-level lecture uploads.
 *
 * Accepted shape: audio/{userId}/{lectureFile}
 *
 * @param {string} filePath Storage object path.
 * @return {{userId: string, lectureId: string} | null} Parsed identifiers.
 */
export function parseLectureAudioUploadPath(
  filePath: string
): {userId: string; lectureId: string} | null {
  const parts = filePath.split("/");
  if (parts.length !== 3) {
    return null;
  }

  const [root, userId, fileName] = parts;
  if (root !== "audio" || !userId || !fileName) {
    return null;
  }

  const extension = path.extname(fileName);
  const lectureId = fileName.replace(extension, "").trim();
  if (!lectureId) {
    return null;
  }

  return {
    userId,
    lectureId,
  };
}

/**
 * Build a minimal metadata patch required for lecture listability.
 *
 * @param {Record<string, unknown> | undefined} data Current lecture data.
 * @param {Date} now Fallback time.
 * @return {Record<string, unknown> | null} Patch payload or null.
 */
export function buildLectureMetadataPatch(
  data: Record<string, unknown> | undefined,
  now: Date = new Date()
): Record<string, unknown> | null {
  const current = data ?? {};
  const updates: Record<string, unknown> = {};

  const title =
    typeof current.title === "string" ? current.title.trim() : "";
  if (!title) {
    updates.title = DEFAULT_LECTURE_TITLE;
  }

  if (!(current.date instanceof admin.firestore.Timestamp)) {
    const processedAt =
      current.processedAt instanceof admin.firestore.Timestamp ?
        current.processedAt :
        null;
    const summarizedAt =
      current.summarizedAt instanceof admin.firestore.Timestamp ?
        current.summarizedAt :
        null;
    updates.date =
      processedAt ??
      summarizedAt ??
      admin.firestore.Timestamp.fromDate(now);
  }

  if (typeof current.isFavorite !== "boolean") {
    updates.isFavorite = false;
  }

  return Object.keys(updates).length ? updates : null;
}
