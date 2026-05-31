from app.transcript.service import parse_vtt


def test_parse_vtt_preserves_youtube_inline_word_timestamps(tmp_path):
    caption = tmp_path / "source.en-orig.vtt"
    caption.write_text(
        """WEBVTT

00:16:14.560 --> 00:16:16.430 align:start position:0%
righters and these supremacists.
Whatever<00:16:15.040><c> you</c><00:16:15.280><c> do,</c>

00:16:16.430 --> 00:16:16.440 align:start position:0%
Whatever you do,

00:16:16.440 --> 00:16:18.230 align:start position:0%
Whatever you do,
we<00:16:16.680><c> will</c><00:16:16.920><c> never</c>

00:16:18.240 --> 00:16:20.070 align:start position:0%
we will never
be<00:16:18.440><c> intimidated.</c>
""",
        encoding="utf-8",
    )

    segments, tokens, metadata = parse_vtt(caption)

    assert metadata["timing_source"] == "youtube_word"
    assert [segment["text"] for segment in segments] == [
        "Whatever you do,",
        "we will never",
        "be intimidated.",
    ]
    assert [(token["text"], token["start_time"]) for token in tokens] == [
        ("Whatever", 974.56),
        ("you", 975.04),
        ("do,", 975.28),
        ("we", 976.44),
        ("will", 976.68),
        ("never", 976.92),
        ("be", 978.24),
        ("intimidated.", 978.44),
    ]


def test_parse_vtt_falls_back_to_estimated_timing_without_inline_words(tmp_path):
    caption = tmp_path / "source.en.vtt"
    caption.write_text(
        """WEBVTT

00:00:10.000 --> 00:00:12.000
Allah reminds us.
""",
        encoding="utf-8",
    )

    segments, tokens, metadata = parse_vtt(caption)

    assert metadata["timing_source"] == "estimated"
    assert segments[0]["text"] == "Allah reminds us."
    assert [token["text"] for token in tokens] == ["Allah", "reminds", "us."]
    assert tokens[1]["start_time"] > tokens[0]["start_time"]
