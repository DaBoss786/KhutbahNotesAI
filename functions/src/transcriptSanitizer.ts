export type SanitizedChunkTranscript = {
  cleanedText: string;
  removed: boolean;
  hardEcho: boolean;
};

/**
 * Normalize text for prompt-echo comparison.
 *
 * @param {string} text Raw text.
 * @return {string} Normalized text.
 */
export function normalizeForComparison(text: string): string {
  return text
    .toLowerCase()
    .replace(/[^\p{L}\p{N}\s]/gu, " ")
    .replace(/\s+/g, " ")
    .trim();
}

/**
 * Count whitespace-delimited words in text.
 *
 * @param {string} text Input text.
 * @return {number} Word count.
 */
function countWords(text: string): number {
  const trimmed = text.trim();
  if (!trimmed) {
    return 0;
  }
  return trimmed.split(/\s+/).length;
}

/**
 * Check whether two normalized texts are near-identical.
 *
 * @param {string} a Text A.
 * @param {string} b Text B.
 * @return {boolean} True when nearly identical.
 */
function areNearIdentical(a: string, b: string): boolean {
  if (!a || !b) {
    return false;
  }
  if (a === b) {
    return true;
  }
  const minLength = Math.min(a.length, b.length);
  const maxLength = Math.max(a.length, b.length);
  if (maxLength === 0) {
    return false;
  }
  const lengthRatio = minLength / maxLength;
  if (lengthRatio >= 0.9 && (a.includes(b) || b.includes(a))) {
    return true;
  }
  const aWords = new Set(a.split(" ").filter(Boolean));
  const bWords = new Set(b.split(" ").filter(Boolean));
  if (aWords.size === 0 || bWords.size === 0) {
    return false;
  }
  let intersection = 0;
  for (const word of aWords) {
    if (bWords.has(word)) {
      intersection++;
    }
  }
  const union = new Set([...aWords, ...bWords]).size;
  const similarity = union > 0 ? intersection / union : 0;
  return similarity >= 0.95;
}

/**
 * Detect prompt echoing in transcript text.
 *
 * @param {string} text Transcript text.
 * @param {string} prompt Prompt text used for transcription.
 * @return {boolean} True when transcript appears to echo the prompt.
 */
export function isPromptEcho(text: string, prompt: string): boolean {
  const normalizedText = normalizeForComparison(text);
  if (!normalizedText) {
    return false;
  }
  const normalizedPrompt = normalizeForComparison(prompt);
  if (!normalizedPrompt) {
    return false;
  }
  if (areNearIdentical(normalizedText, normalizedPrompt)) {
    return true;
  }
  if (normalizedText.includes(normalizedPrompt)) {
    return true;
  }
  const minWords = 6;
  if (countWords(normalizedText) < minWords) {
    return false;
  }
  return normalizedPrompt.includes(normalizedText);
}

/**
 * Escape regular-expression metacharacters.
 *
 * @param {string} value Raw text.
 * @return {string} Escaped text.
 */
function escapeRegex(value: string): string {
  return value.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

/**
 * Build a regex that matches prompt words separated by punctuation/whitespace.
 *
 * @param {string} prompt Prompt text.
 * @return {RegExp | null} Compiled regex or null when prompt has no words.
 */
function buildPromptLeakageRegex(prompt: string): RegExp | null {
  const words = normalizeForComparison(prompt).split(" ").filter(Boolean);
  if (words.length === 0) {
    return null;
  }
  const phrase = words
    .map((word) => escapeRegex(word))
    .join("[^\\p{L}\\p{N}]+");
  return new RegExp(
    `(?<![\\p{L}\\p{N}])${phrase}(?![\\p{L}\\p{N}])`,
    "giu"
  );
}

/**
 * Collapse extra spacing after prompt leakage removal.
 *
 * @param {string} text Input text.
 * @return {string} Cleaned text.
 */
function collapseWhitespace(text: string): string {
  return text
    .replace(/[ \t]+/g, " ")
    .replace(/[ \t]*\n[ \t]*/g, "\n")
    .replace(/\n{3,}/g, "\n\n")
    .replace(/(?:^|\s)[.!?]+(?=\s|$)/g, " ")
    .replace(/ {2,}/g, " ")
    .trim();
}

/**
 * Strip leaked prompt text while preserving surrounding transcript.
 *
 * @param {string} text Transcript text.
 * @param {string} prompt Prompt text to remove if leaked.
 * @return {string} Transcript with leaked prompt removed.
 */
export function stripPromptEchoLeakage(text: string, prompt: string): string {
  if (!text) {
    return "";
  }

  const promptRegex = buildPromptLeakageRegex(prompt);
  if (!promptRegex) {
    return text.trim();
  }

  let removedAny = false;
  const stripped = text.replace(promptRegex, () => {
    removedAny = true;
    return " ";
  });

  return removedAny ? collapseWhitespace(stripped) : text.trim();
}

/**
 * Sanitize a single chunk transcript for prompt leakage.
 *
 * @param {string} text Chunk transcript.
 * @param {string} prompt Prompt text.
 * @return {SanitizedChunkTranscript} Sanitized chunk and flags.
 */
export function sanitizeChunkTranscript(
  text: string,
  prompt: string
): SanitizedChunkTranscript {
  const cleanedText = stripPromptEchoLeakage(text, prompt);
  const removed = cleanedText !== text.trim();
  const hardEcho = cleanedText ?
    isPromptEcho(cleanedText, prompt) :
    isPromptEcho(text, prompt) || removed;

  return {
    cleanedText,
    removed,
    hardEcho,
  };
}
