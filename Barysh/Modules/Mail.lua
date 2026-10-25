local _, ns = ...

local MailAPI, MailClassify, CostBasis, Items = ns.MailAPI, ns.MailClassify, ns.CostBasis, ns.Items
local L = ns.L

-- Auction house mail collection and mail review. TZ: "Почта".
-- The addon only takes auction house mail, and only after the player clicks the button.
local M = ns:NewModule("Mail", { group = "money" })
ns.Mail = M

M.STEP_DELAY = 0.15
M.STEP_TIMEOUT = 4

local patterns

function M.Patterns()
    patterns = patterns or MailClassify.BuildPatterns(MailAPI.SubjectFormats())
    return patterns
end

-- Inbox overview: { auction = { {index, kind, name, money, items}, ... }, other = { header, ... } }
function M.ReadInbox()
    local out = { auction = {}, other = {}, money = 0 }
    for i = 1, MailAPI.Count() do
        local h = MailAPI.Header(i)
        if h then
            local inv = MailAPI.Invoice(i)
            local kind, name = MailClassify.Classify(h.subject, inv and inv.type, M.Patterns())
            if kind and MailClassify.IsCollectable(kind) then
                out.auction[#out.auction + 1] = { index = i, kind = kind, name = name, header = h, invoice = inv }
                out.money = out.money + h.money
            elseif kind ~= MailClassify.PENDING then
                h.kind = M.OtherKind(h)
                out.other[#out.other + 1] = h
            end
        end
    end
    return out
end

-- Takes the oldest posted-lot record of an item (its deposit is known there).
local function takePosted(itemID, qty)
    for i, p in ipairs(ns.db.posted) do
        if p.itemID == itemID and (not qty or p.qty == qty) then
            return table.remove(ns.db.posted, i)
        end
    end
end

-- Ledger and cost basis for one auction mail, before taking it.
function M.RecordMail(mail)
    local h, inv = mail.header, mail.invoice
    local items = MailAPI.Items(mail.index)
    if mail.kind == MailClassify.SOLD then
        local itemID = Items.ID(inv and inv.itemName or mail.name)
        local qty = inv and inv.count or 1
        local cost = itemID and CostBasis.Remove(ns.db.books, itemID, qty) or 0
        local net = inv and (inv.buyout - inv.cut) or h.money
        if itemID then takePosted(itemID, qty) end
        ns.Record({
            kind = "ah_sell", itemID = itemID, name = mail.name, qty = qty, amount = h.money,
            profit = net - cost, note = inv and ("cut " .. inv.cut .. ", deposit " .. inv.deposit),
        })
    elseif mail.kind == MailClassify.WON then
        local paid = inv and math.max(inv.bid, inv.buyout) or 0
        local it = items[1]
        if it then
            local qty = 0
            for _, x in ipairs(items) do qty = qty + x.count end
            CostBasis.Add(ns.db.books, it.itemID, qty, paid)
            ns.Record({ kind = "ah_buy", itemID = it.itemID, name = it.name, qty = qty, amount = -paid, profit = 0 })
        end
    elseif mail.kind == MailClassify.EXPIRED or mail.kind == MailClassify.CANCELLED then
        for _, it in ipairs(items) do
            -- The deposit of a lot that comes back is lost.
            local posted = takePosted(it.itemID, it.count) or takePosted(it.itemID)
            local lost = posted and posted.deposit or 0
            ns.Record({ kind = "ah_expired", itemID = it.itemID, name = it.name, qty = it.count, amount = -lost, profit = -lost })
            -- Comes back into the selling queue with a "returned" mark.
            ns.db.returned = ns.db.returned or {}
            ns.db.returned[it.itemID] = (ns.db.returned[it.itemID] or 0) + it.count
        end
    end
end

-- Other mail: never taken automatically, only shown with actions. TZ: "Почта".

-- Character names of this account (without realm).
local function ownNames()
    local names = {}
    for key in pairs(ns.db.chars) do names[key:match("^[^-]+") or key] = true end
    return names
end

-- "cod" | "own" | "stranger_gold" | "plain"
function M.OtherKind(h)
    if h.cod > 0 then return "cod" end
    local sender = h.sender and (h.sender:match("^[^-]+") or h.sender)
    if sender and ownNames()[sender] then return "own" end
    if h.money > 0 and not ns.TradeAPI.IsGuildMember(h.sender) then return "stranger_gold" end
    return "plain"
end

-- COD mail: market value of the attachments vs the price. { cod, value, profit, verdict, items }
function M.CodInfo(index)
    local h = MailAPI.Header(index)
    if not h or h.cod == 0 then return nil end
    local key = ns.Prices.DefaultKey()
    local cut = ns.AH.Cut(key)
    local items = MailAPI.Items(index)
    local value = 0
    for _, it in ipairs(items) do
        local v = it.itemID and ns.Prices.Value(it.itemID, key)
        if v then value = value + ns.Money.AfterCut(v, cut) * it.count end
    end
    local profit = value - h.cod
    return { cod = h.cod, value = value, profit = profit, verdict = profit > 0 and "good" or "bad", items = items }
end

-- Must be called from a click. Sends the mail back.
function M.Return(index)
    MailAPI.Return(index)
end

-- Must be called from a click: takes everything from a mail of an own character.
function M.TakeOwn(index)
    MailAPI.TakeAll(index)
end

-- Must be called from a click: pays the COD (VERIFY: taking an attachment pays it, as on retail)
-- and records the purchase. The remaining attachments are taken with the same click by the client.
function M.PayCod(index)
    local info = M.CodInfo(index)
    if not info or #info.items == 0 then return false end
    local h = MailAPI.Header(index)
    local qty, totalValue = 0, 0
    for _, it in ipairs(info.items) do totalValue = totalValue + (ns.Prices.Value(it.itemID) or 0) * it.count end
    for _, it in ipairs(info.items) do
        -- Spread the price over the items by market value.
        local share = totalValue > 0 and math.floor(info.cod * (ns.Prices.Value(it.itemID) or 0) * it.count / totalValue + 0.5)
            or math.floor(info.cod / #info.items + 0.5)
        CostBasis.Add(ns.db.books, it.itemID, it.count, share)
        qty = qty + it.count
    end
    local first = info.items[1]
    ns.Record({ kind = "cod", itemID = first.itemID, name = first.name, qty = qty, amount = -info.cod, profit = 0,
        note = h and h.subject })
    MailAPI.TakeAll(index)
    return true
end

-- Collecting ----------------------------------------------------------------------------

M.collecting = nil

local function stop(reason)
    local c = M.collecting
    M.collecting = nil
    if c then
        ns.Print(L.MAIL_COLLECTED:format(c.taken, ns.FormatMoney(c.money)) ..
            (reason and reason ~= "done" and (" (" .. (L["MAIL_STOP_" .. reason] or reason) .. ")") or ""))
    end
    if ns.UI and ns.UI.Refresh then ns.UI.Refresh() end
end

-- One action at a time: find the last auction mail and take its money or one attachment.
local function step()
    local c = M.collecting
    if not c then return end
    c.waiting = nil
    local inbox = M.ReadInbox()
    local mail = inbox.auction[#inbox.auction]
    if not mail then return stop("done") end

    local fp = mail.index .. "|" .. mail.header.subject .. "|" .. mail.header.daysLeft
    if not c.recorded[fp] then
        c.recorded[fp] = true
        ns.Safe(M.RecordMail, mail)
    end

    local token = {}
    c.waiting = token
    if mail.header.money > 0 then
        c.money = c.money + mail.header.money
        MailAPI.TakeMoney(mail.index)
    else
        local items = MailAPI.Items(mail.index)
        if #items == 0 then
            -- Empty mail the client still lists: skip it by asking again shortly.
            c.empty = (c.empty or 0) + 1
            if c.empty > 5 then return stop("done") end
        else
            MailAPI.TakeItem(mail.index, items[1].slot)
        end
    end
    c.taken = c.taken + 1
    C_Timer.After(M.STEP_TIMEOUT, function()
        if M.collecting == c and c.waiting == token then stop("timeout") end
    end)
end

function M.Collect()
    if M.collecting or not M.mailOpen then return false end
    M.collecting = { taken = 0, money = 0, recorded = {} }
    step()
    return true
end

local function onInboxUpdate()
    local c = M.collecting
    if c and c.waiting then
        c.waiting = nil
        C_Timer.After(M.STEP_DELAY, step)
    end
    if ns.UI and ns.UI.Refresh then ns.UI.Refresh() end
end

-- Button on the mail frame -----------------------------------------------------------------

function M.UpdateButton()
    local b = M.button
    if not b then return end
    local n = #M.ReadInbox().auction
    b:SetText(L.MAIL_COLLECT:format(n))
    b:SetEnabled(n > 0 and not M.collecting)
end

local function createButton()
    if M.button or not MailFrame then return end
    local b = CreateFrame("Button", "BaryshCollectAuctionMail", MailFrame, "UIPanelButtonTemplate")
    b:SetSize(190, 22)
    b:SetPoint("TOPRIGHT", MailFrame, "TOPRIGHT", -60, -30)
    b:SetScript("OnClick", function() M.Collect() end)
    M.button = b
end

function M:OnEnable()
    self:RegisterEvent("MAIL_SHOW", function()
        M.mailOpen = true
        createButton()
        if M.button then M.button:Show() end
        M.UpdateButton()
        ns.Safe(ns.Probe.RecordMail)
        if ns.UI and ns.UI.ShowNear then ns.UI.ShowNear(MailFrame, "mail") end
    end)
    self:RegisterEvent("MAIL_CLOSED", function()
        M.mailOpen = false
        if M.collecting then stop("closed") end
        if ns.UI and ns.UI.HideNear then ns.UI.HideNear(MailFrame) end
    end)
    self:RegisterEvent("MAIL_INBOX_UPDATE", function()
        onInboxUpdate()
        M.UpdateButton()
    end)
    self:RegisterEvent("UI_ERROR_MESSAGE", function(_, _, _, message)
        if M.collecting and message == ERR_INV_FULL then stop("full") end
    end)
end

function M:OnDisable()
    if M.button then M.button:Hide() end
    M.collecting = nil
end
