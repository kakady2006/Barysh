local _, ns = ...

local Serialize, Lists = ns.Serialize, ns.Lists

-- Import and export strings: !BARYSH:<version>!<name>!<data>. TZ: "Импорт и экспорт строкой".
-- Before applying, the addon shows what will be added, removed and changed.
ns:NewModule("ImportExport", { group = "service", canDisable = false })
local IE = {}
ns.ImportExport = IE

local DEFLATE = 0 -- Enum.CompressionMethod.Deflate

-- VERIFY: C_EncodingUtil on Forever (listed for 1.60.1 on warcraft.wiki.gg). Without it: plain strings.
local function compressor()
    local E = C_EncodingUtil
    if E and E.CompressString then
        return function(s)
            local ok, z = pcall(E.CompressString, s, DEFLATE)
            return ok and z or nil
        end
    end
end

local function decompressor()
    local E = C_EncodingUtil
    if E and E.DecompressString then
        return function(z)
            local ok, s = pcall(E.DecompressString, z, DEFLATE)
            return ok and s or nil
        end
    end
end

function IE.ExportList(name)
    local list = ns.ItemLists.Get(name)
    if not list then return nil end
    local payload = Lists.Export(list)
    payload.kind = "list"
    payload.list = name
    return Serialize.Pack("list:" .. name, payload, compressor())
end

-- Settings as plain values; lists without per-entry bookkeeping (source, time).
local function exportable(profile)
    local out = {}
    for k, v in pairs(profile) do
        if k == "lists" then
            local lists = { custom = {} }
            for _, n in ipairs(Lists.BUILTIN) do lists[n] = Lists.Export(v[n]) end
            for n, l in pairs(v.custom) do lists.custom[n] = Lists.Export(l) end
            out.lists = lists
        elseif type(v) == "table" then
            out[k] = exportable(v)
        else
            out[k] = v
        end
    end
    return out
end

function IE.ExportSettings()
    return Serialize.Pack("settings", { kind = "settings", profile = exportable(ns.settings) }, compressor())
end

-- Reads a string. Returns preview or nil, error.
-- preview = { kind = "list", list, isNew, diff = { add, remove, change }, payload }
--         | { kind = "settings", changes = { {path, old, new} }, payload }
function IE.Preview(text)
    local name, payload = Serialize.Unpack(text, decompressor())
    if not name then return nil, payload end
    if payload.kind == "list" and type(payload.list) == "string" and type(payload.items) == "table" then
        local current = ns.ItemLists.Get(payload.list)
        return {
            kind = "list", list = payload.list, isNew = current == nil, payload = payload,
            diff = Lists.Diff(current or Lists.New(), payload),
        }
    elseif payload.kind == "settings" and type(payload.profile) == "table" then
        return { kind = "settings", changes = Lists.SettingsDiff(exportable(ns.settings), payload.profile), payload = payload }
    end
    return nil, "data"
end

-- Tables whose keys are free-form: taken from the string as a whole.
local OPEN = { modules = true, services = true }

-- Copies values only where the current settings have the same kind of value:
-- unknown keys and wrong types from a foreign string are ignored.
local function applyPlain(dst, src)
    for k, v in pairs(src) do
        local cur = dst[k]
        if k == "lists" then
            -- lists are merged separately
        elseif OPEN[k] and type(v) == "table" then
            dst[k] = v
        elseif type(v) == "table" and type(cur) == "table" then
            applyPlain(cur, v)
        elseif cur ~= nil and type(cur) == type(v) then
            dst[k] = v
        end
    end
end

function IE.Apply(preview)
    local now = ns.Now()
    if preview.kind == "list" then
        local name = preview.list
        if not ns.ItemLists.Get(name) then ns.ItemLists.Create(name) end
        local list = ns.ItemLists.Get(name)
        if not list then return false end
        Lists.Apply(list, preview.payload, now)
    else
        local p = preview.payload.profile
        applyPlain(ns.settings, p)
        if type(p.lists) == "table" then
            for _, n in ipairs(Lists.BUILTIN) do
                if type(p.lists[n]) == "table" then Lists.Apply(ns.settings.lists[n], p.lists[n], now) end
            end
            for n, l in pairs(type(p.lists.custom) == "table" and p.lists.custom or {}) do
                if type(l) == "table" then
                    if not ns.ItemLists.Get(n) then ns.ItemLists.Create(n) end
                    local list = ns.ItemLists.Get(n)
                    if list then Lists.Apply(list, l, now) end
                end
            end
        end
        ns.ApplyModuleSettings()
        if ns.UI and ns.UI.ModulesChanged then ns.UI.ModulesChanged() end
    end
    if ns.Prices then ns.Prices.Invalidate() end
    return true
end
