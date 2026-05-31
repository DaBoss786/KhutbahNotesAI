from pydantic import BaseModel, Field


class JobCreate(BaseModel):
    youtube_url: str
    speaker_name: str | None = ""
    masjid_name: str | None = ""
    clip_count: int = Field(default=5, ge=1, le=10)
    min_duration: float = Field(default=20, ge=5, le=180)
    max_duration: float = Field(default=60, ge=10, le=180)
    branding_profile: str = "default"


class ApprovalUpdate(BaseModel):
    approvals: dict[str, str]


class SelectionCreate(BaseModel):
    start_time: float
    end_time: float
    text_excerpt: str = ""
    source: str = "manual"
    status: str = "draft"


class SelectionPatch(BaseModel):
    start_time: float | None = None
    end_time: float | None = None
    text_excerpt: str | None = None
    status: str | None = None
    intro_title: str | None = None
    intro_subtitle: str | None = None
    outro_title: str | None = None
    outro_subtitle: str | None = None
    crop_focus_x: float | None = Field(default=None, ge=0, le=1)
    crop_focus_y: float | None = Field(default=None, ge=0, le=1)
    subtitle_offset_ms: int | None = Field(default=None, ge=-750, le=750)


class SubtitlePreviewRenderRequest(BaseModel):
    crop_focus_x: float | None = Field(default=None, ge=0, le=1)
    crop_focus_y: float | None = Field(default=None, ge=0, le=1)
    subtitle_offset_ms: int | None = Field(default=None, ge=-750, le=750)
    preview_start: float | None = None
    duration: float = Field(default=8, ge=1, le=15)


class LockRequest(BaseModel):
    locked_by: str = "local-user"
