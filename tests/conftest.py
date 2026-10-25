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
    def __init__(self, files, overrides=None):
        """overrides: {relative path: source} to replace a file (e.g. a generated Data/Market.lua)."""
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
        overrides = overrides or {}
        for rel in files:
            loader(overrides.get(rel) or source_for(rel), rel, ADDON_NAME, self.ns)
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

    def to_lua(self, obj):
        """Python dicts/lists -> Lua tables, recursively."""
        if isinstance(obj, dict):
            return self.lua.table_from({k: self.to_lua(v) for k, v in obj.items()})
        if isinstance(obj, (list, tuple)):
            return self.lua.table_from([self.to_lua(v) for v in obj])
        return obj

    def lots(self, *triples):
        """(qty, price, tl) -> Lua lot list."""
        return self.to_lua([{"qty": q, "price": p, "tl": t} for q, p, t in triples])


def saved_variables(value, name):
    """Writes a Lua value the way the WoW client writes SavedVariables files (UTF-8 bytes)."""
    out = [f"\n{name} = "]

    def emit(v, depth):
        t = lua51.lua_type(v)
        if t == "table":
            out.append("{\n")
            keys = list(v.keys())
            seq = keys == list(range(1, len(keys) + 1))
            for k in keys:
                out.append("\t" * (depth + 1))
                if not seq:
                    out.append(f'["{k}"] = ' if isinstance(k, str) else f"[{k}] = ")
                emit(v[k], depth + 1)
                out.append(f", -- [{k}]\n" if seq else ",\n")
            out.append("\t" * depth + "}")
        elif isinstance(v, bool):
            out.append("true" if v else "false")
        elif isinstance(v, str):
            out.append('"' + v.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n") + '"')
        elif v is None:
            out.append("nil")
        else:
            out.append(repr(v))

    emit(value, 0)
    out.append("\n")
    return "".join(out).encode("utf-8")


def to_py(value):
    """Lua tables -> Python: sequences become lists, the rest dicts."""
    if lua51.lua_type(value) != "table":
        return value
    keys = list(value.keys())
    if keys == list(range(1, len(keys) + 1)):
        return [to_py(value[k]) for k in keys]
    return {k: to_py(value[k]) for k in keys}


@pytest.fixture
def addon():
    """The whole addon, loaded in TOC order, before login."""
    return Addon(toc_files())


@pytest.fixture
def logic():
    """Only pure Logic/ files: no game API needed."""
    return Addon([f for f in toc_files() if f.startswith("Logic/")])
