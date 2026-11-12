-- Data only. Incoming packets are never evaluated as Lua.
local addonName, addon = ...
addon = addon or {}
_G.NibWhisper = addon
local P = { MAX_PACKET = 131072, MAX_QUESTION = 2000 }
addon.Protocol = P
local arrayMeta = { __nibarray = true }
P.NULL = setmetatable({}, { __tostring = function() return "null" end })

function P.Array(value)
    return setmetatable(value or {}, arrayMeta)
end

function P.IsArray(value)
    return type(value) == "table" and getmetatable(value) == arrayMeta
end

function P.IsFinite(value)
    return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

function P.IsPositiveInteger(value)
    return P.IsFinite(value) and value > 0 and value == math.floor(value) and value <= 2147483647
end

local function utf8codepoint(n)
    if n < 0 or n > 1114111 or (n >= 55296 and n <= 57343) then error("Invalid Unicode code point") end
    if n < 128 then return string.char(n) end
    if n < 2048 then return string.char(192 + math.floor(n / 64), 128 + n % 64) end
    if n < 65536 then return string.char(224 + math.floor(n / 4096), 128 + math.floor(n / 64) % 64, 128 + n % 64) end
    return string.char(240 + math.floor(n / 262144), 128 + math.floor(n / 4096) % 64, 128 + math.floor(n / 64) % 64, 128 + n % 64)
end

function P.ValidUTF8(s)
    if type(s) ~= "string" then return false end
    local i = 1
    while i <= #s do
        local a, b, c, d = s:byte(i, i + 3)
        local function continuation(n) return n and n >= 128 and n <= 191 end
        if a < 128 then i = i + 1
        elseif a >= 194 and a <= 223 and continuation(b) then i = i + 2
        elseif a >= 224 and a <= 239 and continuation(b) and continuation(c)
            and not (a == 224 and b < 160) and not (a == 237 and b >= 160) then i = i + 3
        elseif a >= 240 and a <= 244 and continuation(b) and continuation(c) and continuation(d)
            and not (a == 240 and b < 144) and not (a == 244 and b >= 144) then i = i + 4
        else return false end
    end
    return true
end

function P.TruncateUTF8(s, maxBytes)
    s = tostring(s or "")
    if #s <= maxBytes then return s end
    s = s:sub(1, maxBytes)
    while #s > 0 and not P.ValidUTF8(s) do s = s:sub(1, -2) end
    return s
end

function P.SanitizeText(value, maxBytes)
    if type(value) ~= "string" then return "" end
    local text = value:gsub("\r\n", "\n"):gsub("\r", "\n")
    text = text:gsub("|H.-|h(.-)|h", "%1"):gsub("|T.-|t", ""):gsub("|A.-|a", "")
    text = text:gsub("|K.-|k", "[hidden]"):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    text = text:gsub("|n", "\n"):gsub("|", ""):gsub("[%z\1-\8\11\12\14-\31\127]", "")
    return P.TruncateUTF8(text, maxBytes or 24000)
end

local escapes = { ['"'] = '\\"', ['\\'] = '\\\\', ['\b'] = '\\b', ['\f'] = '\\f', ['\n'] = '\\n', ['\r'] = '\\r', ['\t'] = '\\t' }
local function quote(s)
    if not P.ValidUTF8(s) then error("Invalid UTF-8 string") end
    return '"' .. s:gsub('[%z\1-\31\\"]', function(c) return escapes[c] or string.format('\\u%04x', c:byte()) end) .. '"'
end

function P.EncodeJSON(value)
    local seen, nodes = {}, 0
    local function encode(v, depth)
        nodes = nodes + 1
        if nodes > 50000 or depth > 32 then error("JSON structure is too large") end
        if v == P.NULL or v == nil then return "null" end
        local kind = type(v)
        if kind == "boolean" then return v and "true" or "false" end
        if kind == "number" then
            if not P.IsFinite(v) then error("Nonfinite JSON number") end
            return string.format("%.17g", v)
        end
        if kind == "string" then return quote(v) end
        if kind ~= "table" then error("Unsupported JSON value") end
        if seen[v] then error("Cyclic JSON value") end
        seen[v] = true
        local out = {}
        local isArray = P.IsArray(v)
        if not isArray and #v > 0 then
            isArray = true
            local n = 0
            for k in pairs(v) do
                if type(k) ~= "number" or k < 1 or k ~= math.floor(k) then isArray = false; break end
                n = n + 1
            end
            if n ~= #v then isArray = false end
        end
        if isArray then
            for k in pairs(v) do
                if type(k) ~= "number" or k < 1 or k > #v or k ~= math.floor(k) then error("Invalid JSON array") end
            end
            for i = 1, #v do out[#out + 1] = encode(v[i], depth + 1) end
        else
            local keys = {}
            for k in pairs(v) do if type(k) ~= "string" then error("JSON object keys must be strings") end; keys[#keys + 1] = k end
            table.sort(keys)
            for _, k in ipairs(keys) do out[#out + 1] = quote(k) .. ":" .. encode(v[k], depth + 1) end
        end
        seen[v] = nil
        return (isArray and "[" or "{") .. table.concat(out, ",") .. (isArray and "]" or "}")
    end
    return encode(value, 0)
end

function P.DecodeJSON(text)
    if type(text) ~= "string" or #text > P.MAX_PACKET or not P.ValidUTF8(text) then error("Invalid JSON input") end
    local at, nodes = 1, 0
    local function skip() local _, last = text:find("^[ \t\r\n]*", at); at = (last or at - 1) + 1 end
    local parse
    local function parseString()
        if text:sub(at, at) ~= '"' then error("Expected JSON string") end
        at = at + 1
        local out = {}
        local start = at
        while at <= #text do
            local ch = text:sub(at, at)
            if ch == '"' then out[#out + 1] = text:sub(start, at - 1); at = at + 1; return table.concat(out) end
            if ch:byte() < 32 then error("Unescaped control in JSON string") end
            if ch == "\\" then
                out[#out + 1] = text:sub(start, at - 1)
                at = at + 1
                local e = text:sub(at, at)
                local mapped = { ['"'] = '"', ['\\'] = '\\', ['/'] = '/', b = '\b', f = '\f', n = '\n', r = '\r', t = '\t' }
                if mapped[e] then out[#out + 1] = mapped[e]; at = at + 1
                elseif e == "u" then
                    local hex = text:sub(at + 1, at + 4)
                    if #hex ~= 4 or not hex:match("^%x%x%x%x$") then error("Invalid Unicode escape") end
                    local n = tonumber(hex, 16)
                    at = at + 5
                    if n >= 55296 and n <= 56319 then
                        if text:sub(at, at + 1) ~= "\\u" then error("Missing low surrogate") end
                        local lowHex = text:sub(at + 2, at + 5)
                        if not lowHex:match("^%x%x%x%x$") then error("Invalid low surrogate") end
                        local low = tonumber(lowHex, 16)
                        if low < 56320 or low > 57343 then error("Invalid low surrogate") end
                        n = 65536 + (n - 55296) * 1024 + low - 56320
                        at = at + 6
                    elseif n >= 56320 and n <= 57343 then error("Unpaired low surrogate") end
                    out[#out + 1] = utf8codepoint(n)
                else error("Invalid JSON escape") end
                start = at
            else at = at + 1 end
        end
        error("Unterminated JSON string")
    end
    local function digit() return text:sub(at, at):match("%d") ~= nil end
    local function parseNumber()
        local start = at
        if text:sub(at, at) == "-" then at = at + 1 end
        if text:sub(at, at) == "0" then at = at + 1
        elseif text:sub(at, at):match("[1-9]") then repeat at = at + 1 until not digit()
        else error("Invalid JSON number") end
        if text:sub(at, at) == "." then at = at + 1; if not digit() then error("Invalid fraction") end; repeat at = at + 1 until not digit() end
        local e = text:sub(at, at)
        if e == "e" or e == "E" then
            at = at + 1
            local sign = text:sub(at, at)
            if sign == "+" or sign == "-" then at = at + 1 end
            if not digit() then error("Invalid exponent") end
            repeat at = at + 1 until not digit()
        end
        local value = tonumber(text:sub(start, at - 1))
        if not P.IsFinite(value) then error("Nonfinite JSON number") end
        return value
    end
    parse = function(depth)
        nodes = nodes + 1
        if depth > 32 or nodes > 50000 then error("JSON structure is too large") end
        skip()
        local ch = text:sub(at, at)
        if ch == '"' then return parseString() end
        if ch == "{" or ch == "[" then
            at = at + 1
            local array = ch == "["
            local ending = array and "]" or "}"
            local result = array and P.Array() or {}
            skip()
            if text:sub(at, at) == ending then at = at + 1; return result end
            while true do
                skip()
                if array then result[#result + 1] = parse(depth + 1)
                else
                    local key = parseString()
                    if result[key] ~= nil then error("Duplicate JSON key") end
                    skip(); if text:sub(at, at) ~= ":" then error("Missing JSON colon") end
                    at = at + 1; result[key] = parse(depth + 1)
                end
                skip()
                local separator = text:sub(at, at); at = at + 1
                if separator == ending then return result end
                if separator ~= "," then error("Invalid JSON separator") end
            end
        end
        for token, value in pairs({ ["true"] = true, ["false"] = false, ["null"] = P.NULL }) do
            if text:sub(at, at + #token - 1) == token then at = at + #token; return value end
        end
        if ch == "-" or ch:match("%d") then return parseNumber() end
        error("Unexpected JSON token")
    end
    local result = parse(0)
    skip()
    if at <= #text then error("Trailing JSON data") end
    return result
end

local alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local values = {}
for i = 1, #alphabet do values[alphabet:sub(i, i)] = i - 1 end

function P.EncodeBase64(bytes)
    local out = {}
    for i = 1, #bytes, 3 do
        local a, b, c = bytes:byte(i, i + 2)
        local n = a * 65536 + (b or 0) * 256 + (c or 0)
        out[#out + 1] = alphabet:sub(math.floor(n / 262144) + 1, math.floor(n / 262144) + 1)
        local k = math.floor(n / 4096) % 64 + 1; out[#out + 1] = alphabet:sub(k, k)
        k = math.floor(n / 64) % 64 + 1; out[#out + 1] = b and alphabet:sub(k, k) or "="
        k = n % 64 + 1; out[#out + 1] = c and alphabet:sub(k, k) or "="
    end
    return table.concat(out)
end

function P.DecodeBase64(text)
    if type(text) ~= "string" or #text % 4 ~= 0 or #text > P.MAX_PACKET or text:find("[^A-Za-z0-9+/=]") then error("Invalid Base64") end
    local out = {}
    for i = 1, #text, 4 do
        local a, b, c, d = text:sub(i,i), text:sub(i+1,i+1), text:sub(i+2,i+2), text:sub(i+3,i+3)
        if not values[a] or not values[b] or (c ~= "=" and not values[c]) or (d ~= "=" and not values[d]) then error("Invalid Base64 quartet") end
        if c == "=" and d ~= "=" then error("Invalid Base64 padding") end
        if (c == "=" or d == "=") and i + 3 ~= #text then error("Early Base64 padding") end
        local n = values[a] * 262144 + values[b] * 4096 + (values[c] or 0) * 64 + (values[d] or 0)
        out[#out + 1] = string.char(math.floor(n / 65536))
        if c ~= "=" then out[#out + 1] = string.char(math.floor(n / 256) % 256) end
        if d ~= "=" then out[#out + 1] = string.char(n % 256) end
    end
    local bytes = table.concat(out)
    if P.EncodeBase64(bytes) ~= text then error("Noncanonical Base64") end
    return bytes
end

function P.EncodePacket(kind, value)
    if kind ~= "NIBQ1" and kind ~= "NIBR1" and kind ~= "NIBS1" and kind ~= "NIBP1" and kind ~= "NIBT1" and kind ~= "NIBC1" and kind ~= "NIBA1" and kind ~= "NIBK1" then error("Unknown packet kind") end
    local packet = kind .. ":" .. P.EncodeBase64(P.EncodeJSON(value))
    if #packet > P.MAX_PACKET then error("Packet exceeds 128 KiB") end
    return packet
end

function P.DecodePacket(kind, packet)
    if type(packet) ~= "string" then error("Expected a packet") end
    packet = packet:match("^%s*(.-)%s*$")
    if #packet > P.MAX_PACKET or packet:sub(1, #kind + 1) ~= kind .. ":" then error("Wrong or oversized packet") end
    return P.DecodeJSON(P.DecodeBase64(packet:sub(#kind + 2)))
end
