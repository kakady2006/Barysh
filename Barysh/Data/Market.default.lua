-- Placeholder. BaryshSync overwrites Data\Market.lua with market statistics from the PC database.
-- tools\install.ps1 copies this file to Market.lua when it does not exist yet.
local _, ns = ...

ns.market = {
    generated = 0, -- unix time the file was written; 0 = never
    ack = {},      -- what BaryshSync has stored: scans = time, ledger = id, errors = time
    ah = {},       -- ["Realm|Horde"] = { [itemID] = { market price, sold per day, scans } }
    series = {},   -- ["Realm|Horde"] = { [itemID] = { "daily prices, 30 days", "daily sales" } }
}
