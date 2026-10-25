local _, ns = ...

-- Recognises what a finished trade was. TZ: "Обмен", "Прайс услуг", "Клиенты".
local Trade = {}
ns.TradeLogic = Trade

-- trade = {
--   own = partner is a character of this account, guild = partner is in the guild,
--   gave = { items = { {itemID, qty}, ... }, money }, got = { items = ..., money },
--   enchant = name of the enchantment put on the partner's item in the "will not be traded" slot, or nil,
--   order = true when this client gave reagents earlier and has not received the craft yet,
--   crafted = { [itemID] = true } items the player crafted recently,
-- }
-- Returns { kind, auto, options, warn }:
--   kind: service | craft | trade_sell | trade_buy | reagents_in | transfer | money_in | unclear | ignore
--   auto: record without asking (a short message with "Fix" is shown)
--   options: answers for the "What was it?" window
--   warn: "stranger_gold" when gold came from someone outside the account and guild
function Trade.Classify(trade)
    local gaveItems, gotItems = #trade.gave.items > 0, #trade.got.items > 0
    local gaveMoney, gotMoney = (trade.gave.money or 0) > 0, (trade.got.money or 0) > 0
    if not gaveItems and not gotItems and not gaveMoney and not gotMoney and not trade.enchant then
        return { kind = "ignore", auto = true }
    end
    if trade.own then return { kind = "transfer", auto = true } end
    local stranger = not trade.guild

    if trade.enchant and gotMoney and not gaveItems then
        return { kind = "service", auto = true }
    end
    if gaveItems and gotMoney and not gotItems then
        if trade.order then return { kind = "craft", auto = true } end
        for _, it in ipairs(trade.gave.items) do
            if trade.crafted and trade.crafted[it.itemID] then
                return { kind = "unclear", auto = false, options = { "craft", "trade_sell", "ignore" } }
            end
        end
        return { kind = "trade_sell", auto = true }
    end
    if gotItems and gaveMoney and not gaveItems then
        return { kind = "trade_buy", auto = true }
    end
    if gotMoney and not gaveItems and not gotItems then
        return { kind = "money_in", auto = false, options = { "service", "trade_sell", "ignore" },
            warn = stranger and "stranger_gold" or nil }
    end
    if gotItems and not gaveItems and not gaveMoney and not gotMoney then
        -- A client hands over reagents for a future order.
        return { kind = "reagents_in", auto = true }
    end
    if gaveItems and gotItems then
        return { kind = "unclear", auto = false, options = { "trade_buy", "trade_sell", "ignore" } }
    end
    return { kind = "ignore", auto = true }
end

-- Reagents the player added: what the recipe needs minus what the client brought.
-- need, brought: { {itemID, qty}, ... }
function Trade.OwnReagents(need, brought)
    local have = {}
    for _, b in ipairs(brought or {}) do have[b.itemID] = (have[b.itemID] or 0) + b.qty end
    local out = {}
    for _, n in ipairs(need) do
        local left = n.qty - (have[n.itemID] or 0)
        if left > 0 then out[#out + 1] = { itemID = n.itemID, qty = left } end
        have[n.itemID] = math.max(0, (have[n.itemID] or 0) - n.qty)
    end
    return out
end

function Trade.Cost(items, valueOf)
    local sum = 0
    for _, it in ipairs(items) do sum = sum + (valueOf(it.itemID) or 0) * it.qty end
    return math.floor(sum + 0.5)
end

-- Service price list entry: { name, client = price with the client's reagents,
--   own = price with own reagents or nil ("auto": client price + market value of reagents),
--   reagents = { {itemID, qty}, ... } }
function Trade.ServicePrice(entry, ownReagents, valueOf)
    if not ownReagents then return entry.client end
    if entry.own then return entry.own end
    return (entry.client or 0) + Trade.Cost(entry.reagents or {}, valueOf)
end

-- Does the gold in the trade match the price list? Returns "ok" | "less" | "more", difference.
function Trade.CheckPayment(expected, paid)
    if not expected then return nil end
    local diff = paid - expected
    if diff == 0 then return "ok", 0 end
    return diff < 0 and "less" or "more", diff
end

-- Finds the price list entry for an enchantment shown in the trade window.
function Trade.FindService(priceList, enchantName)
    if not enchantName then return nil end
    for _, e in ipairs(priceList) do
        if e.name == enchantName then return e end
    end
    local lower = enchantName:lower()
    for _, e in ipairs(priceList) do
        if e.name and lower:find(e.name:lower(), 1, true) then return e end
    end
end

-- Client book: clients[name] = { orders, sum, last }. Names stay on this PC only.
Trade.REGULAR_ORDERS = 3

function Trade.AddOrder(clients, name, amount, t)
    local c = clients[name] or { orders = 0, sum = 0 }
    c.orders = c.orders + 1
    c.sum = c.sum + (amount or 0)
    c.last = t
    clients[name] = c
    return c
end

function Trade.IsRegular(clients, name)
    local c = clients[name]
    return c ~= nil and c.orders >= Trade.REGULAR_ORDERS
end
