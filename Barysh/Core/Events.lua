local _, ns = ...

-- event -> { [owner] = handler }
local handlers = {}
local frame = CreateFrame("Frame")

frame:SetScript("OnEvent", function(_, event, ...)
    local list = handlers[event]
    if not list then return end
    for owner, fn in pairs(list) do
        ns.Safe(fn, owner, event, ...)
    end
end)

function ns.RegisterEvent(owner, event, fn)
    local list = handlers[event]
    if not list then
        list = {}
        handlers[event] = list
        frame:RegisterEvent(event)
    end
    list[owner] = fn
end

function ns.UnregisterEvent(owner, event)
    local list = handlers[event]
    if not list then return end
    list[owner] = nil
    if next(list) == nil then
        handlers[event] = nil
        frame:UnregisterEvent(event)
    end
end

function ns.UnregisterAllEvents(owner)
    for event in pairs(handlers) do
        ns.UnregisterEvent(owner, event)
    end
end

function ns.HasEventHandlers(owner)
    for _, list in pairs(handlers) do
        if list[owner] then return true end
    end
    return false
end
