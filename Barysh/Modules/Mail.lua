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
                out.other[#out.other + 1] = h
            end
        end
    end
    return out
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
            ns.Record({ kind = "ah_expired", itemID = it.itemID, name = it.name, qty = it.count, amount = 0, profit = 0 })
            -- Comes back into the selling queue with a "returned" mark.
            ns.db.returned = ns.db.returned or {}
            ns.db.returned[it.itemID] = (ns.db.returned[it.itemID] or 0) + it.count
        end
    end
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
    end)
    self:RegisterEvent("MAIL_CLOSED", function()
        M.mailOpen = false
        if M.collecting then stop("closed") end
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
