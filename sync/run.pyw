"""Starts BaryshSync without a console window (used by the Windows Task Scheduler)."""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from barysh_sync.__main__ import main  # noqa: E402

raise SystemExit(main(["--quiet"]))
