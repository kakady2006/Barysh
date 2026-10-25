-- Minimal imitation of the WoW client globals the addon uses.
-- Add only functions that really exist in the Forever API.

local Mock = { frames = {}, printed = {}, clock = 0, now = 1793000000 }
WowMock = Mock

local Frame = {}
Frame.__index = Frame

function Frame:RegisterEvent(event) self.events[event] = true end
function Frame:UnregisterEvent(event) self.events[event] = nil end
function Frame:IsEventRegistered(event) return self.events[event] == true end
function Frame:SetScript(name, fn) self.scripts[name] = fn end
function Frame:GetScript(name) return self.scripts[name] end

function CreateFrame(frameType, name)
    local f = setmetatable({ frameType = frameType, events = {}, scripts = {} }, Frame)
    Mock.frames[#Mock.frames + 1] = f
    if name then _G[name] = f end
    return f
end

-- Fire an event on every frame registered for it, like the client does.
function Mock.FireEvent(event, ...)
    for _, f in ipairs(Mock.frames) do
        local handler = f.scripts.OnEvent
        if f.events[event] and handler then handler(f, event, ...) end
    end
end

-- Run OnUpdate scripts for n frames, advancing the clock by `ms` each frame.
function Mock.RunFrames(n, ms)
    for _ = 1, n do
        Mock.clock = Mock.clock + (ms or 16)
        for _, f in ipairs(Mock.frames) do
            local handler = f.scripts.OnUpdate
            if handler then handler(f, (ms or 16) / 1000) end
        end
    end
end

function debugprofilestop() return Mock.clock end
function GetTime() return Mock.clock / 1000 end
function time() return Mock.now end
function GetLocale() return "ruRU" end
function debugstack(level) return debug.traceback("", (level or 1) + 1) end

function print(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[i] = tostring(select(i, ...)) end
    Mock.printed[#Mock.printed + 1] = table.concat(parts, " ")
end

SlashCmdList = {}

C_AddOns = {
    GetAddOnMetadata = function(_, field)
        if field == "Version" then return "test" end
    end,
}
