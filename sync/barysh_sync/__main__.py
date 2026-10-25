"""Entry point: python -m barysh_sync [--once] [--config path]."""

import argparse
import logging
import sys

from . import __version__, config
from .app import App


def setup_logging(cfg, quiet=False):
    cfg.data_dir.mkdir(parents=True, exist_ok=True)
    handlers = [logging.FileHandler(cfg.log_file, encoding="utf-8")]
    if not quiet and sys.stdout is not None:
        handlers.append(logging.StreamHandler(sys.stdout))
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s", handlers=handlers)


def main(argv=None):
    argv = sys.argv[1:] if argv is None else argv
    if argv and argv[0] in ("encode", "decode"):
        # Import strings for lists: python -m barysh_sync encode list.json | decode "!BARYSH:..."
        from . import importstring
        return importstring.main(argv)
    parser = argparse.ArgumentParser(prog="barysh-sync", description=f"BaryshSync {__version__}")
    parser.add_argument("--once", action="store_true", help="process changed files once and exit")
    parser.add_argument("--config", help="path to config.toml")
    parser.add_argument("--quiet", action="store_true", help="log only to the file (for pythonw)")
    parser.add_argument("--tray", action="store_true", help="show a tray icon (Windows)")
    args = parser.parse_args(argv)

    cfg = config.load(args.config)
    setup_logging(cfg, args.quiet)
    app = App(cfg)
    if not app.game_dirs():
        logging.error("Папка WoW с аддоном Barysh не найдена. Укажи game_dir в sync/config.toml.")
        if args.once:
            return 1
    if args.once:
        app.poll_once()
        return 0
    if args.tray and sys.platform == "win32":
        from . import tray
        tray.run(app)
        return 0
    app.run_forever()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
