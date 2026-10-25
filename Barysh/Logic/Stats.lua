local _, ns = ...

local Stats = {}
ns.Stats = Stats

local function sortedCopy(list)
    local t = {}
    for i = 1, #list do t[i] = list[i] end
    table.sort(t)
    return t
end

-- Median of a list of numbers; nil for an empty list. Even count -> mean of the two middle values.
function Stats.Median(list)
    local n = #list
    if n == 0 then return nil end
    local t = sortedCopy(list)
    if n % 2 == 1 then
        return t[(n + 1) / 2]
    end
    return (t[n / 2] + t[n / 2 + 1]) / 2
end

-- Percentile p in [0, 1] with linear interpolation between closest ranks.
function Stats.Percentile(list, p)
    local n = #list
    if n == 0 then return nil end
    local t = sortedCopy(list)
    local pos = 1 + (n - 1) * p
    local lo = math.floor(pos)
    local hi = math.min(lo + 1, n)
    return t[lo] + (t[hi] - t[lo]) * (pos - lo)
end

-- Weighted percentile: items = { {value=, weight=}, ... }.
-- Returns the smallest value whose cumulative weight reaches p of the total weight.
function Stats.WeightedPercentile(items, p)
    local total = 0
    local t = {}
    for i, it in ipairs(items) do
        if it.weight > 0 then
            t[#t + 1] = it
            total = total + it.weight
        end
    end
    if total == 0 then return nil end
    table.sort(t, function(a, b) return a.value < b.value end)
    local target = total * p
    local acc = 0
    for _, it in ipairs(t) do
        acc = acc + it.weight
        if acc >= target then return it.value end
    end
    return t[#t].value
end
