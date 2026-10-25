local _, ns = ...

local MailAPI = {}
ns.MailAPI = MailAPI

function MailAPI.Count()
    return (GetInboxNumItems()) or 0
end

function MailAPI.Header(i)
    local _, _, sender, subject, money, cod, daysLeft, itemCount, wasRead, wasReturned = GetInboxHeaderInfo(i)
    if subject == nil and sender == nil then return nil end
    return {
        index = i, sender = sender, subject = subject or "", money = money or 0, cod = cod or 0,
        daysLeft = daysLeft, itemCount = itemCount or 0, wasRead = wasRead, wasReturned = wasReturned,
    }
end

-- VERIFY: field order of GetInboxInvoiceInfo on Forever (retail order assumed).
function MailAPI.Invoice(i)
    local invoiceType, itemName, playerName, bid, buyout, deposit, consignment, _, _, _, count = GetInboxInvoiceInfo(i)
    if not invoiceType then return nil end
    return {
        type = invoiceType, itemName = itemName, player = playerName, bid = bid or 0, buyout = buyout or 0,
        deposit = deposit or 0, cut = consignment or 0, count = count,
    }
end

-- All return values, as text, for /barysh probe.
function MailAPI.RawInvoice(i)
    local values = { GetInboxInvoiceInfo(i) }
    local parts = {}
    for k = 1, 14 do parts[k] = tostring(values[k]) end
    return table.concat(parts, " | ")
end

-- Attachments: { {slot, itemID, count, name}, ... }
function MailAPI.Items(i)
    local out = {}
    for a = 1, ATTACHMENTS_MAX_RECEIVE or 16 do
        local name, itemID, _, count = GetInboxItem(i, a)
        if name or itemID then
            out[#out + 1] = { slot = a, itemID = itemID, count = count or 1, name = name }
        end
    end
    return out
end

function MailAPI.TakeMoney(i)
    TakeInboxMoney(i)
end

function MailAPI.TakeItem(i, slot)
    TakeInboxItem(i, slot)
end

-- Client format strings for auction mail subjects.
function MailAPI.SubjectFormats()
    return {
        sold = AUCTION_SOLD_MAIL_SUBJECT,
        won = AUCTION_WON_MAIL_SUBJECT,
        expired = AUCTION_EXPIRED_MAIL_SUBJECT,
        cancelled = AUCTION_REMOVED_MAIL_SUBJECT,
        outbid = AUCTION_OUTBID_MAIL_SUBJECT,
    }
end
