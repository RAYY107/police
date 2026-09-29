--[[
    Evora_Police — shared helpers (client + server)
]]

Utils = {}

function Utils.trim(s)
    if type(s) ~= "string" then return "" end
    return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

-- Replaces {name} placeholders with values from vars.
function Utils.format(template, vars)
    if type(template) ~= "string" then return "" end
    if type(vars) ~= "table" then return template end
    return (template:gsub("{([%w_]+)}", function(key)
        local value = vars[key]
        if value == nil then return "{" .. key .. "}" end
        return tostring(value)
    end))
end

function Utils.round(n, decimals)
    local m = 10 ^ (decimals or 0)
    return math.floor(n * m + 0.5) / m
end

function Utils.clamp(n, min, max)
    if n < min then return min end
    if n > max then return max end
    return n
end

-- Returns an integer or nil. Accepts numbers and numeric strings.
function Utils.toInt(value)
    if type(value) == "string" then value = tonumber(Utils.trim(value)) end
    if type(value) ~= "number" or value ~= value or value == math.huge or value == -math.huge then return nil end
    if math.floor(value) ~= value then return nil end
    return math.tointeger(value) or math.floor(value)
end

function Utils.toNumber(value)
    if type(value) == "string" then value = tonumber(Utils.trim(value)) end
    if type(value) ~= "number" or value ~= value or value == math.huge or value == -math.huge then return nil end
    return value
end

local function coords(v)
    if v == nil then return nil end
    if type(v) == "table" or type(v) == "vector3" or type(v) == "vector4" or type(v) == "userdata" then
        local x = v.x or v[1]
        local y = v.y or v[2]
        local z = v.z or v[3] or 0.0
        if x and y then return x, y, z end
    end
    return nil
end
Utils.coords = coords

function Utils.dist(a, b)
    local ax, ay, az = coords(a)
    local bx, by, bz = coords(b)
    if not ax or not bx then return math.huge end
    local dx, dy, dz = ax - bx, ay - by, az - bz
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

function Utils.dist2d(a, b)
    local ax, ay = coords(a)
    local bx, by = coords(b)
    if not ax or not bx then return math.huge end
    local dx, dy = ax - bx, ay - by
    return math.sqrt(dx * dx + dy * dy)
end

function Utils.vec(v)
    local x, y, z = coords(v)
    if not x then return nil end
    return { x = x + 0.0, y = y + 0.0, z = z + 0.0 }
end

function Utils.utf8len(s)
    if type(s) ~= "string" then return 0 end
    local ok, len = pcall(utf8.len, s)
    if ok and len then return len end
    return #s
end

function Utils.utf8sub(s, i, j)
    if type(s) ~= "string" then return "" end
    local ok, len = pcall(utf8.len, s)
    if not ok or not len then return s:sub(i, j) end
    j = j or len
    if i < 1 then i = 1 end
    if j > len then j = len end
    if i > j then return "" end
    local startByte = utf8.offset(s, i)
    local endByte = utf8.offset(s, j + 1)
    return s:sub(startByte, (endByte or (#s + 1)) - 1)
end

-- Cleans free text coming from players: strips control characters and markup brackets,
-- collapses whitespace and limits the length (in characters, UTF-8 aware).
-- Drops byte sequences that are not valid UTF-8 (they break JSON consumers such as Discord).
function Utils.validUtf8(s)
    if type(s) ~= "string" then return "" end
    if utf8.len(s) then return s end
    local out, i, n = {}, 1, #s
    while i <= n do
        if utf8.len(s, i, i) then
            local lead = s:byte(i)
            local size = lead < 0x80 and 1 or lead >= 0xF0 and 4 or lead >= 0xE0 and 3 or 2
            out[#out + 1] = s:sub(i, i + size - 1)
            i = i + size
        else
            i = i + 1
        end
    end
    return table.concat(out)
end

function Utils.sanitize(s, maxLen, keepNewLines)
    if type(s) ~= "string" then return "" end
    s = Utils.validUtf8(s)
    if keepNewLines then
        s = s:gsub("\r\n", "\n"):gsub("[\0-\9\11-\31\127]", "")
        s = s:gsub("\n\n\n+", "\n\n")
    else
        s = s:gsub("[\0-\31\127]", " ")
    end
    s = s:gsub("[<>]", "")
    s = s:gsub("[ \t]+", " ")
    s = Utils.trim(s)
    if maxLen and Utils.utf8len(s) > maxLen then
        s = Utils.utf8sub(s, 1, maxLen)
    end
    return s
end

-- FiveM names are shown in vRP menus (HTML) and chat: remove markup characters.
function Utils.safeName(name)
    if type(name) ~= "string" or name == "" then return "?" end
    local clean = Utils.validUtf8(name):gsub("[\0-\31\127<>]", ""):gsub("%^%d", "")
    clean = Utils.trim(clean)
    if clean == "" then return "?" end
    return Utils.utf8sub(clean, 1, 32)
end

function Utils.escapeHtml(s)
    s = tostring(s or "")
    return (s:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"):gsub('"', "&quot;"))
end

function Utils.normalizePlate(plate)
    if type(plate) ~= "string" then return "" end
    plate = plate:upper():gsub("[^%w ]", ""):gsub("%s+", " ")
    return Utils.trim(plate)
end

function Utils.toSet(list)
    local set = {}
    if type(list) == "table" then
        for _, v in ipairs(list) do set[v] = true end
    end
    return set
end

function Utils.count(t)
    local n = 0
    if type(t) == "table" then
        for _ in pairs(t) do n = n + 1 end
    end
    return n
end

function Utils.copy(value, seen)
    if type(value) ~= "table" then return value end
    seen = seen or {}
    if seen[value] then return seen[value] end
    local out = {}
    seen[value] = out
    for k, v in pairs(value) do
        out[Utils.copy(k, seen)] = Utils.copy(v, seen)
    end
    return out
end

function Utils.keys(t)
    local out = {}
    for k in pairs(t or {}) do out[#out + 1] = k end
    return out
end

-- Sorts the keys of a config table by an optional `order` field, then by key.
function Utils.orderedKeys(t)
    local keys = Utils.keys(t)
    table.sort(keys, function(a, b)
        local oa = type(t[a]) == "table" and tonumber(t[a].order) or math.huge
        local ob = type(t[b]) == "table" and tonumber(t[b].order) or math.huge
        if oa ~= ob then return oa < ob end
        return tostring(a) < tostring(b)
    end)
    return keys
end

function Utils.pad2(n)
    n = math.floor(n)
    if n < 10 then return "0" .. n end
    return tostring(n)
end

-- 3725 → "01:02:05"
function Utils.clock(seconds)
    seconds = math.max(0, math.floor(tonumber(seconds) or 0))
    local h = math.floor(seconds / 3600)
    local m = math.floor((seconds % 3600) / 60)
    local s = seconds % 60
    return Utils.pad2(h) .. ":" .. Utils.pad2(m) .. ":" .. Utils.pad2(s)
end

-- 1475 → "24:35"
function Utils.mmss(seconds)
    seconds = math.max(0, math.floor(tonumber(seconds) or 0))
    local m = math.floor(seconds / 60)
    local s = seconds % 60
    return Utils.pad2(m) .. ":" .. Utils.pad2(s)
end

function Utils.minutes(seconds)
    return math.max(0, math.ceil((tonumber(seconds) or 0) / 60))
end

-- Human readable duration in Arabic: "3 ساعات و 12 دقيقة"
function Utils.humanDuration(seconds)
    seconds = math.max(0, math.floor(tonumber(seconds) or 0))
    local d = math.floor(seconds / 86400)
    local h = math.floor((seconds % 86400) / 3600)
    local m = math.floor((seconds % 3600) / 60)
    local parts = {}
    if d > 0 then parts[#parts + 1] = d .. " يوم" end
    if h > 0 then parts[#parts + 1] = h .. " ساعة" end
    if m > 0 or #parts == 0 then parts[#parts + 1] = m .. " دقيقة" end
    return table.concat(parts, " و ")
end

function Utils.money(amount)
    local s = tostring(math.floor(tonumber(amount) or 0))
    local out, n = s:reverse():gsub("(%d%d%d)", "%1,")
    out = out:reverse()
    if out:sub(1, 1) == "," then out = out:sub(2) end
    return out
end

-- Locale lookup with {placeholder} support. Missing keys return the key itself.
function L(key, vars)
    local text = Locale and Locale[key]
    if text == nil then return key end
    if vars then return Utils.format(text, vars) end
    return text
end
