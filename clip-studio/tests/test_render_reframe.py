from app.render.composer import adjusted_subtitle_time, subtitle_preview_blocks, reframe_filter


def test_reframe_filter_uses_saved_focus_values():
    vf = reframe_filter({"crop_focus_x": 0.72, "crop_focus_y": 0.44})

    assert "0.7200*iw-540" in vf
    assert "0.4400*ih-960" in vf
    assert "crop=1080:1920" in vf


def test_reframe_filter_clamps_invalid_values_to_safe_range():
    vf = reframe_filter({"crop_focus_x": 4, "crop_focus_y": -2})

    assert "1.0000*iw-540" in vf
    assert "0.0000*ih-960" in vf


def test_subtitle_offset_negative_makes_highlight_earlier():
    assert adjusted_subtitle_time(10.0, -250) == 10.25
    assert adjusted_subtitle_time(10.0, 250) == 9.75


def test_subtitle_preview_excludes_boundary_only_tokens():
    blocks = subtitle_preview_blocks(
        [
            {"text": "previous", "start_time": 9.5, "end_time": 10.0},
            {"text": "current", "start_time": 10.0, "end_time": 10.5},
        ],
        10.0,
        12.0,
    )

    assert blocks[0]["tokens"][0]["text"] == "current"
