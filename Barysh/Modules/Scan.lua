local ADDON, ns = ...

local AH, Lots, ScanDiff, History, Velocity, Pricing, Jobs =
    ns.AH, ns.Lots, ns.ScanDiff, ns.History, ns.Velocity, ns.Pricing, ns.Jobs
local L = ns.L

-- Full scan (4 modes), quick scan by list, saving only changes. TZ: "Ядро: скан, цены, подсказка".
local M = ns:NewModule("Scan", { group = "core", canDisable = false })
ns.Scan = M

-- Other modules (deals, alerts) react to every applied scan: fn({ key, full, items, changed, ids }).
M.listeners = {}
function M.OnApplied(fn)
    M.listeners[#M.listeners + 1] = fn
end

local DAY = 24 * 60 * 60
M.RESPONSE_TIMEOUT = 30     -- seconds to wait for REPLICATE_ITEM_LIST_UPDATE
M.ROWS_PER_STEP = 400       -- rows read per job step
M.ITEMS_PER_STEP = 200      -- items diffed per job step
M.MISSING_RETRIES = 3       -- re-reads of rows the client had not loaded yet
M.MISSING_DELAY = 1
M.SEARCH_TIMEOUT = 5
M.TIMER_PERIOD = 5          -- how often the 15-minute mode checks the cooldown

-- Saved data ----------------------------------------------------------------------------

-- Per auction house: scans = full scan times in the window, snap = itemID -> encoded lots,
-- hist = itemID -> price history, sales = itemID -> { [day] = units }.
function M.House(key)
    local all = ns.db.ah
    local h = all[key]
    if not h then
        h = { scans = {}, snap = {}, hist = {}, sales = {} }
        all[key] = h
    end
    return h
end

function M.CooldownLeft()
    local last = ns.db.lastReplicate
    if not last then return 0 end
    return math.max(0, last + ns.const.replicateCooldown - ns.Now())
end

local function probeLog(entry)
    local p = ns.db.probe
    p.scans = p.scans or {}
    table.insert(p.scans, entry)
    while #p.scans > 20 do table.remove(p.scans, 1) end
end

-- Applying a scan -----------------------------------------------------------------------

local function encodeRemoved(removed)
    local parts = {}
    for i, l in ipairs(removed) do
        parts[i] = l.qty .. ":" .. l.price .. ":" .. l.tl .. ":" .. l.verdict:sub(1, 1)
    end
    return table.concat(parts, ",")
end

local function encodeReduced(reduced)
    local parts = {}
    for i, r in ipairs(reduced) do
        parts[i] = r.price .. ":" .. r.from .. ":" .. r.to
    end
    return table.concat(parts, ",")
end

-- Compares one item with the saved snapshot and stores what changed.
-- ctx = { house, t, elapsed, outbox (or nil), baseline (true on the very first scan) }
function M.ApplyItem(ctx, itemID, newLots)
    local h = ctx.house
    local oldStr = h.snap[itemID]
    local newStr = Lots.Encode(newLots)
    if oldStr == newStr then return false end

    local d = ScanDiff.Diff(Lots.Decode(oldStr), newLots, ctx.elapsed)
    h.snap[itemID] = newStr ~= "" and newStr or nil

    local qty, min = Lots.Totals(newLots)
    local price = Pricing.ScanPrice(newLots)
    h.hist[itemID] = h.hist[itemID] or {}
    local priceChanged = History.Record(h.hist[itemID], ctx.t, price, qty, min)

    if not ctx.baseline and d.soldUnits > 0 then
        h.sales[itemID] = h.sales[itemID] or {}
        Velocity.Add(h.sales[itemID], ctx.t, d.soldUnits)
    end

    if ctx.outbox and (d.changed or priceChanged) then
        local e = {}
        if #d.added > 0 then e.a = Lots.Encode(d.added) end
        if #d.removed > 0 then e.d = encodeRemoved(d.removed) end
        if #d.reduced > 0 then e.r = encodeReduced(d.reduced) end
        if priceChanged then e.s = (price or 0) .. ":" .. qty .. ":" .. (min or 0) end
        ctx.outbox.items[itemID] = e
    end
    return d.changed
end

local function newOutbox(key, t, full, rows)
    if not ns.IsModuleWanted("Sync") then return nil end
    ns.db.outbox = ns.db.outbox or {}
    local e = { ah = key, t = t, full = full, rows = rows, items = {} }
    table.insert(ns.db.outbox, e)
    return e
end

local function pruneHouse(h, now)
    local days = ns.settings.summaryDays
    local cutoff = now - days * DAY
    local kept = {}
    for _, t in ipairs(h.scans) do
        if t >= cutoff then kept[#kept + 1] = t end
    end
    h.scans = kept
    for id, list in pairs(h.hist) do
        History.Prune(list, cutoff)
        local last = list[#list]
        if #list == 1 and last.q == 0 and last.t < cutoff then h.hist[id] = nil end
    end
    for id, days_ in pairs(h.sales) do
        Velocity.Prune(days_, now, days)
        if next(days_) == nil then h.sales[id] = nil end
    end
    h.pruned = now
end

-- byItem: itemID -> lots. full = true: items missing from byItem left the market.
-- Runs in frame-sized steps; onDone(stats) when finished.
function M.ApplyScan(key, t, byItem, full, rows, onDone)
    local h = M.House(key)
    local prevT = full and h.lastFull or h.lastAny
    local ctx = {
        house = h, t = t,
        elapsed = prevT and (t - prevT) or nil,
        baseline = h.lastFull == nil,
        outbox = newOutbox(key, t, full, rows),
    }
    local ids = {}
    for id in pairs(byItem) do ids[#ids + 1] = id end
    if full then
        for id in pairs(h.snap) do
            if not byItem[id] then
                ids[#ids + 1] = id
                byItem[id] = {}
            end
        end
    end

    local i, changed = 0, 0
    local function step()
        local stop = math.min(#ids, i + M.ITEMS_PER_STEP)
        for k = i + 1, stop do
            if M.ApplyItem(ctx, ids[k], byItem[ids[k]]) then changed = changed + 1 end
        end
        i = stop
        return i >= #ids
    end
    local function finish(ok)
        if not ok then return end
        if full then
            h.scans[#h.scans + 1] = t
            h.lastFull = t
            h.firstScan = h.firstScan or t
        end
        h.lastAny = t
        if not h.pruned or t - h.pruned > DAY / 4 then pruneHouse(h, t) end
        if ctx.outbox and next(ctx.outbox.items) == nil and not full then
            -- nothing to tell BaryshSync about
            for idx = #ns.db.outbox, 1, -1 do
                if ns.db.outbox[idx] == ctx.outbox then table.remove(ns.db.outbox, idx) end
            end
        end
        ns.Prices.Invalidate()
        local stats = { items = #ids, changed = changed, full = full, key = key, ids = ids }
        for _, fn in ipairs(M.listeners) do ns.Safe(fn, stats) end
        if onDone then onDone(stats) end
    end
    return Jobs.Run("apply", step, finish)
end

-- Full scan -------------------------------------------------------------------------------

M.state = "idle"

local function setState(s)
    M.state = s
    if ns.UI and ns.UI.Refresh then ns.UI.Refresh() end
end

local function fail(reason)
    local req = M.req
    M.req = nil
    if M.readJob then Jobs.Cancel(M.readJob); M.readJob = nil end
    setState("idle")
    if req then
        req.result = reason
        probeLog(req)
        if reason == "timeout" and req.trigger ~= "button" then
            -- No answer to a scan the addon started on its own: the client wants a click.
            ns.db.autoScanNeedsClick = true
        end
    end
end

-- trigger: "button" | "open" | "timer". Returns true or false, reason.
function M.StartFull(trigger)
    if not M.ahOpen then return false, "closed" end
    if M.state ~= "idle" then return false, "busy" end
    local left = M.CooldownLeft()
    if left > 0 then return false, "cooldown", left end
    if not AH.Available() then return false, "noapi" end

    local ok, err = AH.RequestReplicate()
    local req = { trigger = trigger, t = ns.Now(), started = GetTime(), key = AH.CurrentKey() }
    M.req = req
    if not ok then
        fail("error: " .. tostring(err))
        return false, "error"
    end
    setState("waiting")
    C_Timer.After(M.RESPONSE_TIMEOUT, function()
        if M.req == req and M.state == "waiting" then fail("timeout") end
    end)
    return true
end

local function readRows(req)
    local n = AH.NumReplicate()
    req.rows = n
    req.waited = GetTime() - req.started
    req.readStart = debugprofilestop()
    req.frames = 0
    local byItem, missing, bidOnly = {}, {}, 0
    local i = 0

    -- False if the client has not loaded the row yet (read again later).
    local function addRow(idx)
        local itemID, count, buyout, tl = AH.ReadReplicate(idx)
        if not itemID then return false end
        if buyout <= 0 then
            bidOnly = bidOnly + 1
            return true
        end
        local lots = byItem[itemID]
        if not lots then
            lots = {}
            byItem[itemID] = lots
        end
        lots[#lots + 1] = { qty = count, price = math.floor(buyout / count), tl = tl }
        return true
    end

    local function step()
        req.frames = req.frames + 1
        local stop = math.min(n, i + M.ROWS_PER_STEP)
        for idx = i, stop - 1 do
            if not addRow(idx) then missing[#missing + 1] = idx end
        end
        i = stop
        return i >= n
    end

    local retries = 0
    local function finishRead(ok)
        M.readJob = nil
        if not ok or M.req ~= req then return end
        if #missing > 0 and retries < M.MISSING_RETRIES then
            retries = retries + 1
            C_Timer.After(M.MISSING_DELAY, function()
                if M.req ~= req then return end
                local again = missing
                missing = {}
                for _, idx in ipairs(again) do
                    if not addRow(idx) then missing[#missing + 1] = idx end
                end
                finishRead(true)
            end)
            return
        end
        req.missing = #missing
        req.bidOnly = bidOnly
        req.readMs = debugprofilestop() - req.readStart
        setState("saving")
        M.ApplyScan(req.key, req.t, byItem, true, n, function(stats)
            req.items = stats.items
            req.changed = stats.changed
            req.total = GetTime() - req.started
            req.result = "ok"
            probeLog(req)
            M.req = nil
            M.lastResult = req
            setState("idle")
            ns.Print(L.SCAN_DONE:format(n, stats.changed))
        end)
    end

    M.readJob = Jobs.Run("replicate", step, finishRead)
end

function M:OnReplicateUpdate()
    local req = M.req
    if not req or M.state ~= "waiting" then return end
    ns.db.lastReplicate = req.t
    ns.db.autoScanNeedsClick = nil
    setState("reading")
    readRows(req)
end

-- Quick scan by list --------------------------------------------------------------------

function M.QuickList()
    return ns.ItemLists.Ids("quick")
end

function M.StartQuick(list)
    if not M.ahOpen then return false, "closed" end
    if M.state ~= "idle" then return false, "busy" end
    list = list or M.QuickList()
    if #list == 0 then return false, "empty" end
    M.quick = { queue = {}, pos = 0, byItem = {}, t = ns.Now(), key = AH.CurrentKey() }
    for i, id in ipairs(list) do M.quick.queue[i] = id end
    setState("quick")
    M.NextQuick()
    return true
end

function M.NextQuick()
    local q = M.quick
    if not q then return end
    q.pos = q.pos + 1
    local itemID = q.queue[q.pos]
    if not itemID then
        M.quick = nil
        setState("saving")
        M.ApplyScan(q.key, q.t, q.byItem, false, nil, function(stats)
            setState("idle")
            ns.Print(L.QUICK_DONE:format(#q.queue, stats.changed))
        end)
        return
    end
    if not AH.CanSearch() then
        q.pos = q.pos - 1
        C_Timer.After(0.2, M.NextQuick)
        return
    end
    q.current = itemID
    q.key_ = AH.Search(itemID)
    local pos = q.pos
    C_Timer.After(M.SEARCH_TIMEOUT, function()
        if M.quick == q and q.pos == pos and q.current == itemID then
            q.current = nil
            M.NextQuick()
        end
    end)
end

local function quickResult(itemID, lots)
    local q = M.quick
    if not q or q.current ~= itemID then return end
    q.current = nil
    q.byItem[itemID] = lots
    C_Timer.After(0.1, M.NextQuick)
end

function M:OnCommodityResults(_, itemID)
    ns.Items.SetCommodity(itemID, true)
    if M.quick and M.quick.current == itemID then
        quickResult(itemID, (AH.CommodityResults(itemID)))
    end
end

function M:OnItemResults(_, itemKey)
    local q = M.quick
    if itemKey and itemKey.itemID then ns.Items.SetCommodity(itemKey.itemID, false) end
    if q and itemKey and q.current == itemKey.itemID then
        quickResult(itemKey.itemID, (AH.ItemResults(itemKey)))
    end
end

-- Modes and events ----------------------------------------------------------------------

local function timerTick()
    if not M.ahOpen or M.state ~= "idle" or not ns.settings.scan.every15 then return end
    if M.CooldownLeft() > 0 then return end
    if ns.db.autoScanNeedsClick then
        -- The client does not allow scans without a click: remind with a sound once per cooldown.
        local last = ns.db.lastReplicate or 0
        if M.remindedFor ~= last then
            M.remindedFor = last
            PlaySound(SOUNDKIT.RAID_WARNING)
            ns.Print(L.SCAN_READY)
        end
        return
    end
    M.StartFull("timer")
end

function M:OnEnable()
    self:RegisterEvent("AUCTION_HOUSE_SHOW", function()
        M.ahOpen = true
        M.key = AH.CurrentKey()
        ns.cdb.lastHouse = M.key
        if ns.settings.scan.onOpen then M.StartFull("open") end
        M.ticker = C_Timer.NewTicker(M.TIMER_PERIOD, timerTick)
        if ns.UI and ns.UI.OnAuctionHouse then ns.UI.OnAuctionHouse(true) end
    end)
    self:RegisterEvent("AUCTION_HOUSE_CLOSED", function()
        M.ahOpen = false
        if M.ticker then M.ticker:Cancel(); M.ticker = nil end
        if M.state == "waiting" then fail("closed") end
        if M.quick then M.quick = nil; setState("idle") end
        if ns.UI and ns.UI.OnAuctionHouse then ns.UI.OnAuctionHouse(false) end
    end)
    self:RegisterEvent("REPLICATE_ITEM_LIST_UPDATE", M.OnReplicateUpdate)
    self:RegisterEvent("COMMODITY_SEARCH_RESULTS_UPDATED", M.OnCommodityResults)
    self:RegisterEvent("ITEM_SEARCH_RESULTS_UPDATED", M.OnItemResults)
    local function blocked(_, event, addon, func)
        if addon ~= ADDON then return end
        local p = ns.db.probe
        p.blocked = p.blocked or {}
        table.insert(p.blocked, { event = event, func = tostring(func), t = ns.Now() })
        while #p.blocked > 20 do table.remove(p.blocked, 1) end
        if tostring(func):find("ReplicateItems") then
            ns.db.autoScanNeedsClick = true
            if M.state == "waiting" then fail("blocked") end
        end
    end
    self:RegisterEvent("ADDON_ACTION_BLOCKED", blocked)
    self:RegisterEvent("ADDON_ACTION_FORBIDDEN", blocked)
end

-- Prices for other modules ----------------------------------------------------------------

local Prices = {}
ns.Prices = Prices
local cache = {}

function Prices.Invalidate()
    cache = {}
end

-- The house used when the player is not at an auction house: the last one visited.
function Prices.DefaultKey()
    return (M.ahOpen and M.key) or ns.cdb.lastHouse or AH.FactionKey()
end

local function synced(key, itemID)
    local m = ns.market and ns.market.ah and ns.market.ah[key]
    local e = m and m[itemID]
    if e then return { price = e[1], perDay = e[2], scans = e[3] } end
end

-- Summary of one item: market, current, min7, median7, perDay, scans, isNew, onMarket, synced.
function Prices.Item(itemID, key)
    key = key or Prices.DefaultKey()
    local ck = key .. "#" .. itemID
    local s = cache[ck]
    if s then return s end
    local h = ns.db.ah[key]
    local now = ns.Now()
    if h and h.hist[itemID] then
        s = History.Summary(h.hist[itemID], h.scans, now, ns.settings.deals.caution)
        local sales = h.sales[itemID]
        s.perDay = sales and Velocity.PerDay(sales, now, ns.settings.summaryDays, h.firstScan) or 0
    else
        s = { scans = 0, isNew = true, onMarket = 0, perDay = nil }
    end
    local sy = synced(key, itemID)
    if sy then
        s.synced = sy
        -- The PC database sees the whole history: trust it when it has more scans.
        if sy.price and (not s.market or (sy.scans or 0) > s.scans) then s.market = sy.price end
        if sy.perDay and (not s.perDay or (sy.scans or 0) > s.scans) then s.perDay = sy.perDay end
        if (sy.scans or 0) >= Pricing.NEW_ITEM_SCANS then s.isNew = false end
    end
    cache[ck] = s
    return s
end

-- Best single price estimate: market price, else the current scan price.
function Prices.Value(itemID, key)
    local s = Prices.Item(itemID, key)
    return s.market or s.current
end
