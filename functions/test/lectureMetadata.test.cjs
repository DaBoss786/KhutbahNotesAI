const test = require("node:test");
const assert = require("node:assert/strict");
const admin = require("firebase-admin");

const {
  DEFAULT_LECTURE_TITLE,
  buildLectureMetadataPatch,
  parseLectureAudioUploadPath,
} = require("../lib/lectureMetadata.js");

test("buildLectureMetadataPatch fills missing title/date/isFavorite", () => {
  const now = new Date("2026-03-15T00:00:00.000Z");
  const patch = buildLectureMetadataPatch({}, now);

  assert.ok(patch);
  assert.equal(patch.title, DEFAULT_LECTURE_TITLE);
  assert.equal(patch.isFavorite, false);
  assert.ok(patch.date instanceof admin.firestore.Timestamp);
  assert.equal(patch.date.toMillis(), now.getTime());
});

test("buildLectureMetadataPatch preserves valid fields", () => {
  const data = {
    title: "A valid title",
    date: admin.firestore.Timestamp.fromDate(new Date("2026-03-14T10:00:00Z")),
    isFavorite: true,
  };
  const patch = buildLectureMetadataPatch(data);
  assert.equal(patch, null);
});

test("buildLectureMetadataPatch prefers processedAt over summarizedAt", () => {
  const processedAt = admin.firestore.Timestamp.fromDate(
    new Date("2026-03-14T11:00:00Z")
  );
  const summarizedAt = admin.firestore.Timestamp.fromDate(
    new Date("2026-03-14T12:00:00Z")
  );
  const patch = buildLectureMetadataPatch({
    title: "Existing title",
    processedAt,
    summarizedAt,
    isFavorite: false,
  });

  assert.ok(patch);
  assert.ok(patch.date instanceof admin.firestore.Timestamp);
  assert.equal(patch.date.toMillis(), processedAt.toMillis());
  assert.equal(patch.title, undefined);
  assert.equal(patch.isFavorite, undefined);
});

test("parseLectureAudioUploadPath accepts top-level lecture uploads", () => {
  const parsed = parseLectureAudioUploadPath("audio/u1/lecture-123.m4a");
  assert.deepEqual(parsed, {userId: "u1", lectureId: "lecture-123"});
});

test("parseLectureAudioUploadPath rejects nested recap paths", () => {
  assert.equal(
    parseLectureAudioUploadPath("audio/u1/recaps/lecture-123/variant.mp3"),
    null
  );
});
