local _, ns = ...

-- Spreads heavy work over frames so the game does not stutter.
-- A job is a function step() that does a small piece of work and returns true when finished.
local Jobs = {}
ns.Jobs = Jobs

Jobs.budgetMs = 8

local queue = {}
local frame = CreateFrame("Frame")

local function finish(job, ok)
    for i, j in ipairs(queue) do
        if j == job then
            table.remove(queue, i)
            break
        end
    end
    if job.onDone then ns.Safe(job.onDone, ok) end
end

local function tick()
    local deadline = debugprofilestop() + Jobs.budgetMs
    while queue[1] and debugprofilestop() < deadline do
        local job = queue[1]
        local ok, done = ns.Safe(job.step)
        if not ok then
            finish(job, false)
        elseif done then
            finish(job, true)
        end
    end
    if not queue[1] then
        frame:SetScript("OnUpdate", nil)
    end
end

-- Returns a handle that can be passed to Jobs.Cancel.
function Jobs.Run(name, step, onDone)
    local job = { name = name, step = step, onDone = onDone }
    queue[#queue + 1] = job
    frame:SetScript("OnUpdate", tick)
    return job
end

function Jobs.Cancel(job)
    for i, j in ipairs(queue) do
        if j == job then
            table.remove(queue, i)
            return true
        end
    end
    return false
end

function Jobs.Pending()
    return #queue
end
