local _, ns = ...

local Lists, Items = ns.Lists, ns.Items

-- Item lists in settings: quick scan, stock, do not buy, disenchant exclusions, own lists.
-- TZ: "Списки товаров". Data lives in the settings profile (ns.settings.lists).
ns:NewModule("Lists", { group = "service", canDisable = false })
local IL = {}
ns.ItemLists = IL

function IL.Get(name)
    local lists = ns.settings.lists
    if name ~= "custom" and lists[name] then return lists[name] end
    return lists.custom[name]
end

function IL.IsBuiltin(name)
    for _, n in ipairs(Lists.BUILTIN) do
        if n == name then return true end
    end
    return false
end

-- Built-in lists first, then own lists by name.
function IL.Names()
    local out = {}
    for _, n in ipairs(Lists.BUILTIN) do out[#out + 1] = n end
    local custom = {}
    for n in pairs(ns.settings.lists.custom) do custom[#custom + 1] = n end
    table.sort(custom)
    for _, n in ipairs(custom) do out[#out + 1] = n end
    return out
end

function IL.Title(name)
    if IL.IsBuiltin(name) then return ns.L["LIST_" .. name] end
    return name
end

function IL.Create(name)
    name = (name or ""):gsub("^%s+", ""):gsub("%s+$", ""):gsub("!", "")
    if name == "" or name == "custom" or IL.Get(name) then return nil end
    ns.settings.lists.custom[name] = Lists.New()
    return name
end

function IL.Delete(name)
    if IL.IsBuiltin(name) then return false end
    ns.settings.lists.custom[name] = nil
    return true
end

-- Accepts a link (Shift+click), an item ID or an exact name the client knows.
function IL.ParseItem(text)
    if type(text) == "number" then return text end
    text = tostring(text or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if text == "" then return nil end
    return Items.ID(tonumber(text) or text)
end

function IL.Add(name, item, fields)
    local list = IL.Get(name)
    local id = IL.ParseItem(item)
    if not list or not id then return nil end
    Lists.Add(list, id, fields, "manual", ns.Now())
    if ns.Prices then ns.Prices.Invalidate() end
    return id
end

function IL.Remove(name, itemID)
    local list = IL.Get(name)
    local had = list and Lists.Remove(list, itemID)
    if ns.Prices then ns.Prices.Invalidate() end
    return had
end

function IL.Ids(name)
    local list = IL.Get(name)
    return list and Lists.Ids(list) or {}
end

function IL.Has(name, itemID)
    return Lists.Has(IL.Get(name), itemID)
end

function IL.Entry(name, itemID)
    local list = IL.Get(name)
    return list and list.items[itemID]
end
