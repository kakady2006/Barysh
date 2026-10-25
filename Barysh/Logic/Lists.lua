local _, ns = ...

-- Item lists: quick scan, stock, do not buy, disenchant exclusions, own lists. TZ: "Списки товаров".
-- list = { items = { [itemID] = { src = "manual" | "import", t = added, buyBelow =, cap =, note = } } }
-- buyBelow/cap (copper) and note matter for the stock list; other lists ignore them.
local Lists = {}
ns.Lists = Lists

Lists.BUILTIN = { "quick", "stock", "noBuy", "noDisenchant" }
Lists.FIELDS = { "buyBelow", "cap", "note" }

function Lists.New()
    return { items = {} }
end

function Lists.Has(list, itemID)
    return list ~= nil and list.items[itemID] ~= nil
end

-- Adds or updates an entry. Returns true if it was new.
function Lists.Add(list, itemID, fields, src, t)
    local e = list.items[itemID]
    local new = e == nil
    if new then
        e = { src = src or "manual", t = t }
        list.items[itemID] = e
    elseif src then
        e.src = src
    end
    if fields then
        for _, f in ipairs(Lists.FIELDS) do
            if fields[f] ~= nil then e[f] = fields[f] end
        end
    end
    return new
end

function Lists.Remove(list, itemID)
    local had = list.items[itemID] ~= nil
    list.items[itemID] = nil
    return had
end

function Lists.Ids(list)
    local ids = {}
    for id in pairs(list.items) do ids[#ids + 1] = id end
    table.sort(ids)
    return ids
end

function Lists.Count(list)
    local n = 0
    for _ in pairs(list.items) do n = n + 1 end
    return n
end

-- What goes into an export string: only item IDs and their parameters.
function Lists.Export(list)
    local items = {}
    for id, e in pairs(list.items) do
        local x = {}
        for _, f in ipairs(Lists.FIELDS) do x[f] = e[f] end
        items[id] = x
    end
    return { items = items }
end

local function sameFields(e, x)
    for _, f in ipairs(Lists.FIELDS) do
        if e[f] ~= x[f] then return false end
    end
    return true
end

-- Difference between the list and an imported payload, shown before applying.
-- Removal touches only entries that came from an earlier import: manual entries stay.
function Lists.Diff(list, payload)
    local d = { add = {}, remove = {}, change = {} }
    local incoming = payload.items or {}
    for id, x in pairs(incoming) do
        local e = list.items[id]
        if not e then
            d.add[#d.add + 1] = id
        elseif not sameFields(e, x) then
            d.change[#d.change + 1] = id
        end
    end
    for id, e in pairs(list.items) do
        if incoming[id] == nil and e.src == "import" then d.remove[#d.remove + 1] = id end
    end
    table.sort(d.add)
    table.sort(d.remove)
    table.sort(d.change)
    return d
end

function Lists.Apply(list, payload, t)
    local d = Lists.Diff(list, payload)
    for _, id in ipairs(d.remove) do list.items[id] = nil end
    for id, x in pairs(payload.items or {}) do
        local e = list.items[id]
        if e then
            for _, f in ipairs(Lists.FIELDS) do e[f] = x[f] end
            e.src = "import"
        else
            Lists.Add(list, id, x, "import", t)
        end
    end
    return d
end

-- Settings import: flat differences {path, old, new} between two plain tables.
local function flatten(t, prefix, out)
    for k, v in pairs(t) do
        local path = prefix and (prefix .. "." .. tostring(k)) or tostring(k)
        if type(v) == "table" then
            flatten(v, path, out)
        else
            out[path] = v
        end
    end
    return out
end

function Lists.SettingsDiff(current, incoming)
    local a, b = flatten(current, nil, {}), flatten(incoming, nil, {})
    local out = {}
    for path, v in pairs(b) do
        if a[path] ~= v then out[#out + 1] = { path = path, old = a[path], new = v } end
    end
    for path, v in pairs(a) do
        if b[path] == nil then out[#out + 1] = { path = path, old = v } end
    end
    table.sort(out, function(x, y) return x.path < y.path end)
    return out
end

-- Converts the old quick list format (a plain array of IDs) and the old map format ({[id] = true}).
function Lists.Migrate(old)
    if type(old) ~= "table" then return Lists.New() end
    if type(old.items) == "table" then return old end
    local list = Lists.New()
    for k, v in pairs(old) do
        if type(k) == "number" and type(v) == "number" then
            Lists.Add(list, v, nil, "manual")
        elseif type(k) == "number" and v == true then
            Lists.Add(list, k, nil, "manual")
        end
    end
    return list
end
