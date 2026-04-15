const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");

const {
  buildTranscriptDocument,
  extractRecentStreamVideosFromHtml,
  extractWatchVideoMetadataFromHtml,
  filterStreamVideos,
  inferSpeakerFromTitle,
  normalizeCaptionFragment,
  parseTranscriptDocument,
  slugifyChannelUrl,
  slugifyTitle,
  writeTranscriptFile,
} = require("../lib/youtubeStreamTranscriptExport.js");

test("extractRecentStreamVideosFromHtml returns newest stream videos in page order", () => {
  const html = `<!doctype html><html><body><script>
var ytInitialData = {
  "contents": {
    "twoColumnBrowseResultsRenderer": {
      "tabs": [
        {
          "tabRenderer": {
            "title": "Home"
          }
        },
        {
          "tabRenderer": {
            "title": "Streams",
            "endpoint": {
              "commandMetadata": {
                "webCommandMetadata": {
                  "url": "/@EPICMASJID/streams"
                }
              }
            },
            "content": {
              "richGridRenderer": {
                "contents": [
                  {
                    "richItemRenderer": {
                      "content": {
                        "lockupViewModel": {
                          "contentId": "video-1",
                          "rendererContext": {
                            "commandContext": {
                              "onTap": {
                                "innertubeCommand": {
                                  "commandMetadata": {
                                    "webCommandMetadata": {
                                      "url": "/watch?v=video-1"
                                    }
                                  }
                                }
                              }
                            }
                          },
                          "metadata": {
                            "lockupMetadataViewModel": {
                              "title": {
                                "content": "Newest Stream"
                              },
                              "metadata": {
                                "contentMetadataViewModel": {
                                  "metadataRows": [
                                    {
                                      "metadataParts": [
                                        {"text": {"content": "2.1K views"}},
                                        {"text": {"content": "Streamed 1 day ago"}}
                                      ]
                                    }
                                  ]
                                }
                              }
                            }
                          }
                        }
                      }
                    }
                  },
                  {
                    "richItemRenderer": {
                      "content": {
                        "lockupViewModel": {
                          "contentId": "video-2",
                          "rendererContext": {
                            "commandContext": {
                              "onTap": {
                                "innertubeCommand": {
                                  "commandMetadata": {
                                    "webCommandMetadata": {
                                      "url": "/watch?v=video-2"
                                    }
                                  }
                                }
                              }
                            }
                          },
                          "metadata": {
                            "lockupMetadataViewModel": {
                              "title": {
                                "content": "Second Stream"
                              },
                              "metadata": {
                                "contentMetadataViewModel": {
                                  "metadataRows": [
                                    {
                                      "metadataParts": [
                                        {"text": {"content": "800 views"}},
                                        {"text": {"content": "Streamed 8 days ago"}}
                                      ]
                                    }
                                  ]
                                }
                              }
                            }
                          }
                        }
                      }
                    }
                  },
                  {
                    "richItemRenderer": {
                      "content": {
                        "lockupViewModel": {
                          "contentId": "video-3",
                          "rendererContext": {
                            "commandContext": {
                              "onTap": {
                                "innertubeCommand": {
                                  "commandMetadata": {
                                    "webCommandMetadata": {
                                      "url": "/watch?v=video-3"
                                    }
                                  }
                                }
                              }
                            }
                          },
                          "metadata": {
                            "lockupMetadataViewModel": {
                              "title": {
                                "content": "Third Stream"
                              },
                              "metadata": {
                                "contentMetadataViewModel": {
                                  "metadataRows": [
                                    {
                                      "metadataParts": [
                                        {"text": {"content": "500 views"}},
                                        {"text": {"content": "Streamed 15 days ago"}}
                                      ]
                                    }
                                  ]
                                }
                              }
                            }
                          }
                        }
                      }
                    }
                  }
                ]
              }
            }
          }
        }
      ]
    }
  }
};
</script></body></html>`;

  const videos = extractRecentStreamVideosFromHtml(html, 2);
  assert.deepEqual(videos, [
    {
      videoId: "video-1",
      title: "Newest Stream",
      videoUrl: "https://www.youtube.com/watch?v=video-1",
      publishedText: "Streamed 1 day ago",
    },
    {
      videoId: "video-2",
      title: "Second Stream",
      videoUrl: "https://www.youtube.com/watch?v=video-2",
      publishedText: "Streamed 8 days ago",
    },
  ]);
});

test("extractRecentStreamVideosFromHtml supports live-tab videoRenderer items", () => {
  const html = `<!doctype html><html><body><script>
var ytInitialData = {
  "contents": {
    "twoColumnBrowseResultsRenderer": {
      "tabs": [
        {
          "tabRenderer": {
            "title": "Live",
            "endpoint": {
              "commandMetadata": {
                "webCommandMetadata": {
                  "url": "/@EPICMASJID/streams"
                }
              }
            },
            "content": {
              "richGridRenderer": {
                "contents": [
                  {
                    "richItemRenderer": {
                      "content": {
                        "videoRenderer": {
                          "videoId": "video-live-1",
                          "title": {
                            "runs": [
                              {"text": "Latest Live Stream"}
                            ]
                          },
                          "publishedTimeText": {
                            "simpleText": "Streamed 2 hours ago"
                          },
                          "navigationEndpoint": {
                            "commandMetadata": {
                              "webCommandMetadata": {
                                "url": "/watch?v=video-live-1&pp=123"
                              }
                            }
                          }
                        }
                      }
                    }
                  }
                ]
              }
            }
          }
        }
      ]
    }
  }
};
</script></body></html>`;

  const videos = extractRecentStreamVideosFromHtml(html, 1);
  assert.deepEqual(videos, [
    {
      videoId: "video-live-1",
      title: "Latest Live Stream",
      videoUrl: "https://www.youtube.com/watch?v=video-live-1&pp=123",
      publishedText: "Streamed 2 hours ago",
    },
  ]);
});

test("extractRecentStreamVideosFromHtml falls back to channel root video grid", () => {
  const html = `<!doctype html><html><body><script>
var ytInitialData = {
  "contents": {
    "twoColumnBrowseResultsRenderer": {
      "tabs": [
        {
          "tabRenderer": {
            "title": "Home",
            "endpoint": {
              "commandMetadata": {
                "webCommandMetadata": {
                  "url": "/@theicnyc"
                }
              }
            },
            "content": {
              "richGridRenderer": {
                "contents": [
                  {
                    "richItemRenderer": {
                      "content": {
                        "videoRenderer": {
                          "videoId": "video-root-1",
                          "title": {
                            "runs": [
                              {"text": "Friday Khutbah | Imam Example"}
                            ]
                          },
                          "publishedTimeText": {
                            "simpleText": "2 days ago"
                          },
                          "navigationEndpoint": {
                            "commandMetadata": {
                              "webCommandMetadata": {
                                "url": "/watch?v=video-root-1"
                              }
                            }
                          }
                        }
                      }
                    }
                  },
                  {
                    "richItemRenderer": {
                      "content": {
                        "videoRenderer": {
                          "videoId": "video-root-2",
                          "title": {
                            "runs": [
                              {"text": "Community Update"}
                            ]
                          },
                          "publishedTimeText": {
                            "simpleText": "5 days ago"
                          },
                          "navigationEndpoint": {
                            "commandMetadata": {
                              "webCommandMetadata": {
                                "url": "/watch?v=video-root-2"
                              }
                            }
                          }
                        }
                      }
                    }
                  }
                ]
              }
            }
          }
        }
      ]
    }
  }
};
</script></body></html>`;

  const videos = extractRecentStreamVideosFromHtml(html, 2);
  assert.deepEqual(videos, [
    {
      videoId: "video-root-1",
      title: "Friday Khutbah | Imam Example",
      videoUrl: "https://www.youtube.com/watch?v=video-root-1",
      publishedText: "2 days ago",
    },
    {
      videoId: "video-root-2",
      title: "Community Update",
      videoUrl: "https://www.youtube.com/watch?v=video-root-2",
      publishedText: "5 days ago",
    },
  ]);
});

test("extractRecentStreamVideosFromHtml falls back when streams tab has no content", () => {
  const html = `<!doctype html><html><body><script>
var ytInitialData = {
  "contents": {
    "twoColumnBrowseResultsRenderer": {
      "tabs": [
        {
          "tabRenderer": {
            "title": "Streams",
            "endpoint": {
              "commandMetadata": {
                "webCommandMetadata": {
                  "url": "/@channel/streams"
                }
              }
            }
          }
        },
        {
          "tabRenderer": {
            "title": "Videos",
            "selected": true,
            "endpoint": {
              "commandMetadata": {
                "webCommandMetadata": {
                  "url": "/@channel/videos"
                }
              }
            },
            "content": {
              "richGridRenderer": {
                "contents": [
                  {
                    "richItemRenderer": {
                      "content": {
                        "videoRenderer": {
                          "videoId": "video-fallback-1",
                          "title": {
                            "runs": [
                              {"text": "Friday Sermon | Imam Example"}
                            ]
                          },
                          "publishedTimeText": {
                            "simpleText": "1 day ago"
                          },
                          "navigationEndpoint": {
                            "commandMetadata": {
                              "webCommandMetadata": {
                                "url": "/watch?v=video-fallback-1"
                              }
                            }
                          }
                        }
                      }
                    }
                  }
                ]
              }
            }
          }
        }
      ]
    }
  }
};
</script></body></html>`;

  const videos = extractRecentStreamVideosFromHtml(html, 1);
  assert.deepEqual(videos, [
    {
      videoId: "video-fallback-1",
      title: "Friday Sermon | Imam Example",
      videoUrl: "https://www.youtube.com/watch?v=video-fallback-1",
      publishedText: "1 day ago",
    },
  ]);
});

test("filterStreamVideos keeps only matching khutbah-like titles", () => {
  const videos = filterStreamVideos([
    {
      videoId: "a",
      title: "Friday Khutbah | Imam Example",
      videoUrl: "https://www.youtube.com/watch?v=a",
      publishedText: "Streamed 1 day ago",
    },
    {
      videoId: "b",
      title: "Community Fundraiser Night",
      videoUrl: "https://www.youtube.com/watch?v=b",
      publishedText: "Streamed 2 days ago",
    },
    {
      videoId: "c",
      title: "Jumu'ah Reflections",
      videoUrl: "https://www.youtube.com/watch?v=c",
      publishedText: "Streamed 3 days ago",
    },
  ], {
    titleKeywords: ["khutbah", "jumu'ah"],
  });

  assert.deepEqual(videos.map((video) => video.videoId), ["a", "c"]);
});

test("slugifyChannelUrl uses the handle for channel subfolders", () => {
  assert.equal(
    slugifyChannelUrl("https://www.youtube.com/@qalaminstitute/streams"),
    "qalaminstitute"
  );
});

test("inferSpeakerFromTitle parses common khutbah speaker patterns", () => {
  assert.equal(
    inferSpeakerFromTitle(
      "If You Think They've Won, Watch This | Khutbah by Dr. Omar Suleiman"
    ),
    "Dr. Omar Suleiman"
  );
  assert.equal(
    inferSpeakerFromTitle(
      "Four Keys to Success | Jumuah Khutbah | Shaykh Yaser Birjas"
    ),
    "Shaykh Yaser Birjas"
  );
  assert.equal(
    inferSpeakerFromTitle("LIVE: WCCC Jummah Prayer | 4/10/26"),
    null
  );
});

test("extractWatchVideoMetadataFromHtml parses publish date from watch html", () => {
  const metadata = extractWatchVideoMetadataFromHtml(
    `
    <html>
      <script>
        var ytInitialPlayerResponse = {
          "microformat": {
            "playerMicroformatRenderer": {
              "publishDate": "2026-04-11"
            }
          }
        };
      </script>
    </html>
    `,
    "Friday Khutbah | Imam Nadim Bashir"
  );

  assert.equal(metadata.publishedAt?.toISOString(), "2026-04-11T00:00:00.000Z");
  assert.equal(metadata.speaker, "Imam Nadim Bashir");
});

test("slugifyTitle normalizes punctuation and casing", () => {
  assert.equal(
    slugifyTitle("How to Gain Allah's Blessing & Rehma"),
    "how-to-gain-allah-s-blessing-rehma"
  );
});

test("normalizeCaptionFragment decodes double-escaped HTML entities", () => {
  assert.equal(
    normalizeCaptionFragment("&amp;gt;&amp;gt; Allah&#39;s mercy"),
    ">> Allah's mercy"
  );
});

test("buildTranscriptDocument includes metadata header and transcript body", () => {
  const doc = buildTranscriptDocument(
    {
      videoId: "abc123",
      title: "A Sample Khutbah",
      videoUrl: "https://www.youtube.com/watch?v=abc123",
      publishedText: "Streamed 1 day ago",
    },
    {
      text: "Line one.\nLine two.",
      source: "youtube_watch_page",
      languageCode: "en",
      isAutoGenerated: false,
    },
    "https://www.youtube.com/@EPICMASJID/streams",
    new Date("2026-04-11T22:00:00.000Z"),
    {
      metadata: {
        publishedAt: new Date("2026-04-11T19:30:00.000Z"),
        speaker: "Shaykh Example",
      },
    }
  );

  assert.match(doc, /Title: A Sample Khutbah/);
  assert.match(doc, /Video URL: https:\/\/www\.youtube\.com\/watch\?v=abc123/);
  assert.match(doc, /Transcript Source: youtube_watch_page/);
  assert.match(doc, /Published At: 2026-04-11T19:30:00.000Z/);
  assert.match(doc, /Speaker: Shaykh Example/);
  assert.match(doc, /Line one\.\nLine two\./);
});

test("parseTranscriptDocument reads metadata headers and transcript body", () => {
  const parsed = parseTranscriptDocument(
    [
      "Title: A Sample Khutbah",
      "Video URL: https://www.youtube.com/watch?v=abc123",
      "Source Page: https://www.youtube.com/@EPICMASJID/streams",
      "Published: Streamed 1 day ago",
      "Fetched At: 2026-04-11T22:00:00.000Z",
      "Transcript Source: youtube_watch_page",
      "Published At: 2026-04-11T19:30:00.000Z",
      "Language Code: en",
      "Auto Generated: no",
      "Speaker: Shaykh Example",
      "",
      "Line one.",
      "Line two.",
      "",
    ].join("\n")
  );

  assert.equal(parsed.metadata.title, "A Sample Khutbah");
  assert.equal(parsed.metadata.videoUrl, "https://www.youtube.com/watch?v=abc123");
  assert.equal(
    parsed.metadata.publishedAt?.toISOString(),
    "2026-04-11T19:30:00.000Z"
  );
  assert.equal(parsed.metadata.speaker, "Shaykh Example");
  assert.equal(parsed.metadata.isAutoGenerated, false);
  assert.equal(parsed.transcriptText, "Line one.\nLine two.");
});

test("writeTranscriptFile writes a stable filename and body", async () => {
  const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "epic-streams-"));
  const filePath = await writeTranscriptFile(
    tmpDir,
    {
      videoId: "abc123",
      title: "A Sample Khutbah",
      videoUrl: "https://www.youtube.com/watch?v=abc123",
      publishedText: "Streamed 1 day ago",
    },
    {
      text: "Transcript body",
      source: "youtube_watch_page",
      languageCode: null,
      isAutoGenerated: null,
    },
    "https://www.youtube.com/@EPICMASJID/streams",
    new Date("2026-04-11T20:30:00.000Z")
  );

  assert.equal(
    path.basename(filePath),
    "2026-04-11__abc123__a-sample-khutbah.txt"
  );
  const body = fs.readFileSync(filePath, "utf8");
  assert.match(body, /Transcript body/);
  fs.rmSync(tmpDir, {recursive: true, force: true});
});
