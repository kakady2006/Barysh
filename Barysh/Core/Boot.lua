local ADDON, ns = ...

local boot = {}

ns.RegisterEvent(boot, "ADDON_LOADED", function(_, _, name)
    if name ~= ADDON then return end
    ns.UnregisterEvent(boot, "ADDON_LOADED")
    ns.InitDB()
    ns.FlushPendingErrors()
end)

ns.RegisterEvent(boot, "PLAYER_LOGIN", function()
    ns.UnregisterEvent(boot, "PLAYER_LOGIN")
    ns.ApplyModuleSettings()
    ns.Print(ns.L.LOADED:format(ns.version))
end)
