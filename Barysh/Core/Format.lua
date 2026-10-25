local _, ns = ...

local GOLD, SILVER = 10000, 100

-- Money with coin icons from the client; plain text fallback.
function ns.FormatMoney(copper)
    if not copper then return "—" end
    copper = math.floor(copper + 0.5)
    local sign = copper < 0 and "-" or ""
    copper = math.abs(copper)
    local coins = (C_CurrencyInfo and C_CurrencyInfo.GetCoinTextureString) or GetCoinTextureString
    if coins then
        -- Round small details away on big sums: gold amounts drop copper.
        if copper >= 100 * GOLD then copper = copper - copper % SILVER end
        return sign .. coins(copper)
    end
    local g, s, c = math.floor(copper / GOLD), math.floor(copper % GOLD / SILVER), copper % SILVER
    if g > 0 then return ("%s%dз %02dс"):format(sign, g, s) end
    if s > 0 then return ("%s%dс %02dм"):format(sign, s, c) end
    return ("%s%dм"):format(sign, c)
end

-- "5 мин назад", "3 ч назад", "2 дн назад"
function ns.FormatAge(seconds)
    local L = ns.L
    if not seconds then return L.NEVER end
    if seconds < 90 then return L.AGO_NOW end
    if seconds < 3600 then return L.AGO_MIN:format(math.floor(seconds / 60)) end
    if seconds < 2 * 86400 then return L.AGO_HOURS:format(math.floor(seconds / 3600)) end
    return L.AGO_DAYS:format(math.floor(seconds / 86400))
end

function ns.FormatCountdown(seconds)
    seconds = math.max(0, math.floor(seconds))
    return ("%d:%02d"):format(math.floor(seconds / 60), seconds % 60)
end

function ns.Now()
    return (GetServerTime and GetServerTime()) or time()
end
