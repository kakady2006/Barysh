local _, ns = ...

local Ledger = ns.Ledger

-- Ledger of all money and item movements, capital per character. TZ: "Учёт и капитал".
-- Character holdings are kept by Modules/Inventory.lua.
local M = ns:NewModule("Ledger", { group = "money" })
ns.LedgerModule = M

-- Activities for "income by activity": ledger kind -> group.
M.ACTIVITY = {
    ah_sell = "auction", ah_buy = "auction", ah_expired = "auction",
    disenchant = "disenchant",
    vendor_sell = "vendor", vendor_buy = "vendor",
    craft = "craft", service = "service",
    cod = "trade", trade_sell = "trade", trade_buy = "trade",
}
M.ACTIVITIES = { "auction", "disenchant", "vendor", "craft", "service", "trade" }

-- Records an operation; a disabled ledger records nothing.
-- op = { kind, itemID, name, qty, amount, profit, note }
function ns.Record(op)
    if not M.enabled then return nil end
    op.t = op.t or ns.Now()
    op.char = op.char or ns.CharKey()
    local rec = Ledger.Add(ns.db.ledger, op)
    if ns.UI and ns.UI.Refresh then ns.UI.Refresh() end
    return rec
end

-- Start of today / week / month in local time; "all" = 0.
function M.PeriodStart(period, now)
    now = now or ns.Now()
    if period == "all" then return 0 end
    local d = date("*t", now)
    d.hour, d.min, d.sec = 0, 0, 0
    if period == "week" then
        -- weeks start on Monday
        local wday = (d.wday + 5) % 7
        return time(d) - wday * 86400
    elseif period == "month" then
        d.day = 1
    end
    return time(d)
end

function M.Totals(period, kinds)
    return Ledger.Sum(ns.db.ledger, M.PeriodStart(period), math.huge, kinds)
end

-- Profit by activity: { auction = copper, ... }
function M.ByActivity(from)
    local out = {}
    for _, a in ipairs(M.ACTIVITIES) do out[a] = 0 end
    for _, op in ipairs(ns.db.ledger.ops) do
        local a = M.ACTIVITY[op.kind]
        if a and op.t >= from then out[a] = out[a] + (op.profit or 0) end
    end
    return out
end

-- Profit per hour in game over the period, or nil without play time.
function M.PerHour(period)
    local from = M.PeriodStart(period)
    local sec = ns.Inventory.PlaySeconds(from, math.huge)
    if sec < 600 then return nil end
    return M.Totals(period).profit / (sec / 3600)
end

-- Kinds of one activity, for the ledger filter.
function M.KindsOf(activity)
    if not activity then return nil end
    local kinds = {}
    for kind, a in pairs(M.ACTIVITY) do
        if a == activity then kinds[kind] = true end
    end
    return kinds
end

function M.TotalGold()
    local sum = 0
    for _, c in pairs(ns.db.chars) do sum = sum + (c.money or 0) end
    return sum
end

-- Ledger rows as CSV for the export window (the addon cannot write files).
function M.CSV(from, kinds)
    local lines = { "time;kind;char;item;qty;amount;profit;note" }
    for _, op in ipairs(ns.db.ledger.ops) do
        if op.t >= from and (not kinds or kinds[op.kind]) then
            local name = op.name or (op.itemID and ns.Items.Name(op.itemID)) or ""
            lines[#lines + 1] = table.concat({
                date("%Y-%m-%d %H:%M", op.t), op.kind, (op.char or ""):match("^[^-]*") or "", (name:gsub(";", ",")),
                tostring(op.qty or ""), tostring(op.amount or 0), tostring(op.profit or 0), ((op.note or ""):gsub(";", ",")),
            }, ";")
        end
    end
    return table.concat(lines, "\n")
end
