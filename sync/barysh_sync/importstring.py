"""Barysh import strings: !BARYSH:<version>!<name>!<base64(mode + body)>. Mirrors Barysh/Logic/Serialize.lua.

mode "P": body is the plain serialized value; mode "Z": body is raw DEFLATE of it.
Values: integer "i<n>;", float "f<n>;", string "s<len>:<bytes>", true "T", false "F",
table "{" key value ... "}" with keys sorted (numbers before strings, as in Lua's type-name order).
"""

import base64
import json
import re
import zlib

VERSION = 1
PREFIX = "!BARYSH:"


def _key_order(k):
    # Lua sorts by type name first ("number" < "string"), then by value.
    return (0, k, "") if isinstance(k, (int, float)) else (1, 0, k)


def _encode(v, out):
    if isinstance(v, bool):
        out.append(b"T" if v else b"F")
    elif isinstance(v, int) or (isinstance(v, float) and v.is_integer() and abs(v) < 2 ** 53):
        out.append(b"i%d;" % int(v))
    elif isinstance(v, float):
        out.append(b"f" + repr(v).encode() + b";")
    elif isinstance(v, str):
        raw = v.encode("utf-8")
        out.append(b"s%d:" % len(raw) + raw)
    elif isinstance(v, (list, tuple)):
        _encode({i + 1: x for i, x in enumerate(v)}, out)
    elif isinstance(v, dict):
        out.append(b"{")
        for k in sorted((k for k in v if isinstance(k, (int, float, str)) and not isinstance(k, bool)), key=_key_order):
            if v[k] is None:
                continue
            _encode(k, out)
            _encode(v[k], out)
        out.append(b"}")
    else:
        raise TypeError(f"cannot serialize {type(v).__name__}")


def encode(value):
    out = []
    _encode(value, out)
    return b"".join(out)


class DecodeError(ValueError):
    pass


def _decode(s, pos, depth):
    c = s[pos:pos + 1]
    if c in (b"i", b"f"):
        stop = s.find(b";", pos)
        if stop < 0:
            raise DecodeError("bad number")
        text = s[pos + 1:stop].decode()
        try:
            n = int(text) if c == b"i" else float(text)
        except ValueError as e:
            raise DecodeError("bad number") from e
        return n, stop + 1
    if c == b"s":
        colon = s.find(b":", pos)
        if colon < 0 or not s[pos + 1:colon].isdigit():
            raise DecodeError("bad string")
        n = int(s[pos + 1:colon])
        if colon + n >= len(s) + 1:
            raise DecodeError("bad string")
        return s[colon + 1:colon + 1 + n].decode("utf-8"), colon + 1 + n
    if c == b"T":
        return True, pos + 1
    if c == b"F":
        return False, pos + 1
    if c == b"{":
        if depth > 20:
            raise DecodeError("too deep")
        t = {}
        pos += 1
        while s[pos:pos + 1] != b"}":
            if pos >= len(s):
                raise DecodeError("unterminated table")
            k, pos = _decode(s, pos, depth + 1)
            if isinstance(k, (dict, bool)):
                raise DecodeError("bad key")
            v, pos = _decode(s, pos, depth + 1)
            t[k] = v
        return t, pos + 1
    raise DecodeError(f"unexpected {c!r}")


def decode(data):
    value, pos = _decode(data, 0, 0)
    if pos != len(data):
        raise DecodeError("trailing data")
    return value


def pack(name, payload, compress=True):
    name = str(name).replace("!", "")
    body = encode(payload)
    data = b"P" + body
    if compress:
        c = zlib.compressobj(9, zlib.DEFLATED, -15)
        z = c.compress(body) + c.flush()
        if len(z) + 1 < len(data):
            data = b"Z" + z
    return f"{PREFIX}{VERSION}!{name}!{base64.b64encode(data).decode()}"


def unpack(text):
    """Returns (name, payload). Raises DecodeError."""
    m = re.fullmatch(r"!BARYSH:(\d+)!([^!]*)!(.+)", text.strip(), re.S)
    if not m:
        raise DecodeError("format")
    if int(m.group(1)) > VERSION:
        raise DecodeError("version")
    try:
        raw = base64.b64decode(re.sub(r"\s", "", m.group(3)), validate=True)
    except ValueError as e:
        raise DecodeError("data") from e
    mode, body = raw[:1], raw[1:]
    if mode == b"Z":
        try:
            body = zlib.decompress(body, -15)
        except zlib.error as e:
            raise DecodeError("data") from e
    elif mode != b"P":
        raise DecodeError("data")
    payload = decode(body)
    if not isinstance(payload, dict):
        raise DecodeError("data")
    return m.group(2), payload


def list_string(list_name, items):
    """items: {itemID: {buyBelow, cap, note}} (copper) -> a string the addon imports into that list."""
    clean = {int(i): {k: v for k, v in (fields or {}).items() if k in ("buyBelow", "cap", "note") and v is not None}
             for i, fields in items.items()}
    return pack("list:" + list_name, {"kind": "list", "list": list_name, "items": clean})


def main(argv):
    """encode <file.json> | decode <string>: for preparing lists outside the game."""
    if len(argv) == 2 and argv[0] == "decode":
        name, payload = unpack(argv[1])
        print(json.dumps({"name": name, "payload": payload}, ensure_ascii=False, indent=1))
        return 0
    if len(argv) == 2 and argv[0] == "encode":
        with open(argv[1], encoding="utf-8-sig") as f:
            spec = json.load(f)
        print(list_string(spec["list"], {int(k): v for k, v in spec["items"].items()}))
        return 0
    print("usage: python -m barysh_sync.importstring encode list.json | decode '!BARYSH:...'")
    return 2


if __name__ == "__main__":
    import sys
    raise SystemExit(main(sys.argv[1:]))
