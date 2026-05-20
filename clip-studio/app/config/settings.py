from functools import lru_cache
from pathlib import Path
import os

from dotenv import load_dotenv


ROOT = Path(__file__).resolve().parents[2]
load_dotenv(ROOT / ".env")


class Settings:
    root: Path = ROOT
    app_host: str = os.getenv("APP_HOST", "127.0.0.1")
    app_port: int = int(os.getenv("APP_PORT", "8787"))
    database_path: Path = ROOT / os.getenv("DATABASE_PATH", "data/khutbah_clips.sqlite")
    storage_root: Path = ROOT / os.getenv("STORAGE_ROOT", ".")
    openai_api_key: str = os.getenv("OPENAI_API_KEY", "").strip()
    openai_model: str = os.getenv("OPENAI_MODEL", "gpt-5.4-mini")
    whisper_model: str = os.getenv("WHISPER_MODEL", "base")
    default_clip_count: int = int(os.getenv("DEFAULT_CLIP_COUNT", "5"))
    default_min_duration: int = int(os.getenv("DEFAULT_MIN_DURATION", "20"))
    default_max_duration: int = int(os.getenv("DEFAULT_MAX_DURATION", "60"))
    intro_seconds: int = int(os.getenv("INTRO_SECONDS", "2"))
    outro_seconds: int = int(os.getenv("OUTRO_SECONDS", "5"))
    brand_name: str = os.getenv("BRAND_NAME", "Khutbah Notes")
    brand_primary: str = os.getenv("BRAND_PRIMARY", "#125C40")
    brand_accent: str = os.getenv("BRAND_ACCENT", "#2FB36D")
    brand_cream: str = os.getenv("BRAND_CREAM", "#FAF8F0")
    brand_watermark: str = os.getenv("BRAND_WATERMARK", "Khutbah Notes")
    brand_logo_path_raw: str = os.getenv(
        "BRAND_LOGO_PATH",
        "../Khutbah Notes AI/Assets.xcassets/KhutbahNotesLogo.imageset/Khutbah Notes logo 1024 x 1024.png",
    )

    @property
    def data_dir(self) -> Path:
        return self.root / "data"

    @property
    def jobs_dir(self) -> Path:
        return self.root / "jobs"

    @property
    def outputs_dir(self) -> Path:
        return self.root / "outputs"

    @property
    def tmp_dir(self) -> Path:
        return self.root / "tmp"

    @property
    def brand_logo_path(self) -> Path:
        path = Path(self.brand_logo_path_raw)
        return path if path.is_absolute() else (self.root / path).resolve()

    def ensure_dirs(self) -> None:
        for path in [self.data_dir, self.jobs_dir, self.outputs_dir, self.tmp_dir]:
            path.mkdir(parents=True, exist_ok=True)


@lru_cache
def get_settings() -> Settings:
    return Settings()


settings = get_settings()
