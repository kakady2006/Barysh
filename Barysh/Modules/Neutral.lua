local _, ns = ...

-- Neutral auction house (Gadgetzan, Booty Bay, Everlook): its prices in tooltips and the Market tab,
-- arbitrage deals between it and the faction house. Off by default. TZ: "Нейтральный аукцион".
-- The house the player stands at is always scanned and stored separately, module on or off.
local M = ns:NewModule("Neutral", { group = "trade", defaultEnabled = false })
ns.Neutral = M

function M:OnEnable() end
