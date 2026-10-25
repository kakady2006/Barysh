"""Loads Barysh into a Lua 5.1 runtime (lupa) with an imitation of the WoW API."""

from pathlib import Path

import pytest
from lupa import lua51

ROOT = Path(__file__).resolve().parent.parent
ADDON_DIR = ROOT / "Barysh"
MOCK = Path(__file__).resolve().parent / "wow_mock.lua"
ADDON_NAME = "Barysh"


def toc_files():
    """Files listed in Barysh.toc, in load order."""
    files = []
    for line in (ADDON_DIR / "Barysh.toc").read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if line and not line.startswith("#"):
            files.append(line.replace("\\", "/"))
    return files


def source_for(rel):
    path = ADDON_DIR / rel
    if rel == "Data/Market.lua" and not path.exists():
        # Market.lua is written by BaryshSync and not tracked in git.
        path = ADDON_DIR / "Data/Market.default.lua"
    return path.read_text(encoding="utf-8")


class Addon:
    def __init__(self, files):
        self.lua = lua51.LuaRuntime(unpack_returned_tuples=True)
        self.lua.execute(MOCK.read_text(encoding="utf-8"))
        self.ns = self.lua.table()
        # Each addon file gets (addonName, ns) as varargs, like in the client.
        loader = self.lua.eval(
            "function(src, name, addon, ns) "
            "local f, err = loadstring(src, '@' .. name) "
            "if not f then error(err, 0) end "
            "return f(addon, ns) end"
        )
        for rel in files:
            loader(source_for(rel), rel, ADDON_NAME, self.ns)
        self.mock = self.lua.globals().WowMock
        self.g = self.lua.globals()

    def fire(self, event, *args):
        self.mock.FireEvent(event, *args)

    def login(self):
        """ADDON_LOADED + PLAYER_LOGIN, as the client does on /reload."""
        self.fire("ADDON_LOADED", ADDON_NAME)
        self.fire("PLAYER_LOGIN")

    def errors(self):
        db = self.g.BaryshDB
        if db is None or db.errors is None:
            return []
        return [(e.msg, e.stack) for e in db.errors.values()]

    def table(self, *args, **kwargs):
        return self.lua.table(*args, **kwargs)


@pytest.fixture
def addon():
    """The whole addon, loaded in TOC order, before login."""
    return Addon(toc_files())


@pytest.fixture
def logic():
    """Only pure Logic/ files: no game API needed."""
    return Addon([f for f in toc_files() if f.startswith("Logic/")])
