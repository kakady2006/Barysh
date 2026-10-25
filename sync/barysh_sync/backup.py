"""Copies of SavedVariables before every processing: after a crash the game sometimes leaves an empty file."""

import shutil
import time
from pathlib import Path

KEEP = 200


def make_backup(sv_path, backup_dir, keep=KEEP, now=None):
    """Copies sv_path into backup_dir/<account>/; keeps the newest `keep` copies. Returns the copy's path."""
    sv_path = Path(sv_path)
    account = sv_path.parent.parent.name
    folder = Path(backup_dir) / account
    folder.mkdir(parents=True, exist_ok=True)
    stamp = time.strftime("%Y%m%d-%H%M%S", time.localtime(now or time.time()))
    target = folder / f"Barysh-{stamp}.lua"
    n = 1
    while target.exists():
        n += 1
        target = folder / f"Barysh-{stamp}-{n}.lua"
    shutil.copy2(sv_path, target)
    copies = sorted(folder.glob("Barysh-*.lua"), key=lambda p: p.stat().st_mtime)
    for old in copies[:-keep]:
        old.unlink()
    return target


def looks_truncated(sv_path):
    """Empty file, or no BaryshDB assignment at all."""
    sv_path = Path(sv_path)
    if not sv_path.exists() or sv_path.stat().st_size == 0:
        return True
    with open(sv_path, "r", encoding="latin-1") as f:
        head = f.read(4096)
    return "BaryshDB" not in head
