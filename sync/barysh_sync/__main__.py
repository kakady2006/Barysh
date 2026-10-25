"""Entry point. For now it only reports what it finds; the watcher comes in stage 1."""

from . import __version__
from .paths import find_game_dirs, saved_variables_files


def main():
    print(f"BaryshSync {__version__}")
    dirs = find_game_dirs()
    if not dirs:
        print("WoW folder with the Barysh addon not found (set game_dir in sync/config.toml).")
        return 1
    for game_dir in dirs:
        print(f"Game folder: {game_dir}")
        for sv in saved_variables_files(game_dir):
            print(f"  SavedVariables: {sv}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
