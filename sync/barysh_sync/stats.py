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
