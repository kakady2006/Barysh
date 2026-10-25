"""Market price and sales speed over the whole history. Mirrors Barysh/Logic/Pricing.lua."""

DAY = 24 * 60 * 60
WINDOW_DAYS = 7
RECENT_DAYS = 3
RECENT_WEIGHT = 2
CAUTION_PERCENTILE = {"normal": 0.5, "careful": 0.35, "bold": 0.65}


def weighted_percentile(items, p):
    """items: [(value, weight)]. Smallest value whose cumulative weight reaches p of the total."""
    items = sorted((v, w) for v, w in items if w > 0)
    total = sum(w for _, w in items)
    if total == 0:
        return None
    target = total * p
    acc = 0
    for v, w in items:
        acc += w
        if acc >= target:
            return v
    return items[-1][0]


def market_price(scans, now, caution="normal"):
    """scans: [(time, price)] -> copper or None (same rule as the addon)."""
    items = []
    for t, price in scans:
        age = now - t
        if 0 <= age <= WINDOW_DAYS * DAY and price:
            items.append((price, RECENT_WEIGHT if age <= RECENT_DAYS * DAY else 1))
    v = weighted_percentile(items, CAUTION_PERCENTILE[caution])
    return None if v is None else int(v + 0.5)


def prices_at_scans(changes, scan_times):
    """changes: [(t, price, qty)] sorted by t; scan_times sorted.
    Returns [(scan_time, price)] for scans where the item was on the market."""
    out = []
    j = -1
    for st in scan_times:
        while j + 1 < len(changes) and changes[j + 1][0] <= st:
            j += 1
        if j >= 0:
            _, price, qty = changes[j]
            if qty and price:
                out.append((st, price))
    return out


def per_day(sold, now, window_days, first_seen):
    """sold: [(t, units)]. Units per day over the window, divided by days actually watched (>= 1)."""
    from_t = now - window_days * DAY
    total = sum(u for t, u in sold if from_t < t <= now)
    observed = window_days
    if first_seen is not None:
        observed = min(window_days, (now - first_seen) / DAY)
    return total / max(1.0, observed)
