local _, ns = ...
local L = ns.L

local function say(msg)
    print("|cffe6b422Barysh|r " .. msg)
end
ns.Print = say

local commands = {}

function commands.modules()
    say(L.MODULES)
    for _, name in ipairs(ns.moduleOrder) do
        local m = ns.modules[name]
        say(("  %s: %s"):format(L["MODULE_" .. name], m.enabled and L.ON or L.OFF))
    end
end

function commands.errors()
    say(L.ERRORS_COUNT:format(ns.db.errors and #ns.db.errors or 0))
end

function commands.profile(arg)
    if arg == "account" or arg == "char" then
        ns.SetProfileMode(arg)
        ns.ApplyModuleSettings()
    end
    local mode = ns.cdb.profileMode
    say(L.PROFILE_SET:format(mode == "char" and L.PROFILE_CHAR or L.PROFILE_ACCOUNT))
end

SLASH_BARYSH1 = "/barysh"
SlashCmdList.BARYSH = function(input)
    local cmd, arg = (input or ""):match("^%s*(%S*)%s*(.-)%s*$")
    local fn = commands[cmd:lower()]
    if fn then
        ns.Safe(fn, arg)
    else
        say(L.HELP)
    end
end
