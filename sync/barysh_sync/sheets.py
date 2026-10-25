"""Google Sheet with the ledger: new operations, capital by day, stock, income by activity.
TZ: "Google Таблица". Uses a service account (sync/config.toml: google_key_file, spreadsheet_id);
the spreadsheet must be shared with the service account's e-mail. Client names never go here."""

import datetime
import json
import time
import urllib.parse
import urllib.request

from . import stats

API = "https://sheets.googleapis.com/v4/spreadsheets/"

OPS, CAPITAL, STOCK, ACTIVITY = "Операции", "Капитал по дням", "Склад", "Доход по занятиям"

HEADERS = {
    OPS: ["Время", "Тип", "Персонаж", "Предмет", "Кол-во", "Сумма, з", "Прибыль, з", "Примечание"],
    CAPITAL: ["День", "Всего, з", "Золото, з", "Сумки, з", "Банки, з", "Почта, з", "Выставлено, з"],
    STOCK: ["Предмет", "Кол-во", "Себестоимость шт., з", "Цена шт., з", "Вложено, з", "Стоит, з", "Прибыль, з",
            "Продаж в день", "Зачем"],
    ACTIVITY: ["Неделя с", "Аукцион, з", "Распыл, з", "Торговец, з", "Крафт, з", "Услуги, з", "Обмен, з", "Всего, з"],
}

KIND_NAMES = {
    "ah_sell": "Продажа", "ah_buy": "Покупка", "ah_expired": "Вернулось", "disenchant": "Распыл",
    "vendor_sell": "Торговцу", "vendor_buy": "У торговца", "craft": "Крафт", "cod": "Наложенный",
    "trade_sell": "Обмен: продажа", "trade_buy": "Обмен: покупка", "service": "Услуга",
}

ACTIVITY_OF = {
    "ah_sell": "auction", "ah_buy": "auction", "ah_expired": "auction", "disenchant": "disenchant",
    "vendor_sell": "vendor", "vendor_buy": "vendor", "craft": "craft", "service": "service",
    "cod": "trade", "trade_sell": "trade", "trade_buy": "trade",
}
ACTIVITIES = ["auction", "disenchant", "vendor", "craft", "service", "trade"]


def gold(copper):
    return round((copper or 0) / 10000, 4)


def http_json(method, url, token, body=None, timeout=30):
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(url, data=data, method=method,
                                 headers={"Authorization": f"Bearer {token}", "Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=timeout) as r:
        raw = r.read().decode()
    return json.loads(raw) if raw else {}


class Sheets:
    def __init__(self, spreadsheet_id, auth, request=http_json):
        self.id = spreadsheet_id
        self.auth = auth
        self.request = request

    def _call(self, method, path, body=None, params=None):
        url = API + self.id + path
        if params:
            url += "?" + urllib.parse.urlencode(params)
        return self.request(method, url, self.auth.access_token(), body)

    @staticmethod
    def _range(title, cells="A1"):
        return urllib.parse.quote(f"'{title}'!{cells}", safe="")

    def titles(self):
        res = self._call("GET", "", params={"fields": "sheets.properties.title"})
        return [s["properties"]["title"] for s in res.get("sheets", [])]

    def ensure(self):
        """Creates missing sheets with their header rows."""
        have = set(self.titles())
        missing = [t for t in HEADERS if t not in have]
        if missing:
            self._call("POST", ":batchUpdate", {"requests": [{"addSheet": {"properties": {"title": t}}} for t in missing]})
            for t in missing:
                self.replace(t, [])

    def append(self, title, rows):
        if rows:
            self._call("POST", f"/values/{self._range(title)}:append", {"values": rows},
                       {"valueInputOption": "USER_ENTERED", "insertDataOption": "INSERT_ROWS"})

    def replace(self, title, rows):
        """Header + rows, everything else on the sheet cleared."""
        self._call("POST", f"/values/{self._range(title, 'A:Z')}:clear", {})
        self._call("PUT", f"/values/{self._range(title)}", {"values": [HEADERS[title]] + rows},
                   {"valueInputOption": "USER_ENTERED"})


def _date(t):
    return datetime.datetime.fromtimestamp(t).strftime("%Y-%m-%d %H:%M")


def ops_rows(con, after_id):
    rows, last = [], after_id
    for op_id, t, kind, char, item_id, name, qty, amount, profit, note in con.execute(
            "SELECT id, t, kind, char, item_id, name, qty, amount, profit, note FROM ledger WHERE id > ? ORDER BY id",
            (after_id,)):
        rows.append([_date(t), KIND_NAMES.get(kind, kind), (char or "").split("-", 1)[0], name or (item_id or ""),
                     qty or "", gold(amount), gold(profit), note or ""])
        last = op_id
    return rows, last


def capital_rows(con):
    return [[day, gold(total), gold(g), gold(b), gold(bk), gold(m), gold(a)] for day, total, g, b, bk, m, a in
            con.execute("SELECT day, total, gold, bags, bank, mail, auctions FROM capital ORDER BY day")]


def _held(chars, item_id):
    n = 0
    for ch in (chars or {}).values():
        for place in stats.PLACES:
            counts = stats._counts(ch.get(place))
            n += int(counts.get(item_id) or counts.get(str(item_id)) or 0)
    return n


def stock_rows(data, houses, names=None):
    """Stock list positions, as on the addon's Stock tab."""
    profile = data.get("profile") or {}
    items = ((profile.get("lists") or {}).get("stock") or {}).get("items") or {}
    if isinstance(items, list):
        items = {i + 1: e for i, e in enumerate(items)}
    books = data.get("books") or {}
    rows = []
    for item_id, entry in sorted(items.items()):
        item_id = int(item_id)
        qty = _held(data.get("chars"), item_id)
        book = books.get(item_id) or {}
        avg = book["c"] / book["q"] if book.get("q") else None
        value = stats.item_value(houses, item_id)
        per_day = None
        for h in houses.values():
            if item_id in h:
                per_day = h[item_id][1]
        invested = round(avg * qty) if avg else 0
        worth = value * qty if value else None
        rows.append([
            (names or {}).get(item_id, item_id), qty, gold(avg), gold(value), gold(invested),
            gold(worth) if worth is not None else "", gold(worth - invested) if worth is not None and avg else "",
            per_day if per_day is not None else "", (entry or {}).get("note") or "",
        ])
    return rows


def activity_rows(con, weeks=12, now=None):
    now = now or time.time()
    today = datetime.date.fromtimestamp(now)
    monday = today - datetime.timedelta(days=today.weekday())
    rows = []
    for w in range(weeks - 1, -1, -1):
        start = monday - datetime.timedelta(weeks=w)
        t0 = time.mktime(start.timetuple())
        t1 = t0 + 7 * 86400
        sums = dict.fromkeys(ACTIVITIES, 0)
        for kind, profit in con.execute("SELECT kind, profit FROM ledger WHERE t >= ? AND t < ?", (t0, t1)):
            a = ACTIVITY_OF.get(kind)
            if a:
                sums[a] += profit or 0
        rows.append([start.isoformat()] + [gold(sums[a]) for a in ACTIVITIES] + [gold(sum(sums.values()))])
    return rows


def push(con, sheets, data, houses, get_meta, set_meta, now=None):
    """Sends everything new. Returns the number of operation rows appended."""
    sheets.ensure()
    after = int(get_meta(con, "sheets_ledger", 0) or 0)
    rows, last = ops_rows(con, after)
    sheets.append(OPS, rows)
    if last != after:
        set_meta(con, "sheets_ledger", last)
    sheets.replace(CAPITAL, capital_rows(con))
    sheets.replace(STOCK, stock_rows(data, houses))
    sheets.replace(ACTIVITY, activity_rows(con, now=now))
    return len(rows)

