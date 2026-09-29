--[[
    Evora_Police — database layer

    Drivers: oxmysql, mysql-async, ghmattimysql, or custom functions (Config.Database.Custom).
    All SQL uses positional "?" parameters; named-parameter drivers are converted automatically.
    Every call below blocks the calling thread (always call from a thread / event handler).
    Values are never nil: schema columns use NOT NULL defaults (0 / '') for "none".
]]

local DB = { ready = false, driver = nil }
Evora.DB = DB

local TIMEOUT = 15000

DB.schema = {
    [[CREATE TABLE IF NOT EXISTS `evora_police_players` (
        `user_id` INT NOT NULL,
        `name` VARCHAR(64) NOT NULL DEFAULT '',
        `avatar` VARCHAR(255) NOT NULL DEFAULT '',
        `avatar_at` INT NOT NULL DEFAULT 0,
        `last_seen` INT NOT NULL DEFAULT 0,
        PRIMARY KEY (`user_id`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],

    [[CREATE TABLE IF NOT EXISTS `evora_police_officers` (
        `user_id` INT NOT NULL,
        `name` VARCHAR(64) NOT NULL DEFAULT '',
        `rank_group` VARCHAR(64) NOT NULL DEFAULT '',
        `sector` VARCHAR(96) NOT NULL DEFAULT '',
        `ministry` VARCHAR(64) NOT NULL DEFAULT '',
        `groups_json` TEXT NULL,
        `military_code` VARCHAR(32) NOT NULL DEFAULT '',
        `attendance_total` INT NOT NULL DEFAULT 0,
        `fines_issued` INT NOT NULL DEFAULT 0,
        `jails_issued` INT NOT NULL DEFAULT 0,
        `reports_handled` INT NOT NULL DEFAULT 0,
        `impounds_issued` INT NOT NULL DEFAULT 0,
        `vacation_balance` INT NOT NULL DEFAULT 0,
        `on_duty` TINYINT NOT NULL DEFAULT 0,
        `duty_started_at` INT NOT NULL DEFAULT 0,
        `duty_last_seen` INT NOT NULL DEFAULT 0,
        `last_clock_in` INT NOT NULL DEFAULT 0,
        `last_clock_out` INT NOT NULL DEFAULT 0,
        `active` TINYINT NOT NULL DEFAULT 1,
        `created_at` INT NOT NULL DEFAULT 0,
        `updated_at` INT NOT NULL DEFAULT 0,
        PRIMARY KEY (`user_id`),
        KEY `idx_sector` (`sector`),
        KEY `idx_active` (`active`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],

    [[CREATE TABLE IF NOT EXISTS `evora_police_attendance` (
        `id` INT NOT NULL AUTO_INCREMENT,
        `user_id` INT NOT NULL,
        `sector` VARCHAR(96) NOT NULL DEFAULT '',
        `clock_in` INT NOT NULL,
        `clock_out` INT NOT NULL,
        `duration` INT NOT NULL,
        PRIMARY KEY (`id`),
        KEY `idx_user` (`user_id`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],

    [[CREATE TABLE IF NOT EXISTS `evora_police_vacations` (
        `id` INT NOT NULL AUTO_INCREMENT,
        `user_id` INT NOT NULL,
        `days` INT NOT NULL,
        `start_at` INT NOT NULL,
        `end_at` INT NOT NULL,
        `original_groups` TEXT NOT NULL,
        `inactive_group` VARCHAR(64) NOT NULL DEFAULT '',
        `status` VARCHAR(16) NOT NULL DEFAULT 'active',
        `restored` TINYINT NOT NULL DEFAULT 0,
        `ended_at` INT NOT NULL DEFAULT 0,
        `ended_by` INT NOT NULL DEFAULT 0,
        PRIMARY KEY (`id`),
        KEY `idx_user_status` (`user_id`, `status`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],

    [[CREATE TABLE IF NOT EXISTS `evora_police_pending` (
        `id` INT NOT NULL AUTO_INCREMENT,
        `user_id` INT NOT NULL,
        `action` VARCHAR(16) NOT NULL,
        `group_name` VARCHAR(64) NOT NULL,
        `created_at` INT NOT NULL,
        PRIMARY KEY (`id`),
        KEY `idx_user` (`user_id`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],

    [[CREATE TABLE IF NOT EXISTS `evora_police_reports` (
        `id` INT NOT NULL AUTO_INCREMENT,
        `reporter_id` INT NOT NULL,
        `reporter_name` VARCHAR(64) NOT NULL DEFAULT '',
        `target_id` INT NOT NULL,
        `target_name` VARCHAR(64) NOT NULL DEFAULT '',
        `reason` VARCHAR(255) NOT NULL DEFAULT '',
        `status` VARCHAR(16) NOT NULL DEFAULT 'new',
        `assigned_id` INT NOT NULL DEFAULT 0,
        `assigned_name` VARCHAR(64) NOT NULL DEFAULT '',
        `pos_x` FLOAT NOT NULL DEFAULT 0,
        `pos_y` FLOAT NOT NULL DEFAULT 0,
        `pos_z` FLOAT NOT NULL DEFAULT 0,
        `created_at` INT NOT NULL,
        `updated_at` INT NOT NULL,
        PRIMARY KEY (`id`),
        KEY `idx_status` (`status`),
        KEY `idx_reporter` (`reporter_id`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],

    [[CREATE TABLE IF NOT EXISTS `evora_police_wanted` (
        `id` INT NOT NULL AUTO_INCREMENT,
        `target_id` INT NOT NULL,
        `target_name` VARCHAR(64) NOT NULL DEFAULT '',
        `target_job` VARCHAR(64) NOT NULL DEFAULT '',
        `reason` VARCHAR(255) NOT NULL DEFAULT '',
        `created_by_id` INT NOT NULL DEFAULT 0,
        `created_by_name` VARCHAR(64) NOT NULL DEFAULT '',
        `created_at` INT NOT NULL,
        `active` TINYINT NOT NULL DEFAULT 1,
        `cleared_by_id` INT NOT NULL DEFAULT 0,
        `cleared_by_name` VARCHAR(64) NOT NULL DEFAULT '',
        `cleared_at` INT NOT NULL DEFAULT 0,
        PRIMARY KEY (`id`),
        KEY `idx_target_active` (`target_id`, `active`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],

    [[CREATE TABLE IF NOT EXISTS `evora_police_fines` (
        `id` INT NOT NULL AUTO_INCREMENT,
        `target_id` INT NOT NULL,
        `target_name` VARCHAR(64) NOT NULL DEFAULT '',
        `officer_id` INT NOT NULL,
        `officer_name` VARCHAR(64) NOT NULL DEFAULT '',
        `category` VARCHAR(32) NOT NULL,
        `category_label` VARCHAR(64) NOT NULL DEFAULT '',
        `fine_id` VARCHAR(64) NOT NULL,
        `label` VARCHAR(128) NOT NULL,
        `amount` INT NOT NULL,
        `status` VARCHAR(16) NOT NULL DEFAULT 'unpaid',
        `created_at` INT NOT NULL,
        `paid_at` INT NOT NULL DEFAULT 0,
        PRIMARY KEY (`id`),
        KEY `idx_target_status` (`target_id`, `status`),
        KEY `idx_officer` (`officer_id`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],

    [[CREATE TABLE IF NOT EXISTS `evora_police_jail` (
        `user_id` INT NOT NULL,
        `name` VARCHAR(64) NOT NULL DEFAULT '',
        `officer_id` INT NOT NULL DEFAULT 0,
        `officer_name` VARCHAR(64) NOT NULL DEFAULT '',
        `reason_id` VARCHAR(64) NOT NULL DEFAULT '',
        `reason_label` VARCHAR(128) NOT NULL DEFAULT '',
        `total_seconds` INT NOT NULL,
        `remaining_seconds` INT NOT NULL,
        `added_seconds` INT NOT NULL DEFAULT 0,
        `reduced_seconds` INT NOT NULL DEFAULT 0,
        `started_at` INT NOT NULL,
        `updated_at` INT NOT NULL,
        `clothing` MEDIUMTEXT NULL,
        `was_cuffed` TINYINT NOT NULL DEFAULT 0,
        PRIMARY KEY (`user_id`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],

    [[CREATE TABLE IF NOT EXISTS `evora_police_jail_history` (
        `id` INT NOT NULL AUTO_INCREMENT,
        `user_id` INT NOT NULL,
        `name` VARCHAR(64) NOT NULL DEFAULT '',
        `officer_id` INT NOT NULL DEFAULT 0,
        `officer_name` VARCHAR(64) NOT NULL DEFAULT '',
        `reason_label` VARCHAR(128) NOT NULL DEFAULT '',
        `total_seconds` INT NOT NULL DEFAULT 0,
        `started_at` INT NOT NULL DEFAULT 0,
        `ended_at` INT NOT NULL DEFAULT 0,
        `end_type` VARCHAR(16) NOT NULL DEFAULT '',
        `released_by_id` INT NOT NULL DEFAULT 0,
        `released_by_name` VARCHAR(64) NOT NULL DEFAULT '',
        `release_reason` VARCHAR(255) NOT NULL DEFAULT '',
        PRIMARY KEY (`id`),
        KEY `idx_user` (`user_id`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],

    [[CREATE TABLE IF NOT EXISTS `evora_police_impounds` (
        `id` INT NOT NULL AUTO_INCREMENT,
        `plate` VARCHAR(16) NOT NULL,
        `model` VARCHAR(64) NOT NULL DEFAULT '',
        `owner_id` INT NOT NULL,
        `owner_name` VARCHAR(64) NOT NULL DEFAULT '',
        `officer_id` INT NOT NULL,
        `officer_name` VARCHAR(64) NOT NULL DEFAULT '',
        `location_id` VARCHAR(32) NOT NULL,
        `reason` VARCHAR(128) NOT NULL,
        `fee` INT NOT NULL DEFAULT 0,
        `status` VARCHAR(16) NOT NULL DEFAULT 'impounded',
        `created_at` INT NOT NULL,
        `released_at` INT NOT NULL DEFAULT 0,
        `release_type` VARCHAR(16) NOT NULL DEFAULT '',
        `released_by_id` INT NOT NULL DEFAULT 0,
        `released_by_name` VARCHAR(64) NOT NULL DEFAULT '',
        PRIMARY KEY (`id`),
        KEY `idx_plate_status` (`plate`, `status`),
        KEY `idx_owner_status` (`owner_id`, `status`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],

    [[CREATE TABLE IF NOT EXISTS `evora_police_logs` (
        `id` INT NOT NULL AUTO_INCREMENT,
        `category` VARCHAR(32) NOT NULL,
        `action` VARCHAR(64) NOT NULL,
        `actor_id` INT NOT NULL DEFAULT 0,
        `actor_name` VARCHAR(64) NOT NULL DEFAULT '',
        `target_id` INT NOT NULL DEFAULT 0,
        `target_name` VARCHAR(64) NOT NULL DEFAULT '',
        `details` TEXT NULL,
        `created_at` INT NOT NULL,
        PRIMARY KEY (`id`),
        KEY `idx_category` (`category`),
        KEY `idx_actor` (`actor_id`),
        KEY `idx_target` (`target_id`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
}

---------------------------------------------------------------------------
-- Drivers
---------------------------------------------------------------------------
local function toNamed(sql, params)
    local i = 0
    local named = {}
    local out = sql:gsub("%?", function()
        i = i + 1
        named["@p" .. i] = params[i]
        return "@p" .. i
    end)
    return out, named
end

local drivers = {}

drivers.oxmysql = {
    resource = "oxmysql",
    query = function(sql, params, cb) exports.oxmysql:query(sql, params, cb) end,
    execute = function(sql, params, cb) exports.oxmysql:update(sql, params, cb) end,
    insert = function(sql, params, cb) exports.oxmysql:insert(sql, params, cb) end,
}

drivers["mysql-async"] = {
    resource = "mysql-async",
    named = true,
    query = function(sql, params, cb) exports["mysql-async"]:mysql_fetch_all(sql, params, cb) end,
    execute = function(sql, params, cb) exports["mysql-async"]:mysql_execute(sql, params, cb) end,
    insert = function(sql, params, cb) exports["mysql-async"]:mysql_insert(sql, params, cb) end,
}

drivers.ghmattimysql = {
    resource = "ghmattimysql",
    named = true,
    query = function(sql, params, cb) exports.ghmattimysql:execute(sql, params, cb) end,
    execute = function(sql, params, cb)
        exports.ghmattimysql:execute(sql, params, function(r)
            cb(type(r) == "table" and (r.affectedRows or r.changedRows) or r)
        end)
    end,
    insert = function(sql, params, cb)
        exports.ghmattimysql:execute(sql, params, function(r)
            cb(type(r) == "table" and r.insertId or r)
        end)
    end,
}

local function customDriver()
    local c = Config.Database and Config.Database.Custom
    if type(c) ~= "table" or type(c.query) ~= "function" then return nil end
    return {
        resource = nil,
        query = c.query,
        execute = c.execute or c.query,
        insert = c.insert or c.query,
    }
end

local function pickDriver()
    local wanted = Config.Database and Config.Database.Driver or "auto"
    if wanted == "custom" then return customDriver(), "custom" end
    if wanted ~= "auto" then
        local d = drivers[wanted]
        if d and GetResourceState(d.resource) == "started" then return d, wanted end
        return nil, wanted
    end
    for _, name in ipairs({ "oxmysql", "mysql-async", "ghmattimysql" }) do
        if GetResourceState(name) == "started" then return drivers[name], name end
    end
    local c = customDriver()
    if c then return c, "custom" end
    return nil, "auto"
end

---------------------------------------------------------------------------
-- Core call
---------------------------------------------------------------------------
local function prepare(sql, params)
    params = params or {}
    local count = select(2, sql:gsub("%?", ""))
    local list = {}
    for i = 1, count do
        local v = params[i]
        if v == nil then
            Evora.error("SQL parameter %d is nil in: %s", i, sql:sub(1, 120))
            v = ""
        elseif type(v) == "boolean" then
            v = v and 1 or 0
        end
        list[i] = v
    end
    if DB.driver.named then return toNamed(sql, list) end
    return sql, list
end

local function run(kind, sql, params)
    if not DB.ready then return nil end
    local q, p = prepare(sql, params)
    local promiseObj = promise.new()
    local finished = false
    local ok, err = pcall(DB.driver[kind], q, p, function(result)
        if finished then return end
        finished = true
        promiseObj:resolve({ value = result })
    end)
    if not ok then
        Evora.error("database %s failed: %s", kind, tostring(err))
        return nil
    end
    SetTimeout(TIMEOUT, function()
        if finished then return end
        finished = true
        Evora.error("database %s timed out: %s", kind, sql:sub(1, 120))
        promiseObj:resolve({})
    end)
    local r = Citizen.Await(promiseObj)
    if Config.Debug then
        Evora.debug("database", "%s → %s", (sql:sub(1, 90):gsub("%s+", " ")),
            type(r.value) == "table" and ("rows:" .. #r.value) or tostring(r.value))
    end
    return r.value
end

function DB.query(sql, params)
    local rows = run("query", sql, params)
    if type(rows) ~= "table" then return {} end
    return rows
end

function DB.single(sql, params)
    local rows = DB.query(sql, params)
    return rows[1]
end

function DB.scalar(sql, params)
    local row = DB.single(sql, params)
    if not row then return nil end
    for _, v in pairs(row) do return v end
    return nil
end

function DB.execute(sql, params)
    local r = run("execute", sql, params)
    if type(r) == "table" then r = r.affectedRows end
    return tonumber(r) or 0
end

function DB.insert(sql, params)
    local r = run("insert", sql, params)
    if type(r) == "table" then r = r.insertId end
    return tonumber(r)
end

-- Dispatches a statement to the driver without waiting for the answer (resource stop).
function DB.fire(sql, params)
    if not DB.ready then return end
    local q, p = prepare(sql, params)
    pcall(DB.driver.execute, q, p, function() end)
end

function DB.executeAsync(sql, params)
    Evora.thread(function() DB.execute(sql, params) end)
end

-- Converts "@name" placeholders (server-owner SQL hooks) into positional parameters.
function DB.named(sql, map)
    local list = {}
    local out = sql:gsub("@([%a_][%w_]*)", function(name)
        local v = map[name]
        if v == nil then v = "" end
        list[#list + 1] = v
        return "?"
    end)
    return out, list
end

function DB.init()
    local driver, name = pickDriver()
    if not driver then
        DB.ready = false
        Evora.error("Database unavailable (driver '%s'). Start oxmysql, mysql-async or ghmattimysql.", tostring(name))
        return false
    end
    DB.driver = driver
    DB.driverName = name
    DB.ready = true
    if not (Config.Database and Config.Database.AutoCreateTables == false) then
        for _, statement in ipairs(DB.schema) do
            run("execute", statement, {})
        end
    end
    Evora.print("Database ready (%s).", name)
    return true
end
