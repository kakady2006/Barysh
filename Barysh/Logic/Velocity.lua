local _, ns = ...

-- Estimated sales per day from vanished lots. Stored per item as { [day number] = units }.
local Velocity = {}
ns.Velocity = Velocity

local DAY = 24 * 60 * 60

function Velocity.Day(t)
    return math.floor(t / DAY)
end

function Velocity.Add(days, t, units)
    if units <= 0 then return end
    local d = Velocity.Day(t)
    days[d] = (days[d] or 0) + units
end

function Velocity.Prune(days, now, keepDays)
    local oldest = Velocity.Day(now) - keepDays + 1
    for d in pairs(days) do
        if d < oldest then days[d] = nil end
    end
end

-- Units per day over the last windowDays, divided by how long we have actually been watching
-- (firstSeen = time of the first scan in the window). At least one day.
function Velocity.PerDay(days, now, windowDays, firstSeen)
    local today = Velocity.Day(now)
    local total = 0
    for d, units in pairs(days) do
        if d > today - windowDays and d <= today then total = total + units end
    end
    local observed = windowDays
    if firstSeen then
        observed = math.min(windowDays, (now - firstSeen) / DAY)
    end
    return total / math.max(1, observed)
end
