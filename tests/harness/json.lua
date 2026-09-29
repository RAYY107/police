-- Minimal JSON codec with FiveM-like behaviour (sequential tables → arrays, {} → []).
local json = {}

local escapes = { ['"'] = '\\"', ["\\"] = "\\\\", ["\b"] = "\\b", ["\f"] = "\\f", ["\n"] = "\\n", ["\r"] = "\\r", ["\t"] = "\\t" }

local function isArray(t)
    local n = 0
    for k in pairs(t) do
        if type(k) ~= "number" or k < 1 or math.floor(k) ~= k then return false end
        n = n + 1
    end
    for i = 1, n do
        if t[i] == nil then return false end
    end
    return true, n
end

local function encode(v, seen)
    local tv = type(v)
    if v == nil then return "null" end
    if tv == "boolean" then return tostring(v) end
    if tv == "number" then
        if v ~= v or v == math.huge or v == -math.huge then return "null" end
        if math.type(v) == "integer" then return tostring(v) end
        if v == math.floor(v) and math.abs(v) < 1e15 then return string.format("%d", v) end
        return string.format("%.14g", v)
    end
    if tv == "string" then
        return '"' .. v:gsub('[%c"\\]', function(c)
            return escapes[c] or string.format("\\u%04x", c:byte())
        end) .. '"'
    end
    if tv == "table" then
        seen = seen or {}
        if seen[v] then error("circular reference") end
        seen[v] = true
        local arr, n = isArray(v)
        local out = {}
        if arr then
            for i = 1, n do out[i] = encode(v[i], seen) end
            seen[v] = nil
            return "[" .. table.concat(out, ",") .. "]"
        end
        for k, val in pairs(v) do
            if type(val) ~= "function" then
                out[#out + 1] = encode(tostring(k), seen) .. ":" .. encode(val, seen)
            end
        end
        seen[v] = nil
        return "{" .. table.concat(out, ",") .. "}"
    end
    if tv == "function" then return "null" end
    error("cannot encode " .. tv)
end

function json.encode(v) return encode(v) end

local function decodeError(str, i, msg) error(("json decode error at %d: %s"):format(i, msg)) end

local function skip(str, i)
    local _, e = str:find("^[ \n\r\t]*", i)
    return e + 1
end

local parseValue

local function parseString(str, i)
    local out = {}
    i = i + 1
    while true do
        local c = str:sub(i, i)
        if c == "" then decodeError(str, i, "unterminated string") end
        if c == '"' then return table.concat(out), i + 1 end
        if c == "\\" then
            local n = str:sub(i + 1, i + 1)
            local map = { b = "\b", f = "\f", n = "\n", r = "\r", t = "\t", ['"'] = '"', ["\\"] = "\\", ["/"] = "/" }
            if map[n] then
                out[#out + 1] = map[n]
                i = i + 2
            elseif n == "u" then
                local hex = str:sub(i + 2, i + 5)
                out[#out + 1] = utf8.char(tonumber(hex, 16))
                i = i + 6
            else
                decodeError(str, i, "bad escape")
            end
        else
            out[#out + 1] = c
            i = i + 1
        end
    end
end

function parseValue(str, i)
    i = skip(str, i)
    local c = str:sub(i, i)
    if c == "{" then
        local obj = {}
        i = skip(str, i + 1)
        if str:sub(i, i) == "}" then return obj, i + 1 end
        while true do
            local key
            key, i = parseString(str, skip(str, i))
            i = skip(str, i)
            if str:sub(i, i) ~= ":" then decodeError(str, i, "expected ':'") end
            local val
            val, i = parseValue(str, i + 1)
            obj[key] = val
            i = skip(str, i)
            local d = str:sub(i, i)
            if d == "}" then return obj, i + 1 end
            if d ~= "," then decodeError(str, i, "expected ','") end
            i = i + 1
        end
    elseif c == "[" then
        local arr = {}
        i = skip(str, i + 1)
        if str:sub(i, i) == "]" then return arr, i + 1 end
        while true do
            local val
            val, i = parseValue(str, i)
            arr[#arr + 1] = val
            i = skip(str, i)
            local d = str:sub(i, i)
            if d == "]" then return arr, i + 1 end
            if d ~= "," then decodeError(str, i, "expected ','") end
            i = i + 1
        end
    elseif c == '"' then
        return parseString(str, i)
    elseif str:sub(i, i + 3) == "true" then
        return true, i + 4
    elseif str:sub(i, i + 4) == "false" then
        return false, i + 5
    elseif str:sub(i, i + 3) == "null" then
        return nil, i + 4
    else
        local num = str:match("^-?%d+%.?%d*[eE]?[-+]?%d*", i)
        if not num or num == "" then decodeError(str, i, "unexpected character '" .. c .. "'") end
        return tonumber(num), i + #num
    end
end

function json.decode(str)
    if type(str) ~= "string" then return nil end
    local ok, value = pcall(parseValue, str, 1)
    if not ok then error(value, 2) end
    return value
end

return json
