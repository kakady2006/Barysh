"""Statistics over the database for the addon's Market.lua."""

from collections import defaultdict

from . import pricing

DAY = pricing.DAY


def houses(con):
    return [r[0] for r in con.execute("SELECT DISTINCT ah FROM scans")]


def market_stats(con, ah, now, window_days=pricing.WINDOW_DAYS):
    """{item_id: (market price, sold per day, scans seen)} for one auction house."""
    from_t = now - window_days * DAY
    scan_times = [t for (t,) in con.execute(
        "SELECT t FROM scans WHERE ah = ? AND full = 1 AND t >= ? AND t <= ? ORDER BY t", (ah, from_t, now))]
    first_seen = scan_times[0] if scan_times else None

    changes = defaultdict(list)
    # Change points up to now; the last one before the window is the baseline.
    for item_id, t, price, qty in con.execute(
            "SELECT p.item_id, s.t, p.price, p.qty FROM item_prices p JOIN scans s ON s.id = p.scan_id "
            "WHERE s.ah = ? AND s.t <= ? ORDER BY s.t", (ah, now)):
        changes[item_id].append((t, price, qty))

    sold = defaultdict(list)
    for item_id, t, kind, qty, qty_to, verdict in con.execute(
            "SELECT e.item_id, s.t, e.kind, e.qty, e.qty_to, e.verdict FROM lot_events e "
            "JOIN scans s ON s.id = e.scan_id WHERE s.ah = ? AND s.t > ? AND s.t <= ?", (ah, from_t, now)):
        if kind == "d" and verdict == "sold":
            sold[item_id].append((t, qty))
        elif kind == "r":
            sold[item_id].append((t, qty - (qty_to or 0)))

    out = {}
    for item_id in set(changes) | set(sold):
        at_scans = pricing.prices_at_scans(changes.get(item_id, []), scan_times)
        price = pricing.market_price(at_scans, now)
        per_day = pricing.per_day(sold.get(item_id, []), now, window_days, first_seen)
        if price is None and per_day == 0:
            continue
        out[item_id] = (price, round(per_day, 2), len(at_scans))
    return out


SERIES_DAYS = 30
SERIES_MIN_DAYS = 3


def daily_series(con, ah, now, days=SERIES_DAYS):
    """{item_id: (prices, sales)} for the Market tab's 30-day view, oldest day first.
    prices: median scan price per day ("" if the item was not seen), sales: units sold per day.
    Only items seen on at least SERIES_MIN_DAYS days."""
    today = now // DAY
    first_day = today - days + 1
    from_t = first_day * DAY
    scan_times = [t for (t,) in con.execute(
        "SELECT t FROM scans WHERE ah = ? AND full = 1 AND t >= ? AND t <= ? ORDER BY t", (ah, from_t, now))]
    changes = defaultdict(list)
    for item_id, t, price, qty in con.execute(
            "SELECT p.item_id, s.t, p.price, p.qty FROM item_prices p JOIN scans s ON s.id = p.scan_id "
            "WHERE s.ah = ? AND s.t <= ? ORDER BY s.t", (ah, now)):
        changes[item_id].append((t, price, qty))
    sold = defaultdict(lambda: defaultdict(int))
    for item_id, t, kind, qty, qty_to, verdict in con.execute(
            "SELECT e.item_id, s.t, e.kind, e.qty, e.qty_to, e.verdict FROM lot_events e "
            "JOIN scans s ON s.id = e.scan_id WHERE s.ah = ? AND s.t >= ? AND s.t <= ?", (ah, from_t, now)):
        if kind == "d" and verdict == "sold":
            sold[item_id][t // DAY] += qty
        elif kind == "r":
            sold[item_id][t // DAY] += qty - (qty_to or 0)

    out = {}
    for item_id, ch in changes.items():
        by_day = defaultdict(list)
        for t, price in pricing.prices_at_scans(ch, scan_times):
            by_day[t // DAY].append(price)
        if len(by_day) < SERIES_MIN_DAYS:
            continue
        prices, sales = [], []
        for d in range(first_day, today + 1):
            p = by_day.get(d)
            prices.append(str(int(_median(p))) if p else "")
            sales.append(str(sold[item_id].get(d, 0)))
        out[item_id] = (",".join(prices), ",".join(sales))
    return out


def _median(values):
    s = sorted(values)
    n = len(s)
    return s[n // 2] if n % 2 else (s[n // 2 - 1] + s[n // 2]) / 2


def item_value(houses, item_id, cut=0.05):
    """Unit value after the cut from the house with the most data, or None."""
    best = None
    for ah, items in houses.items():
        e = items.get(item_id)
        if e and e[0]:
            if best is None or e[2] > best[1]:
                best = (int(e[0] * (1 - (0.15 if ah.endswith("|Neutral") else cut))), e[2])
    return best[0] if best else None


PLACES = ("bags", "bank", "mail", "auctions")


def _counts(place):
    if isinstance(place, list):  # keys happened to be 1..n
        return {i + 1: n for i, n in enumerate(place)}
    return place or {}


def capital(chars, houses):
    """Same composition as the addon's overview: gold, bags, bank, mail, auctions, total."""
    c = {"gold": 0, "bags": 0, "bank": 0, "mail": 0, "auctions": 0}
    for ch in (chars or {}).values():
        c["gold"] += int(ch.get("money") or 0) + int(ch.get("mailMoney") or 0)
        for place in PLACES:
            for item_id, n in _counts(ch.get(place)).items():
                v = item_value(houses, int(item_id))
                if v:
                    c[place] += v * int(n)
    c["total"] = sum(c.values())
    return c
