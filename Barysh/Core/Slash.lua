local _, ns = ...
local L = ns.L

local function say(msg)
    print("|cffe6b422Barysh|r " .. msg)
end
ns.Print = say

local commands = {}

function commands.show()
    ns.UI.Toggle()
end

function commands.modules()
    say(L.MODULES)
    for _, name in ipairs(ns.moduleOrder) do
        local m = ns.modules[name]
        say(("  %s (%s): %s"):format(L["MODULE_" .. name], name, m.enabled and L.ON or L.OFF))
    end
end

-- /barysh module Deals off
function commands.module(arg)
    local name, state = arg:match("^(%S+)%s*(%S*)$")
    local m = name and ns.modules[name]
    if not m then return say(L.UNKNOWN_MODULE) end
    if state ~= "on" and state ~= "off" then state = m.enabled and "off" or "on" end
    ns.SetModuleEnabled(name, state == "on")
    commands.modules()
end

function commands.errors()
    say(L.ERRORS_COUNT:format(#ns.db.errors))
end

function commands.profile(arg)
    if arg == "account" or arg == "char" then
        ns.SetProfileMode(arg)
        ns.ApplyModuleSettings()
    end
    local mode = ns.cdb.profileMode
    say(L.PROFILE_SET:format(mode == "char" and L.PROFILE_CHAR or L.PROFILE_ACCOUNT))
end

function commands.scan()
    local ok, why, left = ns.Scan.StartFull("button")
    if not ok then
        say(why == "cooldown" and L.SCAN_FAIL_cooldown:format(ns.FormatCountdown(left)) or (L["SCAN_FAIL_" .. why] or why))
    end
end

function commands.quick()
    local ok, why = ns.Scan.StartQuick()
    if not ok then say(L["SCAN_FAIL_" .. why] or why) end
end

-- /barysh quickadd <shift-click an item | item ID | name>
function commands.quickadd(arg)
    if not ns.ItemLists.Add("quick", arg) then return say(L.ITEM_NOT_FOUND) end
    say(L.QUICK_LIST:format(#ns.ItemLists.Ids("quick")))
end

function commands.quickdel(arg)
    local id = ns.ItemLists.ParseItem(arg)
    if id then ns.ItemLists.Remove("quick", id) end
    say(L.QUICK_LIST:format(#ns.ItemLists.Ids("quick")))
end

function commands.probe()
    ns.Probe.Run()
end

function commands.de(arg)
    if arg == "show" or arg == "hide" then
        ns.Disenchanter.SetShown(arg == "show")
    else
        ns.Disenchanter.SetShown(not ns.settings.disenchant.shown)
    end
end

function commands.save()
    ReloadUI()
end

SLASH_BARYSH1 = "/barysh"
SlashCmdList.BARYSH = function(input)
    local cmd, arg = (input or ""):match("^%s*(%S*)%s*(.-)%s*$")
    local fn = commands[cmd:lower()]
    if fn then
        ns.Safe(fn, arg)
    elseif cmd == "" then
        ns.Safe(commands.show)
    else
        say(L.HELP)
    end
end
