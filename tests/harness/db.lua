-- oxmysql-compatible export backed by a real MariaDB through LuaSQL.
local driver = require("luasql.mysql")

local M = {}
local env, conn

local function connect()
    if conn then return conn end
    env = driver.mysql()
    conn = assert(env:connect(os.getenv("EVORA_DB") or "evora_test", os.getenv("EVORA_DB_USER") or "evora",
        os.getenv("EVORA_DB_PASS") or "evora", os.getenv("EVORA_DB_HOST") or "localhost"))
    conn:execute("SET NAMES utf8mb4")
    return conn
end
M.connect = connect

local function literal(v)
    if v == nil then return "NULL" end
    if type(v) == "boolean" then return v and "1" or "0" end
    if type(v) == "number" then
        if math.type(v) == "integer" then return tostring(v) end
        return string.format("%.6f", v)
    end
    return "'" .. connect():escape(tostring(v)) .. "'"
end

-- Replaces positional ? with escaped literals (the harness only; real drivers bind parameters).
function M.interpolate(sql, params)
    local i = 0
    return (sql:gsub("%?", function()
        i = i + 1
        return literal(params and params[i])
    end))
end

function M.raw(sql)
    local c = connect()
    local cur, err = c:execute(sql)
    if not cur then error(err .. "\nSQL: " .. sql) end
    if type(cur) == "number" then return cur end
    local types = cur:getcoltypes()
    local names = cur:getcolnames()
    local rows = {}
    local row = cur:fetch({}, "a")
    while row do
        local out = {}
        for i, name in ipairs(names) do
            local v = row[name]
            if v ~= nil and types[i]:match("^number") then v = tonumber(v) end
            out[name] = v
        end
        rows[#rows + 1] = out
        row = cur:fetch({}, "a")
    end
    cur:close()
    return rows
end

function M.install(H)
    H.sqlLog = {}
    local function run(sql, params)
        local q = M.interpolate(sql, params)
        H.sqlLog[#H.sqlLog + 1] = q
        local ok, res = pcall(M.raw, q)
        if not ok then
            H.sqlErrors = H.sqlErrors or {}
            H.sqlErrors[#H.sqlErrors + 1] = res
            return nil
        end
        return res
    end
    H.resourceExports.oxmysql = {
        query = function(_, sql, params, cb)
            local r = run(sql, params)
            if type(r) == "number" then r = { affectedRows = r } end
            cb(r)
        end,
        update = function(_, sql, params, cb)
            local r = run(sql, params)
            cb(type(r) == "number" and r or 0)
        end,
        insert = function(_, sql, params, cb)
            local r = run(sql, params)
            if r == nil then cb(nil) return end
            cb(tonumber(connect():getlastautoid()))
        end,
    }
end

-- Drops every table used by the tests.
function M.wipe()
    local c = connect()
    local rows = M.raw("SHOW TABLES")
    for _, row in ipairs(rows) do
        for _, name in pairs(row) do
            c:execute("DROP TABLE IF EXISTS `" .. name .. "`")
        end
    end
end

return M
