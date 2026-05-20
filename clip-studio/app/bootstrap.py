from app.storage.db import init_db
from app.config.settings import settings


def main() -> None:
    settings.ensure_dirs()
    init_db()


if __name__ == "__main__":
    main()

