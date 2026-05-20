from types import SimpleNamespace

from app.ingest.youtube import download_video


def test_download_video_continues_when_caption_download_is_rate_limited(
    monkeypatch,
    tmp_path,
):
    calls = []

    def fake_run(args, cwd=None, text=True, stdout=None, stderr=None, check=False):
        calls.append(args)
        if args[0] == "yt-dlp" and "--skip-download" not in args:
            (tmp_path / "source.mp4").write_bytes(b"video")
            return SimpleNamespace(returncode=0, stdout="video ok")
        if args[0] == "yt-dlp" and "--skip-download" in args:
            return SimpleNamespace(
                returncode=1,
                stdout="ERROR: Unable to download video subtitles: HTTP Error 429",
            )
        if args[0] == "ffmpeg":
            (tmp_path / "source.wav").write_bytes(b"audio")
            return SimpleNamespace(returncode=0, stdout="audio ok")
        raise AssertionError(f"Unexpected command: {args}")

    monkeypatch.setattr("app.ingest.youtube.subprocess.run", fake_run)

    result = download_video("https://youtu.be/abcdefghijk", tmp_path)

    assert result["video_path"].name == "source.mp4"
    assert result["audio_path"].name == "source.wav"
    assert "Caption download skipped" in result["log"]
    assert any(args[0] == "ffmpeg" for args in calls)


def test_caption_download_uses_explicit_english_languages(monkeypatch, tmp_path):
    caption_args = None

    def fake_run(args, cwd=None, text=True, stdout=None, stderr=None, check=False):
        nonlocal caption_args
        if args[0] == "yt-dlp" and "--skip-download" not in args:
            (tmp_path / "source.mp4").write_bytes(b"video")
            return SimpleNamespace(returncode=0, stdout="video ok")
        if args[0] == "yt-dlp" and "--skip-download" in args:
            caption_args = args
            (tmp_path / "source.en.vtt").write_text("WEBVTT\n", encoding="utf-8")
            return SimpleNamespace(returncode=0, stdout="captions ok")
        if args[0] == "ffmpeg":
            (tmp_path / "source.wav").write_bytes(b"audio")
            return SimpleNamespace(returncode=0, stdout="audio ok")
        raise AssertionError(f"Unexpected command: {args}")

    monkeypatch.setattr("app.ingest.youtube.subprocess.run", fake_run)

    download_video("https://youtu.be/abcdefghijk", tmp_path)

    assert caption_args is not None
    assert caption_args[caption_args.index("--sub-lang") + 1] == "en,en-US,en-orig"
