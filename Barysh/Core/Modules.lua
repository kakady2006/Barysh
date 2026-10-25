local _, ns = ...

ns.modules = {}
ns.moduleOrder = {}

ns.groups = { "core", "trade", "craft", "money", "service" }

local Module = {}
Module.__index = Module

function Module:RegisterEvent(event, fn)
    ns.RegisterEvent(self, event, fn)
end

function Module:UnregisterEvent(event)
    ns.UnregisterEvent(self, event)
end

-- spec: group (one of ns.groups), canDisable (default true), defaultEnabled (default true),
--       requires (list of module names this one depends on)
function ns:NewModule(name, spec)
    assert(not ns.modules[name], "module already exists: " .. name)
    spec = spec or {}
    local m = setmetatable({
        name = name,
        group = spec.group or "service",
        canDisable = spec.canDisable ~= false,
        defaultEnabled = spec.defaultEnabled ~= false,
        requires = spec.requires or {},
        enabled = false,
    }, Module)
    ns.modules[name] = m
    ns.moduleOrder[#ns.moduleOrder + 1] = name
    return m
end

function ns.IsModuleWanted(name)
    local m = ns.modules[name]
    if not m then return false end
    if not m.canDisable then return true end
    local flag = ns.settings and ns.settings.modules[name]
    if flag == nil then flag = m.defaultEnabled end
    if not flag then return false end
    for _, dep in ipairs(m.requires) do
        if not ns.IsModuleWanted(dep) then return false end
    end
    return true
end

function ns.IsModuleEnabled(name)
    local m = ns.modules[name]
    return m ~= nil and m.enabled
end

function ns.EnableModule(name)
    local m = ns.modules[name]
    if not m or m.enabled then return end
    m.enabled = true
    if m.OnEnable then ns.Safe(m.OnEnable, m) end
end

function ns.DisableModule(name)
    local m = ns.modules[name]
    if not m or not m.enabled or not m.canDisable then return end
    m.enabled = false
    if m.OnDisable then ns.Safe(m.OnDisable, m) end
    -- A disabled module keeps no subscriptions and no runtime data.
    ns.UnregisterAllEvents(m)
    m.data = nil
end

-- Brings every module in line with the current settings.
function ns.ApplyModuleSettings()
    for _, name in ipairs(ns.moduleOrder) do
        if ns.IsModuleWanted(name) then
            ns.EnableModule(name)
        else
            ns.DisableModule(name)
        end
    end
end

function ns.SetModuleEnabled(name, on)
    ns.settings.modules[name] = on and true or false
    ns.ApplyModuleSettings()
    if ns.UI and ns.UI.ModulesChanged then ns.UI.ModulesChanged() end
end
