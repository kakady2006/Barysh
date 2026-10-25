"""Item lists, serialization and import strings."""

import pytest

from conftest import to_py


@pytest.mark.parametrize("value", [
    {"a": 1, "b": [1, 2, 3], "c": {"d": "текст", "e": True, "f": False}},
    {1: {"buyBelow": 12345678901, "note": "a:b;c{}"}, 2: {}},
    {"x": 0.25, "y": -7},
])
def test_serialize_round_trip(logic, value):
    s = logic.ns.Serialize
    text = s.Encode(logic.to_lua(value))
    back = to_py(s.Decode(text))
    if value == {1: {"buyBelow": 12345678901, "note": "a:b;c{}"}, 2: {}}:
        assert back == [{"buyBelow": 12345678901, "note": "a:b;c{}"}, []]
    else:
        assert back == {k: (list(v) if isinstance(v, list) else v) for k, v in value.items()}


def test_serialize_is_canonical(logic):
    s = logic.ns.Serialize
    a = s.Encode(logic.to_lua({"b": 1, "a": 2, 3: "x"}))
    b = s.Encode(logic.to_lua({3: "x", "a": 2, "b": 1}))
    assert a == b == "{i3;s1:xs1:ai2;s1:bi1;}"


@pytest.mark.parametrize("bad", ["", "{", "s5:ab", "i12", "{T", "x", "{i1;i2;}junk"])
def test_decode_rejects_garbage(logic, bad):
    v, err = logic.ns.Serialize.Decode(bad)
    assert v is None and err


@pytest.mark.parametrize("raw", [b"", b"f", b"fo", b"foo", b"foob", b"\x00\xff\x10binary"])
def test_base64(logic, raw):
    import base64
    s = logic.ns.Serialize
    # Build the Lua string byte by byte: Python str would be passed as UTF-8.
    lua_raw = '"' + "".join(f"\\{b}" for b in raw) + '"'
    enc = logic.lua.eval(f"function(S) return S.ToBase64({lua_raw}) end")(s)
    assert enc == base64.b64encode(raw).decode()
    same = logic.lua.eval(f"function(S, e) return S.FromBase64(e) == {lua_raw} end")
    assert same(s, enc)


def test_pack_unpack(logic):
    s = logic.ns.Serialize
    payload = logic.to_lua({"kind": "list", "list": "stock", "items": {2589: {"buyBelow": 900, "note": "ящики"}}})
    text = s.Pack("list:stock!", payload)
    assert text.startswith("!BARYSH:1!list:stock!")
    name, back = s.Unpack("  " + text + "\n")
    assert name == "list:stock"
    assert to_py(back)["items"][2589]["note"] == "ящики"
    assert s.Unpack("hello") == (None, "format")
    assert s.Unpack("!BARYSH:9!x!AAAA") == (None, "version")
    assert s.Unpack("!BARYSH:1!x!@@@@") == (None, "data")


def test_pack_uses_compressor_when_smaller(logic):
    s = logic.ns.Serialize
    compress = logic.lua.eval("function(s) return 'zz' end")
    decompress = logic.lua.eval("function(z) return z == 'zz' and '{s1:ai1;}' or nil end")
    text = s.Pack("x", logic.to_lua({"a": 1, "long": "y" * 50}), compress)
    assert s.Unpack(text) == (None, "compressed")
    name, back = s.Unpack(text, decompress)
    assert to_py(back) == {"a": 1}


def test_lists_add_remove_and_diff(logic):
    L = logic.ns.Lists
    lst = L.New()
    assert L.Add(lst, 10, None, "manual", 1)
    assert not L.Add(lst, 10, logic.to_lua({"note": "x"}))
    L.Add(lst, 20, None, "import", 1)
    L.Add(lst, 30, logic.to_lua({"buyBelow": 5}), "import", 1)
    assert to_py(L.Ids(lst)) == [10, 20, 30]
    incoming = logic.to_lua({"items": {30: {"buyBelow": 7}, 40: {}}})
    d = to_py(L.Diff(lst, incoming))
    assert d == {"add": [40], "remove": [20], "change": [30]}
    L.Apply(lst, incoming, 2)
    assert to_py(L.Ids(lst)) == [10, 30, 40]
    items = lst["items"]
    assert items[30].buyBelow == 7 and items[10].src == "manual" and items[40].src == "import"


def test_lists_migrate_old_formats(logic):
    L = logic.ns.Lists
    assert to_py(L.Ids(L.Migrate(logic.to_lua([5, 6])))) == [5, 6]
    assert to_py(L.Ids(L.Migrate(logic.to_lua({7: True})))) == [7]


def test_settings_diff(logic):
    d = to_py(logic.ns.Lists.SettingsDiff(
        logic.to_lua({"deals": {"minProfit": 100, "caution": "normal"}, "x": 1}),
        logic.to_lua({"deals": {"minProfit": 500, "caution": "normal"}, "y": 2}),
    ))
    assert d == [
        {"path": "deals.minProfit", "old": 100, "new": 500},
        {"path": "x", "old": 1},
        {"path": "y", "new": 2},
    ]
