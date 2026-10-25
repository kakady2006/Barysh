"""The "Export for analysis" button of the Market tab: a JSON file with price history, volumes and lot events
that can be sent to Claude. The addon only asks (BaryshDB.exportRequests); the file is built here."""

import json
import time
from pathlib import Path

from .luadata import as_list

TOP_ITEMS = 200  # an empty request means "the most active items"


def _top_items(con, ah, limit=TOP_ITEMS):
    rows = con.execute(
        "SELECT e.item_id, COUNT(*) n FROM lot_events e JOIN scans s ON s.id = e.scan_id "
        "WHERE s.ah = ? GROUP BY e.item_id ORDER BY n DESC LIMIT ?", (ah, limit))
    return [r[0] for r in rows]


def item_export(con, ah, item_id):
    prices = [
        {"t": t, "price": p, "qty": q, "min": m}
        for t, p, q, m in con.execute(
            "SELECT s.t, p.price, p.qty, p.min FROM item_prices p JOIN scans s ON s.id = p.scan_id "
            "WHERE s.ah = ? AND p.item_id = ? ORDER BY s.t", (ah, item_id))
    ]
    events = [
        {"t": t, "kind": k, "qty": q, "price": p, "tl": tl, "verdict": v, "qty_to": qt}
        for t, k, q, p, tl, v, qt in con.execute(
            "SELECT s.t, e.kind, e.qty, e.price, e.tl, e.verdict, e.qty_to FROM lot_events e "
            "JOIN scans s ON s.id = e.scan_id WHERE s.ah = ? AND e.item_id = ? ORDER BY s.t", (ah, item_id))
    ]
    return {"item_id": item_id, "prices": prices, "lot_events": events}


def build(con, request, out_dir, stats_by_house=None, now=None):
    """Writes one export file. Returns its path."""
    ah = request.get("ah")
    items = [int(i) for i in as_list(request.get("items"))] or _top_items(con, ah)
    scans = [{"t": t, "full": bool(f), "rows": r} for t, f, r in
             con.execute("SELECT t, full, rows FROM scans WHERE ah = ? ORDER BY t", (ah,))]
    stats = (stats_by_house or {}).get(ah, {})
    data = {
        "generated": int(now or time.time()),
        "auction_house": ah.split("|", 1)[-1] if ah else None,  # realm stays out of the file
        "note": "Barysh export: prices in copper; lot_events: a = appeared, d = vanished "
                "(verdict sold/unknown/expired), r = stack reduced (qty -> qty_to); tl = time-left band 0..3.",
        "scans": scans,
        "items": [dict(item_export(con, ah, i), **({"market": dict(zip(("price", "per_day", "scans"), stats[i]))}
                                                   if i in stats else {})) for i in items],
    }
    out_dir = Path(out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    stamp = time.strftime("%Y%m%d-%H%M%S", time.localtime(int(request.get("t") or data["generated"])))
    path = out_dir / f"barysh-export-{stamp}.json"
    path.write_text(json.dumps(data, ensure_ascii=False, indent=1), encoding="utf-8")
    return path
