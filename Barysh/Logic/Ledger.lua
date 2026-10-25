local _, ns = ...

-- Ledger of money and item movements. ledger = { nextId = n, ops = { op, ... } }
-- op = { id, t, kind, char, itemID, name, qty, amount (copper, + in / - out), profit, note }
local Ledger = {}
ns.Ledger = Ledger

Ledger.KINDS = {
    "ah_sell", "ah_buy", "ah_expired", "disenchant", "vendor_sell", "vendor_buy",
    "craft", "cod", "trade_sell", "trade_buy", "service",
}

function Ledger.New()
    return { nextId = 1, ops = {} }
end

function Ledger.Add(ledger, op)
    op.id = ledger.nextId
    ledger.nextId = ledger.nextId + 1
    ledger.ops[#ledger.ops + 1] = op
    return op
end

-- Totals for ops with from <= t < to, optionally only some kinds ({ [kind] = true }).
function Ledger.Sum(ledger, from, to, kinds)
    local s = { income = 0, expense = 0, profit = 0, count = 0 }
    for _, op in ipairs(ledger.ops) do
        if op.t >= from and op.t < to and (not kinds or kinds[op.kind]) then
            s.count = s.count + 1
            local a = op.amount or 0
            if a >= 0 then s.income = s.income + a else s.expense = s.expense - a end
            s.profit = s.profit + (op.profit or 0)
        end
    end
    return s
end

-- Ops with id > afterId, for BaryshSync.
function Ledger.Since(ledger, afterId)
    local out = {}
    for _, op in ipairs(ledger.ops) do
        if op.id > afterId then out[#out + 1] = op end
    end
    return out
end

-- Drops ops already stored by BaryshSync (id <= ackId) and older than keepFrom.
function Ledger.Trim(ledger, ackId, keepFrom)
    local kept = {}
    for _, op in ipairs(ledger.ops) do
        if op.id > ackId or op.t >= keepFrom then kept[#kept + 1] = op end
    end
    ledger.ops = kept
end
