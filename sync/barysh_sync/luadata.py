"""Reading and writing the Lua table format WoW uses for SavedVariables."""

import math
import re

_TOKEN = re.compile(
    r"""
    (?P<ws>\s+|--\[\[.*?\]\]|--[^\n]*)
  | (?P<str>"(?:[^"\\]|\\.|\\\n)*")
  | (?P<num>-?(?:0[xX][0-9a-fA-F]+|(?:\d+\.?\d*|\.\d+)(?:[eE][+-]?\d+)?))
  | (?P<inf>-?(?:inf|nan)\b)
  | (?P<name>[A-Za-z_][A-Za-z0-9_]*)
  | (?P<op>[{}\[\]=,;])
    """,
    re.VERBOSE | re.DOTALL,
)

_ESCAPES = {"n": "\n", "t": "\t", "r": "\r", "a": "\a", "b": "\b", "f": "\f", "v": "\v",
            "\\": "\\", '"': '"', "'": "'", "\n": "\n"}


class LuaParseError(ValueError):
    pass


def _unescape(body):
    out = []
    i = 0
    n = len(body)
    while i < n:
        c = body[i]
        if c != "\\":
            out.append(c)
            i += 1
            continue
        i += 1
        e = body[i]
        if e.isdigit():
            j = i
            while j < n and j < i + 3 and body[j].isdigit():
                j += 1
            out.append(chr(int(body[i:j])))
            i = j
        else:
            out.append(_ESCAPES.get(e, e))
            i += 1
    # Lua strings are bytes; WoW writes UTF-8.
    raw = "".join(out)
    try:
        return raw.encode("latin-1").decode("utf-8")
    except (UnicodeEncodeError, UnicodeDecodeError):
        return raw


def _tokens(text):
    pos = 0
    n = len(text)
    while pos < n:
        m = _TOKEN.match(text, pos)
        if not m:
            raise LuaParseError(f"unexpected character {text[pos]!r} at {pos}")
        pos = m.end()
        kind = m.lastgroup
        if kind == "ws":
            continue
        yield kind, m.group(kind), m.start()


class _Parser:
    def __init__(self, text):
        self.toks = list(_tokens(text))
        self.i = 0

    def peek(self):
        return self.toks[self.i] if self.i < len(self.toks) else (None, None, -1)

    def take(self, kind=None, value=None):
        tok = self.peek()
        if tok[0] is None:
            raise LuaParseError("unexpected end of input")
        if (kind and tok[0] != kind) or (value is not None and tok[1] != value):
            raise LuaParseError(f"expected {value or kind} at {tok[2]}, got {tok[1]!r}")
        self.i += 1
        return tok

    def value(self):
        kind, text, pos = self.peek()
        if kind == "op" and text == "{":
            return self.table()
        self.i += 1
        if kind == "str":
            return _unescape(text[1:-1])
        if kind == "num":
            if text.lower().lstrip("-").startswith("0x"):
                return int(text, 16)
            if re.fullmatch(r"-?\d+", text):
                return int(text)
            return float(text)
        if kind == "inf":
            return float(text)
        if kind == "name":
            if text == "true":
                return True
            if text == "false":
                return False
            if text == "nil":
                return None
        raise LuaParseError(f"unexpected {text!r} at {pos}")

    def table(self):
        self.take("op", "{")
        result = {}
        index = 1
        while True:
            kind, text, _ = self.peek()
            if kind == "op" and text == "}":
                self.i += 1
                return _normalize(result)
            # A nil value means "no entry" in Lua.
            if kind == "op" and text == "[":
                self.i += 1
                key = self.value()
                self.take("op", "]")
                self.take("op", "=")
                v = self.value()
                if v is not None:
                    result[key] = v
            elif kind == "name" and self.i + 1 < len(self.toks) and self.toks[self.i + 1][1] == "=":
                self.i += 2
                v = self.value()
                if v is not None:
                    result[text] = v
            else:
                v = self.value()
                if v is not None:
                    result[index] = v
                index += 1
            kind, text, _ = self.peek()
            if kind == "op" and text in ",;":
                self.i += 1

    def assignments(self):
        out = {}
        while self.peek()[0] is not None:
            _, name, _ = self.take("name")
            self.take("op", "=")
            out[name] = self.value()
        return out


def _normalize(t):
    """A table with keys 1..n becomes a list; an empty table becomes an empty dict."""
    if t and all(isinstance(k, int) for k in t):
        keys = sorted(t)
        if keys == list(range(1, len(keys) + 1)):
            return [t[k] for k in keys]
    return t


def loads(text):
    """Parse a SavedVariables file: {global name: value}."""
    return _Parser(text).assignments()


def as_list(value):
    """Lua sequences may arrive as list or (when empty) dict."""
    if value is None:
        return []
    if isinstance(value, list):
        return value
    if isinstance(value, dict):
        return [value[k] for k in sorted(k for k in value if isinstance(k, int))]
    return [value]


def _dump_string(s):
    s = s.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n").replace("\r", "\\r")
    return f'"{s}"'


def _dump_key(k):
    if isinstance(k, str) and re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*", k):
        return k
    if isinstance(k, str):
        return f"[{_dump_string(k)}]"
    return f"[{dumps(k)}]"


def dumps(value, indent=0):
    """Python -> Lua source. Lists become sequences, dicts become keyed tables."""
    if value is None:
        return "nil"
    if value is True:
        return "true"
    if value is False:
        return "false"
    if isinstance(value, int):
        return str(value)
    if isinstance(value, float):
        if math.isinf(value):
            return "math.huge" if value > 0 else "-math.huge"
        if value == int(value) and abs(value) < 2**53:
            return str(int(value))
        return repr(round(value, 4))
    if isinstance(value, str):
        return _dump_string(value)
    pad = "\t" * (indent + 1)
    if isinstance(value, (list, tuple)):
        if all(not isinstance(v, (dict, list, tuple)) for v in value):
            return "{" + ", ".join(dumps(v) for v in value) + "}"
        items = [pad + dumps(v, indent + 1) for v in value]
    elif isinstance(value, dict):
        items = [f"{pad}{_dump_key(k)} = {dumps(v, indent + 1)}" for k, v in value.items()]
    else:
        raise TypeError(f"cannot dump {type(value).__name__}")
    if not items:
        return "{}"
    return "{\n" + ",\n".join(items) + ",\n" + "\t" * indent + "}"
