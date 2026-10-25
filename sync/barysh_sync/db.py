"""SQLite database with the whole history: scans as lot changes, ledger, characters, errors."""

import json
import sqlite3

from .luadata import as_list

SCHEMA = """
CREATE TABLE IF NOT EXISTS scans (
    id INTEGER PRIMARY KEY,
    ah TEXT NOT NULL,
    t INTEGER NOT NULL,
    full INTEGER NOT NULL,
    rows INTEGER,
    UNIQUE (ah, t)
);
-- kind: a = lot appeared, d = lot vanished (verdict s/u/e), r = stack reduced (qty -> qty_to)
CREATE TABLE IF NOT EXISTS lot_events (
    scan_id INTEGER NOT NULL REFERENCES scans(id),
    item_id INTEGER NOT NULL,
    kind TEXT NOT NULL,
    qty INTEGER NOT NULL,
    price INTEGER NOT NULL,
    tl INTEGER,
    verdict TEXT,
    qty_to INTEGER
);
CREATE INDEX IF NOT EXISTS lot_events_item ON lot_events (item_id, scan_id);
-- Scan price change points per item
CREATE TABLE IF NOT EXISTS item_prices (
    scan_id INTEGER NOT NULL REFERENCES scans(id),
    item_id INTEGER NOT NULL,
    price INTEGER,
    qty INTEGER NOT NULL,
    min INTEGER,
    PRIMARY KEY (scan_id, item_id)
);
CREATE INDEX IF NOT EXISTS item_prices_item ON item_prices (item_id);
CREATE TABLE IF NOT EXISTS ledger (
    id INTEGER PRIMARY KEY,
    t INTEGER NOT NULL,
    kind TEXT NOT NULL,
    char TEXT,
    item_id INTEGER,
    name TEXT,
    qty INTEGER,
    amount INTEGER,
    profit INTEGER,
    note TEXT
);
CREATE TABLE IF NOT EXISTS chars (
    name TEXT PRIMARY KEY,
    money INTEGER,
    t INTEGER,
    faction TEXT
);
CREATE TABLE IF NOT EXISTS errors (
    key_hash TEXT PRIMARY KEY,
    msg TEXT,
    stack TEXT,
    version TEXT,
    count INTEGER,
    first INTEGER,
    last INTEGER,
    reported_count INTEGER DEFAULT 0,
    issue INTEGER
);
-- Capital per day (as the addon's overview counts it). Rows of the "Капитал по дням" sheet.
CREATE TABLE IF NOT EXISTS capital (
    day TEXT PRIMARY KEY,
    t INTEGER,
    gold INTEGER, bags INTEGER, bank INTEGER, mail INTEGER, auctions INTEGER, total INTEGER
);
-- Trade clients. Names stay on this PC: never sent to GitHub or Google.
CREATE TABLE IF NOT EXISTS clients (
    name TEXT PRIMARY KEY,
    orders INTEGER,
    sum INTEGER,
    last INTEGER
);
CREATE TABLE IF NOT EXISTS probe (
    t INTEGER PRIMARY KEY,
    data TEXT
);
CREATE TABLE IF NOT EXISTS meta (
    k TEXT PRIMARY KEY,
    v TEXT
);
"""

VERDICTS = {"s": "sold", "u": "unknown", "e": "expired"}


def connect(path):
    # The tray runs the sync loop in a worker thread; only that thread uses the connection then.
    con = sqlite3.connect(path, check_same_thread=False)
    con.executescript(SCHEMA)
    cols = {r[1] for r in con.execute("PRAGMA table_info(chars)")}
    if "inv" not in cols:  # databases created before holdings were synced
        con.execute("ALTER TABLE chars ADD COLUMN inv TEXT")
    return con


def _parse_lots(s):
    """'qty:price:tl[:verdict],...' -> [(qty, price, tl, verdict)]"""
    out = []
    if not s:
        return out
    for part in s.split(","):
        f = part.split(":")
        out.append((int(f[0]), int(f[1]), int(f[2]), VERDICTS.get(f[3]) if len(f) > 3 else None))
    return out


def import_scan(con, entry):
    """One outbox entry. Returns the scan time, or None if it was already stored."""
    ah, t = entry["ah"], int(entry["t"])
    cur = con.execute(
        "INSERT OR IGNORE INTO scans (ah, t, full, rows) VALUES (?, ?, ?, ?)",
        (ah, t, 1 if entry.get("full") else 0, entry.get("rows")),
    )
    if cur.rowcount == 0:
        return None
    scan_id = cur.lastrowid
    events, prices = [], []
    items = entry.get("items") or {}
    if isinstance(items, list):  # keys happened to be 1..n
        items = dict(enumerate(items, 1))
    for item_id, e in items.items():
        item_id = int(item_id)
        for qty, price, tl, _ in _parse_lots(e.get("a")):
            events.append((scan_id, item_id, "a", qty, price, tl, None, None))
        for qty, price, tl, verdict in _parse_lots(e.get("d")):
            events.append((scan_id, item_id, "d", qty, price, tl, verdict, None))
        if e.get("r"):
            for part in e["r"].split(","):
                price, q_from, q_to = (int(x) for x in part.split(":"))
                events.append((scan_id, item_id, "r", q_from, price, None, None, q_to))
        if e.get("s"):
            price, qty, mn = (int(x) for x in e["s"].split(":"))
            prices.append((scan_id, item_id, price or None, qty, mn or None))
    con.executemany("INSERT INTO lot_events VALUES (?, ?, ?, ?, ?, ?, ?, ?)", events)
    con.executemany("INSERT OR REPLACE INTO item_prices VALUES (?, ?, ?, ?, ?)", prices)
    return t


def import_ledger(con, ops):
    rows = [
        (op["id"], op.get("t", 0), op.get("kind", "?"), op.get("char"), op.get("itemID"), op.get("name"),
         op.get("qty"), op.get("amount"), op.get("profit"), op.get("note"))
        for op in ops if "id" in op
    ]
    con.executemany("INSERT OR IGNORE INTO ledger VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)", rows)
    return max((r[0] for r in rows), default=None)


INVENTORY = ("bags", "bank", "mail", "auctions", "mailMoney")


def import_chars(con, chars):
    for name, c in (chars or {}).items():
        inv = json.dumps({k: c.get(k) for k in INVENTORY if c.get(k) is not None}, default=str)
        con.execute(
            "INSERT INTO chars (name, money, t, faction, inv) VALUES (?, ?, ?, ?, ?) ON CONFLICT(name) DO UPDATE SET "
            "money = excluded.money, t = excluded.t, faction = excluded.faction, inv = excluded.inv "
            "WHERE excluded.t >= chars.t",
            (name, c.get("money"), c.get("t"), c.get("faction"), inv),
        )


def import_clients(con, clients):
    for name, c in (clients or {}).items():
        con.execute(
            "INSERT OR REPLACE INTO clients VALUES (?, ?, ?, ?)",
            (name, c.get("orders"), c.get("sum"), c.get("last")),
        )


def save_capital(con, day, t, c):
    con.execute(
        "INSERT OR REPLACE INTO capital VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
        (day, t, c["gold"], c["bags"], c["bank"], c["mail"], c["auctions"], c["total"]),
    )
    con.commit()


def import_errors(con, errors, key_hash):
    """Returns the latest 'last' time among the imported errors."""
    latest = None
    for e in errors:
        h = key_hash(e.get("key") or e.get("msg", ""))
        con.execute(
            "INSERT INTO errors (key_hash, msg, stack, version, count, first, last) VALUES (?, ?, ?, ?, ?, ?, ?) "
            "ON CONFLICT(key_hash) DO UPDATE SET count = MAX(errors.count, excluded.count), "
            "last = MAX(errors.last, excluded.last), version = excluded.version",
            (h, e.get("msg"), e.get("stack"), e.get("version"), e.get("count", 1), e.get("first"), e.get("last")),
        )
        if e.get("last") is not None:
            latest = max(latest or 0, e["last"])
    return latest


def import_probe(con, probe):
    if not probe:
        return
    env = probe.get("env") or {}
    t = env.get("t") or 0
    con.execute("INSERT OR REPLACE INTO probe VALUES (?, ?)", (t, json.dumps(probe, ensure_ascii=False, default=str)))


def import_saved_variables(con, data, key_hash):
    """data: parsed BaryshDB. Returns the ack for the addon: what is now stored."""
    ack = {}
    latest_scan = None
    for entry in as_list(data.get("outbox")):
        import_scan(con, entry)
        latest_scan = max(latest_scan or 0, int(entry["t"]))
    if latest_scan is not None:
        ack["scans"] = latest_scan
    ledger = data.get("ledger") or {}
    last_id = import_ledger(con, as_list(ledger.get("ops")))
    if last_id is not None:
        ack["ledger"] = last_id
    import_chars(con, data.get("chars"))
    import_clients(con, data.get("clients"))
    requests = as_list(data.get("exportRequests"))
    if requests:
        ack["exports"] = max(int(r.get("t") or 0) for r in requests)
    last_err = import_errors(con, as_list(data.get("errors")), key_hash)
    if last_err is not None:
        ack["errors"] = last_err
    import_probe(con, data.get("probe"))
    con.commit()
    return ack


def get_meta(con, k, default=None):
    row = con.execute("SELECT v FROM meta WHERE k = ?", (k,)).fetchone()
    return json.loads(row[0]) if row else default


def set_meta(con, k, v):
    con.execute("INSERT OR REPLACE INTO meta VALUES (?, ?)", (k, json.dumps(v)))
    con.commit()
