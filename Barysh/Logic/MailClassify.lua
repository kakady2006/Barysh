local _, ns = ...

-- Recognises auction house mail. Subjects are matched with the client's own global format
-- strings (AUCTION_SOLD_MAIL_SUBJECT etc.), so it works in any client language.
local MailClassify = {}
ns.MailClassify = MailClassify

MailClassify.SOLD = "sold"
MailClassify.WON = "won"
MailClassify.PENDING = "pending"     -- sold, money still on the way
MailClassify.EXPIRED = "expired"
MailClassify.CANCELLED = "cancelled"
MailClassify.OUTBID = "outbid"

-- "Auction successful: %s" -> "^Auction successful: (.+)$"
function MailClassify.PatternFromFormat(fmt)
    local escaped = fmt:gsub("[%^%$%(%)%.%[%]%*%+%-%?%%]", "%%%0")
    escaped = escaped:gsub("%%%%s", "(.+)"):gsub("%%%%d", "(%%d+)")
    return "^" .. escaped .. "$"
end

-- formats: { sold = AUCTION_SOLD_MAIL_SUBJECT, won = ..., expired = ..., cancelled = ..., outbid = ... }
function MailClassify.BuildPatterns(formats)
    local patterns = {}
    for kind, fmt in pairs(formats) do
        if type(fmt) == "string" then
            patterns[#patterns + 1] = { kind = kind, pattern = MailClassify.PatternFromFormat(fmt) }
        end
    end
    return patterns
end

-- invoiceType from GetInboxInvoiceInfo: "seller", "buyer", "seller_temp_invoice" or nil.
-- Returns kind, itemName (nil, nil for mail that is not from the auction house).
function MailClassify.Classify(subject, invoiceType, patterns)
    subject = subject or ""
    local name
    for _, p in ipairs(patterns) do
        local m = subject:match(p.pattern)
        if m then
            if invoiceType == nil then return p.kind, m end
            name = m
            break
        end
    end
    if invoiceType == "seller" then return MailClassify.SOLD, name end
    if invoiceType == "buyer" then return MailClassify.WON, name end
    if invoiceType == "seller_temp_invoice" then return MailClassify.PENDING, name end
    return nil, nil
end

-- Mail the "Collect auction mail" button may take.
function MailClassify.IsCollectable(kind)
    return kind == MailClassify.SOLD or kind == MailClassify.WON or kind == MailClassify.EXPIRED
        or kind == MailClassify.CANCELLED or kind == MailClassify.OUTBID
end
