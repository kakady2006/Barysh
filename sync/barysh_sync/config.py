"""Settings from sync/config.toml (not in git). Everything has a working default."""

import os
import tomllib
from dataclasses import dataclass, field
from pathlib import Path

SYNC_DIR = Path(__file__).resolve().parent.parent
REPO_DIR = SYNC_DIR.parent


def _default_data_dir():
    base = os.environ.get("LOCALAPPDATA") or str(Path.home())
    return Path(base) / "BaryshSync"


@dataclass
class Config:
    game_dir: Path | None = None
    data_dir: Path = field(default_factory=_default_data_dir)
    repo_dir: Path = REPO_DIR
    github_issues: bool = True
    poll_seconds: float = 2.0

    @property
    def database(self):
        return self.data_dir / "barysh.sqlite"

    @property
    def backups(self):
        return self.data_dir / "backups"

    @property
    def log_file(self):
        return self.data_dir / "barysh-sync.log"

    @property
    def status_file(self):
        return self.data_dir / "status.json"


def load(path=None):
    path = Path(path) if path else SYNC_DIR / "config.toml"
    cfg = Config()
    if path.exists():
        # utf-8-sig: Notepad and PowerShell 5 save files with a BOM.
        raw = tomllib.loads(path.read_text(encoding="utf-8-sig"))
        if raw.get("game_dir"):
            cfg.game_dir = Path(raw["game_dir"])
        if raw.get("data_dir"):
            cfg.data_dir = Path(raw["data_dir"])
        if "github_issues" in raw:
            cfg.github_issues = bool(raw["github_issues"])
        if raw.get("poll_seconds"):
            cfg.poll_seconds = float(raw["poll_seconds"])
    return cfg
