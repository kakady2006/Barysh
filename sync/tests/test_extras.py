"""Import strings, Google sign-in, Sheets, 30-day series, capital, exports, tray status, end to end."""

import base64
import hashlib
import json
import random
import sys
from pathlib import Path

import pytest

from barysh_sync import db, exports, gauth, importstring, sheets, stats, tray
from barysh_sync.app import App
from barysh_sync.config import Config

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "tests"))
from conftest import Addon, saved_variables, to_py, toc_files  # noqa: E402

DAY = 86400
LINEN, BOLT = 2589, 2996


# import strings -------------------------------------------------------------------------------

def test_importstring_round_trip_and_compression():
    payload = {"kind": "list", "list": "stock", "items": {LINEN: {"buyBelow": 900, "note": "ящики " * 20}}}
    text = importstring.pack("list:stock", payload)
    assert text.startswith("!BARYSH:1!list:stock!")
    raw = base64.b64decode(text.rsplit("!", 1)[1])
    assert raw[:1] == b"Z"  # long notes compress
    assert importstring.unpack(text) == ("list:stock", payload)
    plain = importstring.pack("x", {"a": 1}, compress=False)
    assert importstring.unpack(plain) == ("x", {"a": 1})


@pytest.mark.parametrize("bad, err", [("hello", "format"), ("!BARYSH:9!x!AAAA", "version"), ("!BARYSH:1!x!@@@@", "data")])
def test_importstring_errors(bad, err):
    with pytest.raises(importstring.DecodeError, match=err):
        importstring.unpack(bad)


def test_python_string_imports_in_the_addon():
    text = importstring.list_string("stock", {LINEN: {"buyBelow": 900, "note": "ящики"}, BOLT: {}})
    # The addon test client has no real DEFLATE: send plain.
    text = importstring.pack("list:stock", importstring.unpack(text)[1], compress=False)
    addon = Addon(toc_files())
    addon.login()
    preview = addon.ns.ImportExport.Preview(text)
    assert to_py(preview.diff)["add"] == [LINEN, BOLT]
    addon.ns.ImportExport.Apply(preview)
    e = addon.ns.ItemLists.Entry("stock", LINEN)
    assert e.buyBelow == 900 and e.note == "ящики"


def test_addon_string_reads_in_python():
    addon = Addon(toc_files())
    addon.login()
    addon.lua.execute("C_EncodingUtil = nil")  # plain string
    addon.ns.ItemLists.Add("noBuy", LINEN)
    name, payload = importstring.unpack(addon.ns.ImportExport.ExportList("noBuy"))
    assert name == "list:noBuy" and payload["items"] == {LINEN: {}}


def test_serialization_matches_byte_for_byte():
    addon = Addon([f for f in toc_files() if f.startswith("Logic/")])
    value = {"kind": "list", "items": {LINEN: {"cap": 5, "note": "x"}, BOLT: {}}, "list": "q"}
    lua_text = addon.ns.Serialize.Encode(addon.to_lua(value))
    assert importstring.encode(value).decode() == lua_text


# Google sign-in -------------------------------------------------------------------------------

def _prime(bits, rnd):
    while True:
        n = rnd.getrandbits(bits) | (1 << (bits - 1)) | 1
        if all(pow(a, n - 1, n) == 1 for a in (2, 3, 5, 7, 11, 13, 17, 19, 23)):
            return n


def _der_int(v):
    b = v.to_bytes((v.bit_length() + 8) // 8, "big")
    return b"\x02" + _der_len(len(b)) + b


def _der_len(n):
    if n < 128:
        return bytes([n])
    b = n.to_bytes((n.bit_length() + 7) // 8, "big")
    return bytes([0x80 | len(b)]) + b


def _der_seq(*parts):
    body = b"".join(parts)
    return b"\x30" + _der_len(len(body)) + body


@pytest.fixture(scope="module")
def rsa_key():
    rnd = random.Random(42)
    e = 65537
    while True:
        p, q = _prime(512, rnd), _prime(512, rnd)
        phi = (p - 1) * (q - 1)
        if p != q and phi % e:
            break
    n, d = p * q, pow(e, -1, phi)
    pkcs1 = _der_seq(*(_der_int(x) for x in (0, n, e, d, p, q, d % (p - 1), d % (q - 1), pow(q, -1, p))))
    alg = _der_seq(b"\x06\x09\x2a\x86\x48\x86\xf7\x0d\x01\x01\x01", b"\x05\x00")
    pkcs8 = _der_seq(_der_int(0), alg, b"\x04" + _der_len(len(pkcs1)) + pkcs1)
    pem = "-----BEGIN PRIVATE KEY-----\n" + base64.encodebytes(pkcs8).decode() + "-----END PRIVATE KEY-----\n"
    return {"n": n, "e": e, "d": d, "pem": pem}


def test_private_key_parse_and_signature(rsa_key):
    n, d = gauth.private_key_from_pem(rsa_key["pem"])
    assert (n, d) == (rsa_key["n"], rsa_key["d"])
    sig = gauth.sign_rs256(b"hello", n, d)
    em = pow(int.from_bytes(sig, "big"), rsa_key["e"], n).to_bytes(len(sig), "big")
    assert em.startswith(b"\x00\x01\xff") and em.endswith(gauth.SHA256_PREFIX + hashlib.sha256(b"hello").digest())


def test_jwt_and_token_caching(rsa_key, tmp_path):
    key = {"client_email": "bot@x.iam.gserviceaccount.com", "private_key": rsa_key["pem"],
           "token_uri": "https://oauth2.googleapis.com/token", "private_key_id": "k1"}
    f = tmp_path / "key.json"
    f.write_text(json.dumps(key), encoding="utf-8")
    jwt = gauth.make_jwt(key, now=1000)
    head, claims, _ = jwt.split(".")
    pad = lambda s: s + "=" * (-len(s) % 4)  # noqa: E731
    assert json.loads(base64.urlsafe_b64decode(pad(head))) == {"alg": "RS256", "typ": "JWT", "kid": "k1"}
    c = json.loads(base64.urlsafe_b64decode(pad(claims)))
    assert c["iss"] == key["client_email"] and c["exp"] == 4600 and c["scope"] == gauth.SCOPE
    calls = []
    clock = [1000]

    def post(url, fields):
        calls.append(fields)
        return {"access_token": f"t{len(calls)}", "expires_in": 3600}

    sa = gauth.ServiceAccount(f, post=post, clock=lambda: clock[0])
    assert sa.access_token() == "t1" and sa.access_token() == "t1"
    clock[0] += 3590
    assert sa.access_token() == "t2"
    assert calls[0]["grant_type"].endswith("jwt-bearer")


# Sheets ---------------------------------------------------------------------------------------

class FakeAuth:
    def access_token(self):
        return "tok"


class FakeSheetsHTTP:
    def __init__(self, existing=()):
        self.calls = []
        self.existing = list(existing)

    def __call__(self, method, url, token, body=None):
        self.calls.append((method, url, body))
        if method == "GET":
            return {"sheets": [{"properties": {"title": t}} for t in self.existing]}
        return {}

    def bodies(self, part):
        return [b for m, u, b in self.calls if part in u]


def ledger_db():
    con = db.connect(":memory:")
    db.import_ledger(con, [
        {"id": 1, "t": 1_800_000_000, "kind": "ah_sell", "char": "Tester-Realm", "itemID": LINEN, "name": "Linen",
         "qty": 20, "amount": 9500, "profit": 3000},
        {"id": 2, "t": 1_800_000_100, "kind": "service", "char": "Tester-Realm", "amount": 50000, "profit": 50000,
         "note": "Enchant"},
    ])
    db.save_capital(con, "2027-01-15", 1_800_000_000,
                    {"gold": 10000, "bags": 500, "bank": 0, "mail": 0, "auctions": 0, "total": 10500})
    return con


def test_sheets_push_appends_only_new_operations():
    con = ledger_db()
    http = FakeSheetsHTTP(existing=[sheets.OPS])
    sh = sheets.Sheets("SID", FakeAuth(), request=http)
    data = {"profile": {"lists": {"stock": {"items": {BOLT: {"note": "рейд"}}}}},
            "chars": {"Tester-Realm": {"money": 1, "bags": {BOLT: 10}}}, "books": {BOLT: {"q": 10, "c": 5000}}}
    houses = {"R|Horde": {BOLT: (1000, 3.0, 40)}}
    n = sheets.push(con, sh, data, houses, db.get_meta, db.set_meta, now=1_800_000_200)
    assert n == 2
    added = [b for m, u, b in http.calls if u.endswith(":batchUpdate")][0]
    assert {r["addSheet"]["properties"]["title"] for r in added["requests"]} == {sheets.CAPITAL, sheets.STOCK, sheets.ACTIVITY}
    rows = http.bodies(":append")[0]["values"]
    assert rows[0][1] == "Продажа" and rows[0][2] == "Tester" and rows[0][5] == 0.95
    stock = [b for m, u, b in http.calls if m == "PUT" and "%D0%A1%D0%BA%D0%BB%D0%B0%D0%B4" in u][-1]["values"]
    assert stock[1][:2] == [BOLT, 10] and stock[1][-1] == "рейд" and stock[1][5] == 0.95  # 10 x 950 copper
    assert sheets.push(con, sh, data, houses, db.get_meta, db.set_meta) == 0  # nothing new


# series, capital, exports --------------------------------------------------------------------

def scans_db(days=5):
    con = db.connect(":memory:")
    base = 20_000 * DAY
    for d in range(days):
        t = base + d * DAY + 3600
        db.import_scan(con, {"ah": "R|Horde", "t": t, "full": True, "rows": 2, "items": {
            LINEN: {"s": f"{100 + d}:{50 - d}:90", "d": "5:100:3:s" if d else None, "a": "50:100:3" if not d else None},
        }})
    con.commit()
    return con, base + (days - 1) * DAY + 7200


def test_daily_series():
    con, now = scans_db()
    series = stats.daily_series(con, "R|Horde", now)
    prices, sales = series[LINEN]
    assert prices.split(",")[-5:] == ["100", "101", "102", "103", "104"]
    assert prices.split(",")[0] == "" and len(prices.split(",")) == 30
    assert sales.split(",")[-4:] == ["5", "5", "5", "5"]
    con2, now2 = scans_db(days=2)
    assert stats.daily_series(con2, "R|Horde", now2) == {}  # too few days


def test_capital():
    houses = {"R|Horde": {LINEN: (100, 1.0, 5)}, "R|Neutral": {LINEN: (200, 1.0, 2)}}
    c = stats.capital({"A": {"money": 1000, "mailMoney": 5, "bags": {LINEN: 10}, "auctions": [3]}}, houses)
    assert c == {"gold": 1005, "bags": 950, "bank": 0, "mail": 0, "auctions": 0, "total": 1955}


def test_export_file(tmp_path):
    con, now = scans_db()
    path = exports.build(con, {"t": now, "ah": "R|Horde", "items": [LINEN]}, tmp_path, {"R|Horde": {LINEN: (101, 4.0, 5)}}, now)
    data = json.loads(path.read_text(encoding="utf-8"))
    assert data["auction_house"] == "Horde"
    item = data["items"][0]
    assert item["item_id"] == LINEN and len(item["prices"]) == 5 and item["market"]["price"] == 101
    assert {e["kind"] for e in item["lot_events"]} == {"a", "d"}
    path2 = exports.build(con, {"t": now + 1, "ah": "R|Horde", "items": []}, tmp_path, {}, now)
    assert json.loads(path2.read_text(encoding="utf-8"))["items"][0]["item_id"] == LINEN


def test_tray_status_text():
    assert "ждёт" in tray.status_text(None)
    s = tray.status_text({"t": 1_800_000_000, "sheets": 3, "errors_sent": 1, "exports": 0})
    assert s.startswith("BaryshSync · синхронизация ") and "таблица +3" in s and len(s) <= tray.TIP_MAX


# end to end -----------------------------------------------------------------------------------

def test_end_to_end_capital_exports_sheets_and_series(tmp_path):
    game = tmp_path / "_forever_"
    (game / "Interface" / "AddOns" / "Barysh" / "Data").mkdir(parents=True)
    sv = game / "WTF" / "Account" / "ACC" / "SavedVariables" / "Barysh.lua"
    sv.parent.mkdir(parents=True)
    cfg = Config(game_dir=game, data_dir=tmp_path / "data", github_issues=False)

    addon = Addon(toc_files())
    addon.lua.execute(f'WowMock.items[{LINEN}] = {{ name = "Linen Cloth", quality = 1, ilvl = 5, classID = 7, sellPrice = 13, stack = 20 }}')
    addon.login()
    addon.ns.SetModuleEnabled("Sync", True)
    addon.lua.execute(f"WowMock.money = 12345; WowMock.bags[0][1] = {{ itemID = {LINEN}, count = 20 }}")
    addon.fire("PLAYER_MONEY")
    addon.ns.Inventory.SaveBags()
    addon.fire("AUCTION_HOUSE_SHOW")
    addon.lua.execute(f"WowMock.replicate = {{ {{ {LINEN}, 20, 200, 3 }} }}")
    addon.ns.Scan.StartFull("button")
    addon.mock.Advance(3)
    addon.ns.MarketModule.RequestExport(addon.to_lua([LINEN]))
    addon.ns.Record(addon.to_lua({"kind": "ah_sell", "itemID": LINEN, "qty": 20, "amount": 190, "profit": 50}))
    sv.write_bytes(saved_variables(addon.g.BaryshDB, "BaryshDB"))

    http = FakeSheetsHTTP(existing=list(sheets.HEADERS))
    app = App(cfg, github=None, clock=lambda: addon.g.time(), sheets_client=sheets.Sheets("SID", FakeAuth(), request=http))
    app.github = None
    summary = app.poll_once()[0]
    assert summary["exports"] == 1 and summary["sheets"] == 1
    assert list(cfg.exports.glob("barysh-export-*.json"))
    con = db.connect(cfg.database)
    gold, bags = con.execute("SELECT gold, bags FROM capital").fetchone()
    assert gold == 12345 and bags == 20 * 9  # 10 copper * 0.95, rounded down
    assert app.last is summary

    market = (game / "Interface" / "AddOns" / "Barysh" / "Data" / "Market.lua").read_text(encoding="utf-8")
    again = Addon(toc_files(), overrides={"Data/Market.lua": market})
    again.lua.execute(sv.read_text(encoding="utf-8"))
    again.login()
    again.ns.SetModuleEnabled("Sync", True)
    again.ns.Sync.ApplyAck()
    assert len(again.g.BaryshDB.exportRequests) == 0
    assert again.errors() == []
