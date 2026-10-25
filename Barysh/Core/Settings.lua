local _, ns = ...

local COPPER_PER_SILVER = 100
local COPPER_PER_GOLD = 10000

-- Defaults from TZ "Главные настройки по умолчанию". Money in copper.
ns.defaults = {
    language = "ruRU",
    modules = {}, -- module name -> true/false; missing means the module's own default
    scan = {
        onButton = true,
        onOpen = false,
        every15 = true,
        quick = true,
    },
    deals = {
        minProfit = 1 * COPPER_PER_SILVER,
        maxDaysToSell = 0, -- 0 = no limit
        caution = "normal", -- normal | careful (35th percentile) | bold (65th percentile)
        soundFrom = 5 * COPPER_PER_GOLD,
        popup = false,
    },
    summaryDays = 7,
    staleHours = 24,
    disenchant = {
        quality = "green", -- green | greenblue
    },
}

local function copyDefaults(src, dst)
    for k, v in pairs(src) do
        if type(v) == "table" then
            if type(dst[k]) ~= "table" then dst[k] = {} end
            copyDefaults(v, dst[k])
        elseif dst[k] == nil then
            dst[k] = v
        end
    end
    return dst
end

-- Called on ADDON_LOADED. Profile mode is stored per character:
-- "account" uses BaryshDB.profile, "char" uses BaryshCharDB.profile.
function ns.InitDB()
    BaryshDB = BaryshDB or {}
    BaryshCharDB = BaryshCharDB or {}
    local db, cdb = BaryshDB, BaryshCharDB
    db.schema = db.schema or 1
    db.profile = copyDefaults(ns.defaults, db.profile or {})
    cdb.profileMode = cdb.profileMode or "account"
    if cdb.profileMode == "char" then
        cdb.profile = copyDefaults(ns.defaults, cdb.profile or {})
    end
    ns.db, ns.cdb = db, cdb
    ns.settings = cdb.profileMode == "char" and cdb.profile or db.profile
    ns.lang = ns.settings.language
end

function ns.SetProfileMode(mode)
    assert(mode == "account" or mode == "char", "unknown profile mode")
    ns.cdb.profileMode = mode
    if mode == "char" and not ns.cdb.profile then
        -- A new character profile starts as a copy of the account profile.
        ns.cdb.profile = copyDefaults(ns.db.profile, {})
    end
    ns.settings = mode == "char" and ns.cdb.profile or ns.db.profile
    ns.lang = ns.settings.language
end

function ns.ResetSettingsGroup(key)
    local def = ns.defaults[key]
    if type(def) == "table" then
        ns.settings[key] = copyDefaults(def, {})
    else
        ns.settings[key] = def
    end
end
