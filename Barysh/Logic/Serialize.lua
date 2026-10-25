local _, ns = ...

-- Import/export strings: !BARYSH:<version>!<name>!<data>. TZ: "Импорт и экспорт строкой".
-- data = base64(mode .. body): mode "P" = plain serialized table, "Z" = raw DEFLATE of it.
-- Compression comes from the client (C_EncodingUtil), passed in as functions, so this file stays pure.
-- The same format is read and written by sync/barysh_sync/importstring.py.
local Serialize = {}
ns.Serialize = Serialize

Serialize.VERSION = 1
Serialize.PREFIX = "!BARYSH:"

-- Values: integer "i<n>;", float "f<n>;", string "s<len>:<bytes>", true "T", false "F",
-- table "{" key value ... "}". Keys are sorted, so equal tables give equal strings.

local function keyLess(a, b)
    local ta, tb = type(a), type(b)
    if ta ~= tb then return ta < tb end
    return a < b
end

local function encode(v, out)
    local t = type(v)
    if t == "number" then
        if v == math.floor(v) and v > -2 ^ 53 and v < 2 ^ 53 then
            out[#out + 1] = ("i%.0f;"):format(v) -- %d is 32-bit on some builds
        else
            out[#out + 1] = ("f%.17g;"):format(v)
        end
    elseif t == "string" then
        out[#out + 1] = "s" .. #v .. ":" .. v
    elseif t == "boolean" then
        out[#out + 1] = v and "T" or "F"
    elseif t == "table" then
        out[#out + 1] = "{"
        local keys = {}
        for k in pairs(v) do
            local tk = type(k)
            if tk == "string" or tk == "number" then keys[#keys + 1] = k end
        end
        table.sort(keys, keyLess)
        for _, k in ipairs(keys) do
            local vt = type(v[k])
            if vt == "number" or vt == "string" or vt == "boolean" or vt == "table" then
                encode(k, out)
                encode(v[k], out)
            end
        end
        out[#out + 1] = "}"
    else
        error("cannot serialize " .. t)
    end
end

function Serialize.Encode(v)
    local out = {}
    encode(v, out)
    return table.concat(out)
end

local MAX_DEPTH = 20

local function decode(s, pos, depth)
    local c = s:sub(pos, pos)
    if c == "i" or c == "f" then
        local stop = s:find(";", pos, true)
        if not stop then error("bad number") end
        local n = tonumber(s:sub(pos + 1, stop - 1))
        if not n then error("bad number") end
        return n, stop + 1
    elseif c == "s" then
        local colon = s:find(":", pos, true)
        local len = colon and tonumber(s:sub(pos + 1, colon - 1))
        if not len or colon + len > #s then error("bad string") end
        return s:sub(colon + 1, colon + len), colon + len + 1
    elseif c == "T" then
        return true, pos + 1
    elseif c == "F" then
        return false, pos + 1
    elseif c == "{" then
        if depth > MAX_DEPTH then error("too deep") end
        local t = {}
        pos = pos + 1
        while s:sub(pos, pos) ~= "}" do
            if pos > #s then error("unterminated table") end
            local k, v
            k, pos = decode(s, pos, depth + 1)
            if type(k) == "table" or type(k) == "boolean" then error("bad key") end
            v, pos = decode(s, pos, depth + 1)
            t[k] = v
        end
        return t, pos + 1
    end
    error("unexpected '" .. c .. "'")
end

-- Returns value or nil, error.
function Serialize.Decode(s)
    local ok, v, pos = pcall(decode, s, 1, 0)
    if not ok then return nil, tostring(v) end
    if pos ~= #s + 1 then return nil, "trailing data" end
    return v
end

-- Base64 without bit operations (Lua 5.1) -----------------------------------------------

local ALPHA = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local INDEX = {}
for i = 1, 64 do INDEX[ALPHA:sub(i, i)] = i - 1 end

function Serialize.ToBase64(s)
    local out = {}
    for i = 1, #s, 3 do
        local a, b, c = s:byte(i, i + 2)
        local n = a * 65536 + (b or 0) * 256 + (c or 0)
        local c1 = math.floor(n / 262144) % 64
        local c2 = math.floor(n / 4096) % 64
        local c3 = math.floor(n / 64) % 64
        local c4 = n % 64
        out[#out + 1] = ALPHA:sub(c1 + 1, c1 + 1) .. ALPHA:sub(c2 + 1, c2 + 1)
            .. (b and ALPHA:sub(c3 + 1, c3 + 1) or "=") .. (c and ALPHA:sub(c4 + 1, c4 + 1) or "=")
    end
    return table.concat(out)
end

function Serialize.FromBase64(s)
    s = s:gsub("%s", "")
    if #s % 4 ~= 0 then return nil end
    local out = {}
    for i = 1, #s, 4 do
        local q = { s:byte(i, i + 3) }
        local n, pad = 0, 0
        for j = 1, 4 do
            local ch = string.char(q[j])
            local v
            if ch == "=" then
                pad = pad + 1
                v = 0
            else
                v = INDEX[ch]
                if not v or pad > 0 then return nil end
            end
            n = n * 64 + v
        end
        local a, b, c = math.floor(n / 65536) % 256, math.floor(n / 256) % 256, n % 256
        out[#out + 1] = string.char(a)
        if pad < 2 then out[#out + 1] = string.char(b) end
        if pad < 1 then out[#out + 1] = string.char(c) end
    end
    return table.concat(out)
end

-- Import strings -------------------------------------------------------------------------

-- name: what the string carries ("list:stock", "settings"). '!' is not allowed in it.
-- compress(str) -> str or nil: raw DEFLATE; nil compressor = plain.
function Serialize.Pack(name, payload, compress)
    name = tostring(name):gsub("!", "")
    local body = Serialize.Encode(payload)
    local data = "P" .. body
    if compress then
        local z = compress(body)
        if z and #z + 1 < #data then data = "Z" .. z end
    end
    return Serialize.PREFIX .. Serialize.VERSION .. "!" .. name .. "!" .. Serialize.ToBase64(data)
end

-- Returns name, payload or nil, error ("format" | "version" | "compressed" | "data").
function Serialize.Unpack(str, decompress)
    str = (str or ""):gsub("^%s+", ""):gsub("%s+$", "")
    local version, name, data = str:match("^!BARYSH:(%d+)!([^!]*)!(.+)$")
    if not version then return nil, "format" end
    if tonumber(version) > Serialize.VERSION then return nil, "version" end
    local raw = Serialize.FromBase64(data)
    if not raw or #raw == 0 then return nil, "data" end
    local mode, body = raw:sub(1, 1), raw:sub(2)
    if mode == "Z" then
        if not decompress then return nil, "compressed" end
        body = decompress(body)
        if not body then return nil, "data" end
    elseif mode ~= "P" then
        return nil, "data"
    end
    local payload = Serialize.Decode(body)
    if type(payload) ~= "table" then return nil, "data" end
    return name, payload
end
