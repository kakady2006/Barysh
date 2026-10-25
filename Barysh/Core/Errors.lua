local _, ns = ...

local MAX_ERRORS = 50
local pending = {} -- errors raised before SavedVariables are loaded

local function traceback(msg)
    local stack = debugstack and debugstack(2) or debug.traceback("", 2)
    return { msg = tostring(msg), stack = stack }
end

local function store(err)
    local db = BaryshDB
    if not db then
        pending[#pending + 1] = err
        return
    end
    db.errors = db.errors or {}
    local key = err.msg .. "\n" .. (err.stack:match("[^\n]+") or "")
    local now = time and time() or 0
    for _, e in ipairs(db.errors) do
        if e.key == key then
            e.count = e.count + 1
            e.last = now
            return
        end
    end
    if #db.errors >= MAX_ERRORS then
        table.remove(db.errors, 1)
    end
    db.errors[#db.errors + 1] = {
        key = key, msg = err.msg, stack = err.stack, version = ns.version,
        count = 1, first = now, last = now,
    }
end

-- Called once SavedVariables are available.
function ns.FlushPendingErrors()
    local list = pending
    pending = {}
    for _, err in ipairs(list) do
        store(err)
    end
end

function ns.ReportError(msg)
    store({ msg = tostring(msg), stack = debugstack and debugstack(2) or debug.traceback("", 2) })
end

-- Runs fn(...) and records any error instead of letting it reach the game's error frame.
function ns.Safe(fn, ...)
    local n, args = select("#", ...), { ... }
    local results = { xpcall(function() return fn(unpack(args, 1, n)) end, traceback) }
    if not results[1] then
        store(results[2])
        return false
    end
    return unpack(results)
end
