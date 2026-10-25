local _, ns = ...

local Lots = ns.Lots

-- Difference between two scans of one item (docs/decisions.md, points 3-4).
-- Lots match by "qty + price"; time left may only go down between scans.
local ScanDiff = {}
ns.ScanDiff = ScanDiff

ScanDiff.SOLD = "sold"
ScanDiff.UNKNOWN = "unknown"
ScanDiff.EXPIRED = "expired"

-- What a lot that vanished with this time-left band most likely was.
function ScanDiff.Verdict(tl)
    if tl >= Lots.TL_LONG then return ScanDiff.SOLD end
    if tl == Lots.TL_MEDIUM then return ScanDiff.UNKNOWN end
    return ScanDiff.EXPIRED
end

local function byTl(a, b) return a.tl < b.tl end

local function groupByKey(lots)
    local groups = {}
    for _, l in ipairs(lots) do
        local key = l.qty .. ":" .. l.price
        local g = groups[key]
        if not g then
            g = {}
            groups[key] = g
        end
        g[#g + 1] = l
    end
    return groups
end

-- Greedy matching of identical lots: each new lot takes the old lot with the smallest
-- time left that is still >= its own. Gives the maximum number of matches.
local function matchGroup(old, new, removed, added)
    table.sort(old, byTl)
    table.sort(new, byTl)
    local i = 1
    for _, n in ipairs(new) do
        while old[i] and old[i].tl < n.tl do
            removed[#removed + 1] = old[i]
            i = i + 1
        end
        if old[i] then
            i = i + 1
        else
            added[#added + 1] = n
        end
    end
    for j = i, #old do
        removed[#removed + 1] = old[j]
    end
end

-- A stack lot that shrank at the same price: part of it was bought.
local function findReductions(removed, added)
    local reduced = {}
    table.sort(added, function(a, b) return a.qty > b.qty end)
    local used = {}
    local keptAdded = {}
    for _, a in ipairs(added) do
        local hit
        for ri, r in ipairs(removed) do
            if not used[ri] and r.price == a.price and r.qty > a.qty and r.tl >= a.tl then
                hit = ri
                break
            end
        end
        if hit then
            used[hit] = true
            local r = removed[hit]
            reduced[#reduced + 1] = { price = r.price, from = r.qty, to = a.qty, tl = a.tl }
        else
            keptAdded[#keptAdded + 1] = a
        end
    end
    local keptRemoved = {}
    for ri, r in ipairs(removed) do
        if not used[ri] then keptRemoved[#keptRemoved + 1] = r end
    end
    return keptRemoved, keptAdded, reduced
end

-- old, new: lot lists of one item. Returns
-- { added = lots, removed = lots with .verdict, reduced = { {price, from, to, tl} },
--   soldUnits, soldValue, unknownUnits, expiredUnits, changed }
function ScanDiff.Diff(old, new)
    local removed, added = {}, {}
    local og, ng = groupByKey(old), groupByKey(new)
    for key, olds in pairs(og) do
        matchGroup(olds, ng[key] or {}, removed, added)
    end
    for key, news in pairs(ng) do
        if not og[key] then
            for _, n in ipairs(news) do added[#added + 1] = n end
        end
    end

    local reduced
    removed, added, reduced = findReductions(removed, added)

    local r = {
        added = Lots.Sort(added), removed = {}, reduced = reduced,
        soldUnits = 0, soldValue = 0, unknownUnits = 0, expiredUnits = 0,
    }
    for _, l in ipairs(Lots.Sort(removed)) do
        local v = ScanDiff.Verdict(l.tl)
        r.removed[#r.removed + 1] = { qty = l.qty, price = l.price, tl = l.tl, verdict = v }
        if v == ScanDiff.SOLD then
            r.soldUnits = r.soldUnits + l.qty
            r.soldValue = r.soldValue + l.qty * l.price
        elseif v == ScanDiff.UNKNOWN then
            r.unknownUnits = r.unknownUnits + l.qty
        else
            r.expiredUnits = r.expiredUnits + l.qty
        end
    end
    for _, d in ipairs(reduced) do
        local units = d.from - d.to
        r.soldUnits = r.soldUnits + units
        r.soldValue = r.soldValue + units * d.price
    end
    r.changed = #r.added > 0 or #r.removed > 0 or #r.reduced > 0
    return r
end
