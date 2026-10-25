local _, ns = ...

local TradeLogic, TradeAPI, CostBasis = ns.TradeLogic, ns.TradeAPI, ns.CostBasis
local L = ns.L

-- Trades: recognised and recorded after a successful trade; unclear ones ask "What was it?".
-- Service price list and clients. Client names stay in SavedVariables on this PC only.
-- TZ: "Обмен", "Прайс услуг", "Клиенты".
local M = ns:NewModule("Trade", { group = "craft" })
ns.TradeModule = M

local function valueOf(id)
    return CostBasis.Average(ns.db.books, id) or ns.Prices.Value(id) or 0
end

local function isOwn(name)
    if not name then return false end
    for key in pairs(ns.db.chars) do
        if (key:match("^[^-]+") or key) == name then return true end
    end
    return false
end

-- The trade as Logic/Trade.lua sees it.
function M.Describe(t)
    t.own = isOwn(t.partner)
    t.guild = TradeAPI.IsGuildMember(t.partner)
    t.order = ns.db.orders[t.partner or ""] ~= nil
    t.crafted = ns.RecipesModule and ns.RecipesModule.RecentlyCrafted() or {}
    return t
end

-- Expected price for the enchantment in the trade (price list), for the trade panel.
function M.Expected(t)
    local entry = TradeLogic.FindService(ns.settings.trade.services, t.enchant)
    if not entry then return nil end
    local ownReagents = not t.order
    return TradeLogic.ServicePrice(entry, ownReagents, valueOf), entry
end

-- Recording ---------------------------------------------------------------------------------

local function recipeFor(itemID)
    for _, byID in pairs(ns.db.recipes) do
        for _, r in pairs(byID) do
            if r.output == itemID then return r end
        end
    end
end

-- Applies a kind to a finished trade. Returns ledger ids and an undo function.
function M.Apply(t, kind)
    local ids, undo = {}, {}
    local function rec(op)
        local r = ns.Record(op)
        if r then ids[#ids + 1] = r.id end
    end
    local partner = t.partner
    if kind == "service" then
        local _, entry = M.Expected(t)
        local cost = 0
        if entry and not t.order then cost = TradeLogic.Cost(entry.reagents or {}, valueOf) end
        rec({ kind = "service", qty = 1, amount = t.got.money, profit = t.got.money - cost, note = t.enchant })
        TradeLogic.AddOrder(ns.db.clients, partner, t.got.money, ns.Now())
    elseif kind == "craft" then
        local brought = ns.db.orders[partner] or {}
        local cost, first = 0, t.gave.items[1]
        for _, it in ipairs(t.gave.items) do
            local r = recipeFor(it.itemID)
            if r then cost = cost + TradeLogic.Cost(TradeLogic.OwnReagents(r.reagents, brought), valueOf) end
        end
        rec({ kind = "craft", itemID = first and first.itemID, qty = first and first.qty, amount = t.got.money,
            profit = t.got.money - cost })
        ns.db.orders[partner] = nil
        TradeLogic.AddOrder(ns.db.clients, partner, t.got.money, ns.Now())
    elseif kind == "trade_sell" then
        local cost = 0
        for _, it in ipairs(t.gave.items) do
            local c = CostBasis.Remove(ns.db.books, it.itemID, it.qty)
            cost = cost + c
            undo[#undo + 1] = function() CostBasis.Add(ns.db.books, it.itemID, it.qty, c) end
        end
        local first = t.gave.items[1]
        rec({ kind = "trade_sell", itemID = first and first.itemID, qty = first and first.qty,
            amount = t.got.money, profit = t.got.money - cost })
    elseif kind == "trade_buy" then
        local total = 0
        for _, it in ipairs(t.got.items) do total = total + (ns.Prices.Value(it.itemID) or 1) * it.qty end
        for _, it in ipairs(t.got.items) do
            local share = math.floor(t.gave.money * (ns.Prices.Value(it.itemID) or 1) * it.qty / total + 0.5)
            CostBasis.Add(ns.db.books, it.itemID, it.qty, share)
            undo[#undo + 1] = function() CostBasis.Remove(ns.db.books, it.itemID, it.qty) end
        end
        local first = t.got.items[1]
        rec({ kind = "trade_buy", itemID = first and first.itemID, qty = first and first.qty,
            amount = -t.gave.money, profit = 0 })
    elseif kind == "reagents_in" then
        local o = ns.db.orders[partner] or {}
        for _, it in ipairs(t.got.items) do o[#o + 1] = { itemID = it.itemID, qty = it.qty } end
        ns.db.orders[partner] = o
    end
    return ids, function()
        for _, fn in ipairs(undo) do fn() end
        local kept = {}
        local drop = {}
        for _, id in ipairs(ids) do drop[id] = true end
        for _, op in ipairs(ns.db.ledger.ops) do
            if not drop[op.id] then kept[#kept + 1] = op end
        end
        ns.db.ledger.ops = kept
    end
end

-- After a trade --------------------------------------------------------------------------------

M.last = nil  -- { trade, kind, undo } for "Fix"

function M.Finish(t)
    t = M.Describe(t)
    local r = TradeLogic.Classify(t)
    if r.warn == "stranger_gold" then ns.Print(L.TRADE_STRANGER_GOLD) end
    if r.kind == "ignore" or r.kind == "transfer" then return r end
    if r.auto then
        local _, undo = M.Apply(t, r.kind)
        M.last = { trade = t, kind = r.kind, undo = undo }
        if ns.UI and ns.UI.TradeToast then ns.UI.TradeToast(t, r.kind) end
    elseif ns.settings.trade.ask and ns.UI and ns.UI.TradeAsk then
        ns.UI.TradeAsk(t, r.options)
    end
    return r
end

-- "Fix": undo the automatic record and ask.
function M.Fix()
    local last = M.last
    if not last then return end
    M.last = nil
    last.undo()
    if ns.UI and ns.UI.TradeAsk then
        ns.UI.TradeAsk(last.trade, { "craft", "service", "trade_sell", "trade_buy", "ignore" })
    end
end

function M.Answer(t, kind)
    if kind and kind ~= "ignore" then M.Apply(t, kind) end
end

function M.IsRegular(name)
    return TradeLogic.IsRegular(ns.db.clients, name)
end

local function snapshot()
    if not M.open then return end
    M.state = TradeAPI.Read()
    if ns.UI and ns.UI.TradePanel then ns.UI.TradePanel(M.Describe(M.state)) end
end

function M:OnEnable()
    self:RegisterEvent("TRADE_SHOW", function()
        M.open = true
        M.state = nil
        snapshot()
    end)
    for _, e in ipairs({ "TRADE_PLAYER_ITEM_CHANGED", "TRADE_TARGET_ITEM_CHANGED", "TRADE_MONEY_CHANGED",
        "TRADE_ACCEPT_UPDATE" }) do
        self:RegisterEvent(e, snapshot)
    end
    self:RegisterEvent("TRADE_CLOSED", function()
        M.open = false
        if ns.UI and ns.UI.TradePanel then ns.UI.TradePanel(nil) end
    end)
    self:RegisterEvent("UI_INFO_MESSAGE", function(_, _, _, message)
        if message == ERR_TRADE_COMPLETE and M.state then
            local t = M.state
            M.state = nil
            M.Finish(t)
        end
    end)
end

function M:OnDisable()
    M.open, M.state, M.last = false, nil, nil
end
