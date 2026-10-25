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
        crashAlert = true, -- price fell 30%+ in 24 h on a big volume
        affordable = false, -- show only what the current gold can pay for
        types = { easy = true, disenchant = true, resale = true, stock = true, craft = true, arbitrage = true },
    },
    selling = {
        stack = 0,          -- 0 = one lot for commodities; 20 or 40 = stacks for crates
        expensive = 50 * COPPER_PER_GOLD, -- lots worth more go for 24 hours
        returned = true,    -- returned lots join the queue
    },
    vendor = {
        junk = true,        -- grey items
        easy = true,        -- bought as "easy money"
        better = true,      -- worth more to the vendor than on the auction house or disenchanted
    },
    mail = {
        strangerWarn = true,
    },
    trade = {
        services = {},      -- price list: { {name, client, own, reagents = { {itemID, qty} }} }
        ask = true,         -- the "What was it?" window for unclear trades
    },
    recipes = {
        shown = true,
    },
    market = {
        house = "current",  -- current | faction | neutral | both
    },
    summaryDays = 7,
    staleHours = 24,
    disenchant = {
        quality = "green", -- green | greenblue
        skipBetterToSell = true,
        key = "F",
        shown = true,
    },
    tooltip = {
        enabled = true,
    },
    -- Item lists (Logic/Lists.lua): { items = { [itemID] = { src, t, buyBelow, cap, note } } }
    lists = {
        quick = { items = {} },
        stock = { items = {} },
        noBuy = { items = {} },
        noDisenchant = { items = {} },
        custom = {},        -- name -> list
    },
    minimap = { angle = 200, hidden = false },
}

-- Account-wide data, not part of a profile.
local function initData(db)
    db.ah = db.ah or {}           -- per auction house: scans, snapshot, history, sales
    db.books = db.books or {}     -- cost basis per item
    db.ledger = db.ledger or { nextId = 1, ops = {} }
    db.chars = db.chars or {}     -- money and last login per character
    db.probe = db.probe or {}     -- facts about the client for docs/ingame-checklist.md
    db.errors = db.errors or {}
    db.posted = db.posted or {}       -- own posted lots: deposit is lost if they come back
    db.purchases = db.purchases or {} -- itemID -> deal type of the last purchase
    db.sellMarked = db.sellMarked or {} -- itemID -> true: put into the selling queue ("Exit", "To selling")
    db.stockBelow = db.stockBelow or {} -- itemID -> first day below cost
    db.playtime = db.playtime or {}   -- day -> seconds online
    db.clients = db.clients or {}     -- trade clients, local only
    db.orders = db.orders or {}       -- client name -> reagents handed over for a craft
    db.recipes = db.recipes or {}     -- character -> recipeID -> recipe (for raw materials deals)
    db.exportRequests = db.exportRequests or {} -- "Export for analysis" requests for BaryshSync
end

-- Lists saved before the { items = {} } format.
local function migrateLists(profile)
    local lists = profile and profile.lists
    if type(lists) ~= "table" then return end
    for _, name in ipairs(ns.Lists.BUILTIN) do
        if lists[name] ~= nil then lists[name] = ns.Lists.Migrate(lists[name]) end
    end
end

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
    initData(db)
    migrateLists(db.profile)
    migrateLists(cdb.profile)
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
