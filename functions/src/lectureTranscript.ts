export type TranscriptPayload = {
  text: string;
  source: string;
  repairTranscript: string | null;
};

export type LectureTranscriptPreference = "raw" | "formatted";

type ResolveLectureTranscriptOptions = {
  prefer?: LectureTranscriptPreference;
};

/**
 * Normalize transcript text for storage in the canonical raw field.
 *
 * @param {string} transcript Transcript text.
 * @return {string} Storage-safe transcript text.
 */
export function normalizeLectureTranscriptForStorage(
  transcript: string
): string {
  return transcript.replace(/\r\n/g, "\n").replace(/\s+/g, " ").trim();
}

/**
 * Resolve the best lecture transcript field with configurable preference.
 *
 * @param {Record<string, unknown>} lecture Lecture document data.
 * @param {ResolveLectureTranscriptOptions} options Resolution options.
 * @return {TranscriptPayload | null} Transcript payload or null.
 */
export function resolveLectureTranscript(
  lecture: Record<string, unknown>,
  options: ResolveLectureTranscriptOptions = {}
): TranscriptPayload | null {
  const raw = typeof lecture.transcript === "string" ?
    lecture.transcript.trim() :
    "";
  const formatted = typeof lecture.transcriptFormatted === "string" ?
    lecture.transcriptFormatted.trim() :
    "";
  const prefer = options.prefer ?? "formatted";

  const candidates =
    prefer === "raw" ?
      [
        {text: raw, source: "lecture.transcript" as const},
        {
          text: formatted,
          source: "lecture.transcriptFormatted" as const,
        },
      ] :
      [
        {
          text: formatted,
          source: "lecture.transcriptFormatted" as const,
        },
        {text: raw, source: "lecture.transcript" as const},
      ];

  for (const candidate of candidates) {
    if (!candidate.text) {
      continue;
    }

    return {
      text: candidate.text,
      source: candidate.source,
      repairTranscript:
        candidate.source === "lecture.transcriptFormatted" && !raw ?
          normalizeLectureTranscriptForStorage(candidate.text) :
          null,
    };
  }

  return null;
}
