"""Locating the WoW Forever install and the Barysh SavedVariables files."""

from pathlib import Path

DEFAULT_ROOTS = (
    Path(r"C:\Program Files (x86)\World of Warcraft"),
    Path(r"C:\Program Files\World of Warcraft"),
)

# Game flavor folders look like _retail_, _classic_era_. The Forever folder name is
# not known before launch, so every flavor folder with Barysh installed is a candidate.
FLAVOR_GLOB = "_*_"


def find_game_dirs(roots=DEFAULT_ROOTS):
    """Flavor folders under the WoW roots that have the Barysh addon installed."""
    found = []
    for root in roots:
        if not root.is_dir():
            continue
        for flavor in sorted(root.glob(FLAVOR_GLOB)):
            if (flavor / "Interface" / "AddOns" / "Barysh").exists():
                found.append(flavor)
    return found


def saved_variables_files(game_dir):
    """Barysh.lua SavedVariables for every account in a flavor folder."""
    return sorted((game_dir / "WTF" / "Account").glob("*/SavedVariables/Barysh.lua"))


def market_file(game_dir):
    """Where BaryshSync writes market statistics for the addon."""
    return game_dir / "Interface" / "AddOns" / "Barysh" / "Data" / "Market.lua"
