"""Writes Barysh/Data/Market.lua, which the addon reads on the next /reload."""

import os
import tempfile

from .luadata import dumps

HEADER = "-- Written by BaryshSync. Do not edit: the file is replaced after every save in game.\nlocal _, ns = ...\n\n"


def render(generated, ack, houses):
    """houses: {ah: {item_id: (price, per_day, scans)}}"""
    ah = {}
    for key, items in houses.items():
        ah[key] = {int(i): [p if p is not None else False, d, n] for i, (p, d, n) in sorted(items.items())}
    data = {"generated": int(generated), "ack": ack, "ah": ah}
    return HEADER + "ns.market = " + dumps(data) + "\n"


def write(path, text):
    """Atomic replace, so the game never reads a half-written file."""
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=path.parent, prefix=".market-", suffix=".tmp")
    with os.fdopen(fd, "w", encoding="utf-8", newline="\n") as f:
        f.write(text)
    os.replace(tmp, path)
