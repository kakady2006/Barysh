local _, ns = ...

ns.locales = {}
ns.lang = "ruRU" -- replaced from settings on load

function ns.RegisterLocale(code, strings)
    local t = ns.locales[code] or {}
    for k, v in pairs(strings) do
        t[k] = v
    end
    ns.locales[code] = t
end

-- L.KEY -> active language, then enUS, then the key itself.
ns.L = setmetatable({}, {
    __index = function(_, key)
        local active = ns.locales[ns.lang]
        local value = active and active[key]
        if value == nil then
            local base = ns.locales.enUS
            value = base and base[key]
        end
        return value or key
    end,
})
