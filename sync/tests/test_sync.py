import random
import sqlite3
import subprocess
import sys
from pathlib import Path

import pytest

from barysh_sync import backup, db, errors, luadata, pricing, stats
from barysh_sync.app import App
from barysh_sync.config import Config

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "tests"))
from conftest import Addon, saved_variables, to_py, toc_files  # noqa: E402


# luadata -------------------------------------------------------------------------------

WOW_SV = '''
BaryshDB = {
	["schema"] = 1,
	["profile"] = {
		["language"] = "ruRU",
		["deals"] = {
			["minProfit"] = 100,
			["caution"] = "normal",
		},
	},
	["errors"] = {
		{
			["msg"] = "Interface\\\\AddOns\\\\Barysh\\\\x.lua:1: \\"boom\\"",
			["count"] = 2,
		}, -- [1]
	},
	["empty"] = {
	},
	["neg"] = -1.5e-3,
	["flag"] = false,
	[2589] = "Льняная ткань",
}
'''


def test_parse_wow_saved_variables():
    data = luadata.loads(WOW_SV.encode("utf-8").decode("latin-1"))["BaryshDB"]
    assert data["profile"]["deals"] == {"minProfit": 100, "caution": "normal"}
    assert data["errors"] == [{"msg": 'Interface\\AddOns\\Barysh\\x.lua:1: "boom"', "count": 2}]
    assert data["empty"] == {}
    assert data["neg"] == -0.0015
    assert data["flag"] is False
    assert data[2589] == "Льняная ткань"


def test_dump_and_parse_round_trip():
    value = {"a": [1, 2, {"b": "x\"y\n"}], 5: {"k": 1.25, "n": None}, "deep": {"list": [[1, 2], [3]]}}
    text = "X = " + luadata.dumps(value)
    back = luadata.loads(text)["X"]
    assert back["a"] == [1, 2, {"b": "x\"y\n"}]
    assert back[5] == {"k": 1.25}
    assert back["deep"]["list"] == [[1, 2], [3]]


def test_parse_error_is_reported():
    with pytest.raises(luadata.LuaParseError):
        luadata.loads("BaryshDB = { [1] = ")


# pricing parity with the addon ------------------------------------------------------------

def test_market_price_matches_addon():
    lua = Addon([f for f in toc_files() if f.startswith("Logic/")])
    rnd = random.Random(7)
    now = 1_800_000_000
    for _ in range(50):
        scans = [(now - rnd.randint(0, 9 * 86400), rnd.randint(1, 5000)) for _ in range(rnd.randint(1, 30))]
        lua_scans = lua.to_lua([{"time": t, "price": p} for t, p in scans])
        for caution in ("normal", "careful", "bold"):
            assert pricing.market_price(scans, now, caution) == lua.ns.Pricing.MarketPrice(lua_scans, now, caution)


def test_prices_at_scans_forward_fill():
    changes = [(100, 50, 3), (300, None, 0), (500, 70, 1)]
    assert pricing.prices_at_scans(changes, [50, 100, 200, 300, 400, 500, 600]) == [
        (100, 50), (200, 50), (500, 70), (600, 70)]


def test_per_day():
    now = 10 * 86400
    sold = [(now - 86400, 10), (now - 20 * 86400, 99)]
    assert pricing.per_day(sold, now, 7, None) == 10 / 7
    assert pricing.per_day(sold, now, 7, now - 3600) == 10


# errors ---------------------------------------------------------------------------------

def test_anonymizer():
    anon = errors.Anonymizer(errors.names_from_chars({"Грокаш-Realm": {}, "Tester-Realm": {}}))
    text = "C:\\Users\\kiril\\WTF\\Account\\MYACC\\x Грокаш said to Tester-Realm"
    out = anon(text)
    assert "kiril" not in out and "MYACC" not in out and "Грокаш" not in out and "Tester" not in out
    assert "<user>" in out and "<account>" in out and "Character" in out


class FakeGitHub:
    def __init__(self):
        self.issues, self.comments = [], []

    def ensure_label(self):
        pass

    def create_issue(self, title, body):
        self.issues.append((title, body))
        return len(self.issues)

    def comment(self, number, body):
        self.comments.append((number, body))


def test_report_errors_creates_then_comments():
    con = db.connect(":memory:")
    err = {"key": "k", "msg": "Barysh/x.lua:1: boom for Грокаш", "stack": "s", "version": "0.1", "count": 1,
           "first": 1, "last": 1}
    db.import_errors(con, [err], errors.key_hash)
    gh = FakeGitHub()
    anon = errors.Anonymizer(["Грокаш"])
    assert errors.report_errors(con, gh, anon) == 1
    assert len(gh.issues) == 1 and "Грокаш" not in gh.issues[0][1]
    assert errors.report_errors(con, gh, anon) == 0
    db.import_errors(con, [dict(err, count=3, last=5)], errors.key_hash)
    assert errors.report_errors(con, gh, anon) == 1
    assert gh.comments == [(1, "Повтор: всего 3 раз, версия 0.1.")]


def test_github_failure_is_retried_later():
    con = db.connect(":memory:")
    db.import_errors(con, [{"key": "k", "msg": "m", "count": 1, "last": 1}], errors.key_hash)

    class Broken(FakeGitHub):
        def create_issue(self, title, body):
            raise subprocess.CalledProcessError(1, "gh")

    assert errors.report_errors(con, Broken(), errors.Anonymizer(), log=lambda m: None) == 0
    assert errors.report_errors(con, FakeGitHub(), errors.Anonymizer()) == 1


# backup ---------------------------------------------------------------------------------

def test_backup_keeps_newest(tmp_path):
    sv = tmp_path / "WTF" / "Account" / "ACC" / "SavedVariables" / "Barysh.lua"
    sv.parent.mkdir(parents=True)
    sv.write_text("BaryshDB = {}", encoding="utf-8")
    for i in range(5):
        backup.make_backup(sv, tmp_path / "b", keep=3, now=1_800_000_000 + i)
    assert len(list((tmp_path / "b" / "ACC").glob("*.lua"))) == 3


def test_truncated_detection(tmp_path):
    f = tmp_path / "Barysh.lua"
    f.write_text("", encoding="utf-8")
    assert backup.looks_truncated(f)
    f.write_text("BaryshDB = {}", encoding="utf-8")
    assert not backup.looks_truncated(f)


# end to end -----------------------------------------------------------------------------

LINEN, GLOVES = 2589, 5000


def play(addon, replicate_rows):
    addon.lua.execute(f"""
        WowMock.items[{LINEN}] = {{ name = "Linen Cloth", quality = 1, ilvl = 5, classID = 7, sellPrice = 13 }}
        WowMock.items[{GLOVES}] = {{ name = "Gloves", quality = 2, ilvl = 22, classID = 4, sellPrice = 300 }}
    """)
    for i, rows in enumerate(replicate_rows):
        body = ", ".join(f"{{ {a}, {b}, {c}, {d} }}" for a, b, c, d in rows)
        addon.lua.execute(f"WowMock.replicate = {{ {body} }}")
        if i == 0:
            addon.ns.Scan.StartFull("button")
            addon.mock.Advance(3)
        else:
            addon.mock.Advance(15 * 60 + 10)  # the 15-minute timer scans again


@pytest.fixture
def install(tmp_path):
    game = tmp_path / "_forever_"
    (game / "Interface" / "AddOns" / "Barysh" / "Data").mkdir(parents=True)
    sv = game / "WTF" / "Account" / "ACC" / "SavedVariables" / "Barysh.lua"
    sv.parent.mkdir(parents=True)
    cfg = Config(game_dir=game, data_dir=tmp_path / "data", github_issues=False)
    return game, sv, cfg


def test_end_to_end_addon_sync_addon(install):
    game, sv, cfg = install
    addon = Addon(toc_files())
    addon.login()
    addon.ns.SetModuleEnabled("Sync", True)
    addon.fire("AUCTION_HOUSE_SHOW")
    play(addon, [
        [(LINEN, 20, 200, 3), (LINEN, 20, 200, 3), (GLOVES, 1, 5000, 3)],
        [(LINEN, 20, 200, 3), (GLOVES, 1, 5000, 3)],
    ])
    addon.ns.Record(addon.to_lua({"kind": "ah_sell", "itemID": LINEN, "qty": 20, "amount": 190, "profit": 50}))
    addon.ns.Safe(addon.lua.eval("function() error('boom in Tester') end"))
    assert len(addon.g.BaryshDB.outbox) == 2
    sv.write_bytes(saved_variables(addon.g.BaryshDB, "BaryshDB"))

    gh = FakeGitHub()
    app = App(cfg, github=gh, clock=lambda: addon.g.time())
    done = app.poll_once()
    assert len(done) == 1 and "skipped" not in done[0]
    assert app.poll_once() == []  # unchanged file is not processed again

    con = sqlite3.connect(cfg.database)
    assert con.execute("SELECT COUNT(*) FROM scans").fetchone()[0] == 2
    sold = con.execute("SELECT qty, verdict FROM lot_events WHERE kind = 'd'").fetchall()
    assert sold == [(20, "sold")]
    assert con.execute("SELECT kind, amount FROM ledger").fetchall() == [("ah_sell", 190)]
    assert len(gh.issues) == 1 and "Tester" not in gh.issues[0][1]
    assert list((cfg.backups / "ACC").glob("*.lua"))

    market = (game / "Interface" / "AddOns" / "Barysh" / "Data" / "Market.lua").read_text(encoding="utf-8")
    # Next /reload: the addon reads Market.lua, drops what was stored and uses the PC prices.
    again = Addon(toc_files(), overrides={"Data/Market.lua": market})
    again.lua.execute(sv.read_text(encoding="utf-8"))  # the client loads SavedVariables as Lua code
    again.login()
    again.ns.SetModuleEnabled("Sync", True)
    again.ns.Sync.ApplyAck()
    assert len(again.g.BaryshDB.outbox) == 0
    assert len(again.g.BaryshDB.errors) == 0
    m = to_py(again.ns.market)
    assert m["ah"]["TestRealm|Horde"][LINEN][0] == 10
    s = again.ns.Prices.Item(LINEN, "TestRealm|Horde")
    assert s.synced.price == 10
    assert again.errors() == []


def test_truncated_file_is_skipped(install):
    game, sv, cfg = install
    sv.write_text("", encoding="utf-8")
    app = App(cfg, github=FakeGitHub())
    assert app.poll_once() == [{"skipped": "truncated"}]


def test_stats_empty_db():
    con = db.connect(":memory:")
    assert stats.houses(con) == []
