const test = require("node:test");
const assert = require("node:assert/strict");

const {parseCliArgs} = require("../lib/exportYoutubeStreams.js");

test("parseCliArgs accepts repeated channel and keyword flags", () => {
  const parsed = parseCliArgs([
    "--channel-url",
    "https://www.youtube.com/@EPICMASJID/streams",
    "--channel-url",
    "https://www.youtube.com/@qalaminstitute/streams",
    "--output-dir",
    "/tmp/transcripts",
    "--limit",
    "1",
    "--title-keyword",
    "khutbah",
    "--title-keyword",
    "jumu'ah",
    "--mode",
    "scheduled",
  ]);

  assert.deepEqual(parsed, {
    channelUrls: [
      "https://www.youtube.com/@EPICMASJID/streams",
      "https://www.youtube.com/@qalaminstitute/streams",
    ],
    outputDir: "/tmp/transcripts",
    limit: 1,
    titleKeywords: ["khutbah", "jumu'ah"],
    mode: "scheduled",
  });
});
