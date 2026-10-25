"""Every interface string used in code exists in both languages."""

import re

from conftest import ADDON_DIR

STATIC = re.compile(r"(?<![\w.])L\.([A-Za-z_][A-Za-z0-9_]*)")

# Keys built at run time: prefix -> suffixes.
FAMILIES = {
    "ACT_": ["all", "auction", "disenchant", "vendor", "craft", "service", "trade"],
    "BUY_FAIL_": ["timeout", "price", "unavailable", "failed", "closed"],
    "COD_": ["good", "bad"],
    "DEAL_": ["all", "easy", "disenchant", "resale", "stock", "craft", "arbitrage"],
    "DEALTIP_": ["all", "easy", "disenchant", "resale", "stock", "craft", "arbitrage"],
    "DUR_": ["short", "long"],
    "GROUP_": ["CORE", "TRADE", "CRAFT", "MONEY", "SERVICE"],
    "IMPORT_ERR_": ["format", "version", "compressed", "data"],
    "KIND_": ["ah_sell", "ah_buy", "ah_expired", "disenchant", "vendor_sell", "vendor_buy", "craft", "cod",
              "trade_sell", "trade_buy", "service"],
    "LIST_": ["quick", "stock", "noBuy", "noDisenchant"],
    "MAILKIND_": ["sold", "won", "expired", "cancelled", "outbid"],
    "MAIL_STOP_": ["timeout", "full", "closed"],
    "MODULE_": ["Scan", "Tooltip", "Deals", "Selling", "Stock", "Vendor", "Market", "Neutral", "Mail", "Ledger",
                "Disenchanter", "Recipes", "Trade", "Sync", "Lists", "ImportExport", "Inventory"],
    "MODTIP_": ["Tooltip", "Deals", "Selling", "Stock", "Vendor", "Market", "Neutral", "Mail", "Ledger",
                "Disenchanter", "Recipes", "Trade", "Sync"],
    "PERIOD_": ["today", "week", "month", "all", "day", "7d", "30d"],
    "POST_FAIL_": ["closed", "empty", "missing"],
    "SCAN_FAIL_": ["closed", "busy", "cooldown", "noapi", "error", "empty"],
    "SRC_": ["manual", "import"],
    "TRADEKIND_": ["service", "craft", "trade_sell", "trade_buy", "reagents_in", "ignore"],
    "TRADE_PAY_": ["ok", "less", "more"],
    "USE_": ["ah", "disenchant", "vendor"],
    "VENDOR_": ["junk", "easy", "better"],
}


def keys(addon, lang):
    return set(addon.ns.locales[lang].keys())


def test_languages_have_the_same_keys(addon):
    assert keys(addon, "ruRU") == keys(addon, "enUS")


def test_static_keys_exist(addon):
    en = keys(addon, "enUS")
    missing = set()
    for path in ADDON_DIR.rglob("*.lua"):
        if "Locales" in path.parts or path.name == "Locale.lua":
            continue
        for key in STATIC.findall(path.read_text(encoding="utf-8")):
            if key not in en:
                missing.add(f"{path.name}: {key}")
    assert not missing, sorted(missing)


def test_dynamic_key_families_exist(addon):
    en = keys(addon, "enUS")
    missing = [p + s for p, suffixes in FAMILIES.items() for s in suffixes if p + s not in en]
    assert not missing


def test_every_module_has_a_name(addon):
    en = keys(addon, "enUS")
    names = [addon.ns.moduleOrder[i] for i in range(1, len(addon.ns.moduleOrder) + 1)]
    assert [n for n in names if "MODULE_" + n not in en] == []
