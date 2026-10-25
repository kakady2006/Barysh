-- Placeholder. BaryshSync overwrites Data\Market.lua with market statistics from the PC database.
-- tools\install.ps1 copies this file to Market.lua when it does not exist yet.
local _, ns = ...

ns.market = {
    generated = 0, -- unix time the file was written; 0 = never
    items = {},
}
