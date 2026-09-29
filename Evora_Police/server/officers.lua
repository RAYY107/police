--[[
    Evora_Police — officer records, duty / attendance, military code, pending group changes.

    Attendance only counts while clocked in. Sessions persist in the database, resume after a
    resource restart and are closed from the last heartbeat after a crash.
]]

local Officers = { duty = {} } -- duty[user_id] = { startedAt, source, sector }
Evora.Officers = Officers

local DB, P, Gov, Logs = Evora.DB, Evora.Players, Evora.Gov, Evora.Logs

local COUNTERS = Utils.toSet({ "fines_issued", "jails_issued", "reports_handled", "impounds_issued" })

---------------------------------------------------------------------------
-- Records
---------------------------------------------------------------------------
function Officers.get(user_id)
    return DB.single("SELECT * FROM evora_police_officers WHERE user_id = ?", { user_id })
end

local function decodeGroups(raw)
    if type(raw) ~= "string" or raw == "" then return {} end
    local ok, list = pcall(json.decode, raw)
    return ok and type(list) == "table" and list or {}
end
Officers.decodeGroups = decodeGroups

-- Creates or refreshes the record of an online military player from their live profile.
function Officers.sync(user_id, profile)
    if not profile or not profile.isMilitary then return nil end
    local now = Evora.now()
    local primary = profile.primary
    local groups = Gov.militaryGroups(profile.groups or {})
    local sector = profile.memberSector or primary.sector or ""
    local ministry = primary.ministry or ""
    local name = P.name(user_id)
    local existing = DB.single("SELECT user_id FROM evora_police_officers WHERE user_id = ?", { user_id })
    if existing then
        DB.execute(
            "UPDATE evora_police_officers SET name = ?, rank_group = ?, sector = ?, ministry = ?, groups_json = ?, active = 1, updated_at = ? WHERE user_id = ?",
            { name, primary.group, sector, ministry, json.encode(groups), now, user_id }
        )
    else
        DB.execute(
            "INSERT INTO evora_police_officers (user_id, name, rank_group, sector, ministry, groups_json, military_code, vacation_balance, active, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, 1, ?, ?)",
            { user_id, name, primary.group, sector, ministry, json.encode(groups),
              (Config.MilitaryCode and Config.MilitaryCode.Default) or "", (Config.Vacation and Config.Vacation.DefaultBalance) or 0, now, now }
        )
    end
    return Officers.get(user_id)
end

-- Stores the military groups of an OFFLINE officer (changes made while they are away).
function Officers.storeGroups(user_id, groups)
    local now = Evora.now()
    local resolved = Gov.resolve(groups)
    local list = Gov.militaryGroups(groups)
    local existing = DB.single("SELECT user_id FROM evora_police_officers WHERE user_id = ?", { user_id })
    if not resolved.primary then
        if existing then
            DB.execute("UPDATE evora_police_officers SET groups_json = '[]', active = 0, updated_at = ? WHERE user_id = ?", { now, user_id })
        end
        return
    end
    local primary = resolved.primary
    local sector = resolved.memberSector or primary.sector or ""
    if existing then
        DB.execute(
            "UPDATE evora_police_officers SET rank_group = ?, sector = ?, ministry = ?, groups_json = ?, active = 1, updated_at = ? WHERE user_id = ?",
            { primary.group, sector, primary.ministry or "", json.encode(list), now, user_id }
        )
    else
        DB.execute(
            "INSERT INTO evora_police_officers (user_id, name, rank_group, sector, ministry, groups_json, military_code, vacation_balance, active, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, '', ?, 1, ?, ?)",
            { user_id, P.name(user_id), primary.group, sector, primary.ministry or "", json.encode(list),
              (Config.Vacation and Config.Vacation.DefaultBalance) or 0, now, now }
        )
    end
end

-- Military groups of an officer: live groups when online, stored groups otherwise.
function Officers.groupsOf(user_id, record)
    if P.isOnline(user_id) then
        local profile = Gov.getProfile(user_id, true)
        if profile.isMilitary then return Gov.militaryGroups(profile.groups) end
    end
    record = record or Officers.get(user_id)
    if record and tonumber(record.active) == 1 then return decodeGroups(record.groups_json) end
    return {}
end

function Officers.increment(user_id, column, amount)
    if not COUNTERS[column] then return end
    DB.execute(("UPDATE evora_police_officers SET %s = %s + ? WHERE user_id = ?"):format(column, column), { amount or 1, user_id })
end

function Officers.deactivate(user_id)
    DB.execute("UPDATE evora_police_officers SET active = 0, updated_at = ? WHERE user_id = ?", { Evora.now(), user_id })
end

---------------------------------------------------------------------------
-- Pending group operations (applied when the player joins)
---------------------------------------------------------------------------
function Officers.queueGroup(user_id, action, group)
    DB.execute("INSERT INTO evora_police_pending (user_id, action, group_name, created_at) VALUES (?, ?, ?, ?)",
        { user_id, action, group, Evora.now() })
end

-- Adds / removes a group now when the player is online, otherwise on their next join.
function Officers.setGroup(user_id, group, add)
    if P.isOnline(user_id) then
        if add then Evora.Framework.addUserGroup(user_id, group) else Evora.Framework.removeUserGroup(user_id, group) end
        return true
    end
    Officers.queueGroup(user_id, add and "add" or "remove", group)
    return false
end

function Officers.applyPending(user_id)
    local rows = DB.query("SELECT * FROM evora_police_pending WHERE user_id = ? ORDER BY id ASC", { user_id })
    if #rows == 0 then return end
    for _, row in ipairs(rows) do
        if row.action == "add" then
            Evora.Framework.addUserGroup(user_id, row.group_name)
        else
            Evora.Framework.removeUserGroup(user_id, row.group_name)
        end
    end
    DB.execute("DELETE FROM evora_police_pending WHERE user_id = ?", { user_id })
end

---------------------------------------------------------------------------
-- Duty
---------------------------------------------------------------------------
function Officers.isOnDuty(user_id)
    return Officers.duty[tonumber(user_id)] ~= nil
end

function Officers.dutyOk(user_id, key)
    local required = Config.Duty and Config.Duty.RequireDutyFor and Config.Duty.RequireDutyFor[key]
    if not required then return true end
    return Officers.isOnDuty(user_id)
end

function Officers.sessionSeconds(user_id)
    local d = Officers.duty[tonumber(user_id)]
    if not d then return 0 end
    return math.max(0, Evora.now() - d.startedAt)
end

local function describe(user_id, profile)
    local summary = Gov.summary(profile or Gov.cached(user_id))
    return { user_id = user_id, name = P.name(user_id), rank = summary.rank, sector = summary.sector, sectorLabel = summary.sectorLabel }
end

function Officers.clockIn(user_id, source, profile)
    if Officers.duty[user_id] then return nil, L("duty_already_in") end
    if Evora.Vacation.isOnVacation(user_id) then return nil, L("vacation_blocks_duty") end
    local record = Officers.sync(user_id, profile)
    if not record then return nil, L("err_not_military") end
    local now = Evora.now()
    Officers.duty[user_id] = { startedAt = now, source = source, sector = record.sector or "" }
    DB.execute(
        "UPDATE evora_police_officers SET on_duty = 1, duty_started_at = ?, duty_last_seen = ?, last_clock_in = ? WHERE user_id = ?",
        { now, now, now, user_id }
    )
    if record.military_code and record.military_code ~= "" then
        Evora.Integrations.Radio.setCode(source, record.military_code, describe(user_id, profile))
    end
    Evora.Integrations.Radio.dutyChanged(source, true, describe(user_id, profile))
    Logs.add("attendance", "clock_in", { actor = user_id, fields = { { L("log_field_sector"), Gov.sectorLabel(record.sector) } } })
    Evora.emit("dutyChanged", user_id, true)
    Officers.pushState(user_id)
    return true
end

-- reason: "manual" | "disconnect" | "dismissed" | "vacation" | "rank_lost"
function Officers.clockOut(user_id, reason)
    local d = Officers.duty[user_id]
    if not d then return nil, L("duty_already_out") end
    Officers.duty[user_id] = nil
    local now = Evora.now()
    local duration = math.max(0, now - d.startedAt)
    DB.execute(
        "UPDATE evora_police_officers SET on_duty = 0, duty_started_at = 0, duty_last_seen = ?, attendance_total = attendance_total + ?, last_clock_out = ? WHERE user_id = ?",
        { now, duration, now, user_id }
    )
    DB.execute(
        "INSERT INTO evora_police_attendance (user_id, sector, clock_in, clock_out, duration) VALUES (?, ?, ?, ?, ?)",
        { user_id, d.sector or "", d.startedAt, now, duration }
    )
    local src = P.getSource(user_id)
    if src then Evora.Integrations.Radio.dutyChanged(src, false, describe(user_id)) end
    Logs.add("attendance", "clock_out", {
        actor = user_id,
        fields = { { L("log_field_session"), Utils.humanDuration(duration) }, { L("log_field_reason"), L("clock_reason_" .. (reason or "manual")) } },
    })
    Evora.emit("dutyChanged", user_id, false)
    Officers.pushState(user_id)
    return duration
end

-- Closes a session left open by a crash, counting only until the last heartbeat.
local function closeStale(row)
    local started = tonumber(row.duty_started_at) or 0
    local last = math.max(tonumber(row.duty_last_seen) or 0, started)
    local cap = ((Config.Duty and Config.Duty.MaxStaleSessionHours) or 12) * 3600
    local duration = math.max(0, math.min(last - started, cap))
    DB.execute(
        "UPDATE evora_police_officers SET on_duty = 0, duty_started_at = 0, attendance_total = attendance_total + ?, last_clock_out = ? WHERE user_id = ?",
        { duration, last, row.user_id }
    )
    if started > 0 then
        DB.execute("INSERT INTO evora_police_attendance (user_id, sector, clock_in, clock_out, duration) VALUES (?, ?, ?, ?, ?)",
            { row.user_id, row.sector or "", started, last, duration })
    end
    Evora.debug("database", "closed stale duty session of %d (%ds)", row.user_id, duration)
end

-- Start-up: resume sessions of connected officers (resource restart), close the others.
function Officers.recoverSessions()
    for _, row in ipairs(DB.query("SELECT user_id, sector, duty_started_at, duty_last_seen FROM evora_police_officers WHERE on_duty = 1")) do
        local uid = tonumber(row.user_id)
        local src = P.getSource(uid)
        local profile = src and Gov.getProfile(uid, true)
        if src and profile and profile.isMilitary and Gov.has(profile, "clock") and (tonumber(row.duty_started_at) or 0) > 0 then
            Officers.duty[uid] = { startedAt = tonumber(row.duty_started_at), source = src, sector = row.sector or "" }
        else
            closeStale(row)
        end
    end
end

---------------------------------------------------------------------------
-- Lists
---------------------------------------------------------------------------
function Officers.militarySources()
    local list = {}
    for uid, src in pairs(P.byUser) do
        if Gov.cached(uid).isMilitary then list[#list + 1] = src end
    end
    return list
end

function Officers.onDutySources()
    local list = {}
    for uid, d in pairs(Officers.duty) do
        local src = P.getSource(uid)
        if src then list[#list + 1] = src end
    end
    return list
end

-- المتصلين: clocked-in officers that hold a rank inside a configured sector.
function Officers.onlineList()
    local list = {}
    local codes = {}
    local ids = {}
    for uid in pairs(Officers.duty) do ids[#ids + 1] = uid end
    if #ids > 0 then
        local marks = string.rep("?, ", #ids):sub(1, -3)
        for _, row in ipairs(DB.query("SELECT user_id, military_code FROM evora_police_officers WHERE user_id IN (" .. marks .. ")", ids)) do
            codes[tonumber(row.user_id)] = row.military_code or ""
        end
    end
    for uid, d in pairs(Officers.duty) do
        local profile = Gov.cached(uid)
        if profile.isMilitary and profile.memberSector and P.isOnline(uid) then
            local sectorRank
            for _, g in ipairs(profile.grants) do
                if g.level == "sector" then sectorRank = g break end
            end
            list[#list + 1] = {
                user_id = uid,
                name = P.name(uid),
                rank = Gov.rankLabel((sectorRank or profile.primary).group),
                sector = profile.memberSector,
                sectorLabel = Gov.sectorLabel(profile.memberSector),
                code = codes[uid] or "",
                session = math.max(0, Evora.now() - d.startedAt),
            }
        end
    end
    table.sort(list, function(a, b)
        if a.sectorLabel ~= b.sectorLabel then return a.sectorLabel < b.sectorLabel end
        return a.session > b.session
    end)
    return list
end

---------------------------------------------------------------------------
-- Client state
---------------------------------------------------------------------------
function Officers.pushState(user_id)
    local src = P.getSource(user_id)
    if not src then return end
    local profile = Gov.cached(user_id)
    local summary = Gov.summary(profile)
    TriggerClientEvent("evora_police:state", src, {
        user_id = user_id,
        name = P.name(user_id),
        military = summary.military,
        onDuty = Officers.isOnDuty(user_id),
        vacation = Evora.Vacation.isOnVacation(user_id),
        jailed = Evora.Jail and Evora.Jail.isJailed(user_id) or false,
        rank = summary.rank,
        sectorLabel = summary.sectorLabel,
        ministryLabel = summary.ministryLabel,
        permissions = summary.permissions,
    })
end

---------------------------------------------------------------------------
-- Military code
---------------------------------------------------------------------------
function Officers.setCode(user_id, source, code)
    local maxLen = (Config.MilitaryCode and Config.MilitaryCode.MaxLength) or 12
    code = Utils.sanitize(code or "", maxLen)
    DB.execute("UPDATE evora_police_officers SET military_code = ?, updated_at = ? WHERE user_id = ?", { code, Evora.now(), user_id })
    Evora.Integrations.Radio.setCode(source, code, describe(user_id))
    Logs.add("affairs", "military_code", { actor = user_id, fields = { { L("log_field_code"), code ~= "" and code or "-" } } })
    return code
end

---------------------------------------------------------------------------
-- Lifecycle
---------------------------------------------------------------------------
Evora.on("playerReady", function(user_id, source, restored)
    Officers.applyPending(user_id)
    local profile = Gov.getProfile(user_id, true)
    local record = Officers.get(user_id)
    if profile.isMilitary then
        record = Officers.sync(user_id, profile)
    elseif record and tonumber(record.active) == 1 and not Evora.Vacation.isOnVacation(user_id) then
        Officers.deactivate(user_id)
    end
    if record and tonumber(record.on_duty) == 1 and not Officers.duty[user_id] then
        if restored and profile.isMilitary and (tonumber(record.duty_started_at) or 0) > 0 then
            Officers.duty[user_id] = { startedAt = tonumber(record.duty_started_at), source = source, sector = record.sector or "" }
        else
            closeStale(record)
        end
    end
    if profile.isMilitary and record and record.military_code and record.military_code ~= "" then
        Evora.Integrations.Radio.setCode(source, record.military_code, describe(user_id, profile))
    end
    Officers.pushState(user_id)
end)

Evora.on("playerDropped", function(user_id)
    if Officers.duty[user_id] then Officers.clockOut(user_id, "disconnect") end
end)

Evora.on("profileChanged", function(user_id, profile)
    if profile.isMilitary then
        Officers.sync(user_id, profile)
    else
        if Officers.duty[user_id] then Officers.clockOut(user_id, "rank_lost") end
        if not Evora.Vacation.isOnVacation(user_id) then Officers.deactivate(user_id) end
    end
    Officers.pushState(user_id)
end)

-- Attendance heartbeat: one batched update for every clocked-in officer.
Citizen.CreateThread(function()
    while true do
        Citizen.Wait(((Config.Duty and Config.Duty.HeartbeatInterval) or 60) * 1000)
        local ids = {}
        for uid in pairs(Officers.duty) do ids[#ids + 1] = uid end
        if #ids > 0 and DB.ready then
            local params = { Evora.now() }
            for _, id in ipairs(ids) do params[#params + 1] = id end
            DB.execute("UPDATE evora_police_officers SET duty_last_seen = ? WHERE user_id IN (" .. string.rep("?, ", #ids):sub(1, -3) .. ")", params)
        end
    end
end)
