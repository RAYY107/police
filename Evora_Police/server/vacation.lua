--[[
    Evora_Police — vacations (الإجازات)

    Starting a vacation saves the exact military groups of the officer, removes them, gives the
    configured inactive group and consumes balance. Ending (expiry or كسر الإجازة) restores the
    exact groups — immediately when online, otherwise on the next join.
]]

local Vacation = { active = {} } -- [user_id] = vacation row
Evora.Vacation = Vacation

local DB, P, Gov, Logs, F = Evora.DB, Evora.Players, Evora.Gov, Evora.Logs, Evora.Framework

local function cfg() return Config.Vacation or {} end

local function decode(raw)
    local ok, list = pcall(json.decode, raw or "[]")
    return ok and type(list) == "table" and list or {}
end

function Vacation.isOnVacation(user_id)
    return Vacation.active[tonumber(user_id)] ~= nil
end

function Vacation.get(user_id)
    return Vacation.active[tonumber(user_id)]
end

function Vacation.load()
    Vacation.active = {}
    for _, row in ipairs(DB.query("SELECT * FROM evora_police_vacations WHERE status = 'active'")) do
        Vacation.active[tonumber(row.user_id)] = row
    end
end

function Vacation.validDays(days)
    days = Utils.toInt(days)
    if not days or days < 1 then return nil end
    for _, d in ipairs(cfg().Durations or {}) do
        if d.days == days then return days end
    end
    if cfg().AllowCustom and days <= (cfg().MaxCustomDays or 30) then return days end
    return nil
end

function Vacation.request(user_id, source, profile, days)
    if not Evora.feature("Vacation") then return nil, L("err_feature_disabled") end
    days = Vacation.validDays(days)
    if not days then return nil, L("vacation_invalid_days") end
    if Vacation.active[user_id] then return nil, L("vacation_already") end
    local original = Gov.militaryGroups(profile.groups or {})
    if #original == 0 then return nil, L("err_not_military") end

    local record = Evora.Officers.sync(user_id, profile)
    if not record or (tonumber(record.vacation_balance) or 0) < days then
        return nil, L("vacation_no_balance", { balance = record and record.vacation_balance or 0 })
    end
    local charged = DB.execute(
        "UPDATE evora_police_officers SET vacation_balance = vacation_balance - ? WHERE user_id = ? AND vacation_balance >= ?",
        { days, user_id, days }
    )
    if charged < 1 then return nil, L("vacation_no_balance", { balance = record.vacation_balance }) end

    if Evora.Officers.isOnDuty(user_id) then Evora.Officers.clockOut(user_id, "vacation") end

    local now = Evora.now()
    local inactive = cfg().InactiveGroup or ""
    local row = {
        user_id = user_id, days = days, start_at = now, end_at = now + days * 86400,
        original_groups = json.encode(original), inactive_group = inactive, status = "active", restored = 0,
    }
    row.id = DB.insert(
        "INSERT INTO evora_police_vacations (user_id, days, start_at, end_at, original_groups, inactive_group, status) VALUES (?, ?, ?, ?, ?, ?, 'active')",
        { user_id, days, row.start_at, row.end_at, row.original_groups, inactive }
    )
    if not row.id then
        DB.execute("UPDATE evora_police_officers SET vacation_balance = vacation_balance + ? WHERE user_id = ?", { days, user_id })
        return nil, L("err_internal")
    end

    -- Mark the vacation before changing groups so group listeners know why ranks disappear.
    Vacation.active[user_id] = row
    for _, group in ipairs(original) do F.removeUserGroup(user_id, group) end
    if inactive ~= "" then F.addUserGroup(user_id, inactive) end
    Gov.getProfile(user_id, true)

    Logs.add("affairs", "vacation_start", {
        actor = user_id,
        fields = { { L("log_field_days"), days }, { L("log_field_groups"), table.concat(original, ", ") } },
    })
    Evora.Officers.pushState(user_id)
    return row
end

-- Gives back the exact saved groups (player must be online).
function Vacation.restore(user_id, row)
    if row.inactive_group and row.inactive_group ~= "" then F.removeUserGroup(user_id, row.inactive_group) end
    for _, group in ipairs(decode(row.original_groups)) do
        if Gov.ranks[group] then F.addUserGroup(user_id, group) end
    end
    DB.execute("UPDATE evora_police_vacations SET restored = 1 WHERE id = ?", { row.id })
    Gov.getProfile(user_id, true)
end

-- status: "ended" (expired) | "broken" (كسر الإجازة) | "cancelled" (dismissed while on vacation)
function Vacation.finish(user_id, status, byUserId)
    local row = Vacation.active[user_id]
    if not row then return nil, L("vacation_none") end
    Vacation.active[user_id] = nil
    local now = Evora.now()

    local refund = 0
    if status == "broken" and cfg().RefundOnBreak then
        refund = math.max(0, math.floor((tonumber(row.end_at) - now) / 86400))
    end
    DB.execute("UPDATE evora_police_vacations SET status = ?, ended_at = ?, ended_by = ?, restored = ? WHERE id = ?",
        { status, now, byUserId or 0, status == "cancelled" and 1 or 0, row.id })
    if refund > 0 then
        DB.execute("UPDATE evora_police_officers SET vacation_balance = LEAST(vacation_balance + ?, ?) WHERE user_id = ?",
            { refund, cfg().MaxBalance or 60, user_id })
    end

    local online = P.isOnline(user_id)
    if status == "cancelled" then
        if row.inactive_group and row.inactive_group ~= "" then Evora.Officers.setGroup(user_id, row.inactive_group, false) end
    elseif online then
        Vacation.restore(user_id, row)
    end

    Logs.add("affairs", "vacation_" .. status, {
        actor = byUserId ~= user_id and byUserId or user_id,
        target = byUserId ~= user_id and user_id or nil,
        fields = { { L("log_field_refund"), refund } },
    })
    if online then
        Evora.notify(P.getSource(user_id), "vacation_finished_" .. status, { refund = refund }, "info")
        Evora.Officers.pushState(user_id)
    end
    return true
end

-- Joins: finish expired vacations and restore vacations that ended while offline.
Evora.on("playerReady", function(user_id)
    local row = Vacation.active[user_id]
    if row and tonumber(row.end_at) <= Evora.now() then Vacation.finish(user_id, "ended", 0) end
    for _, pending in ipairs(DB.query(
        "SELECT * FROM evora_police_vacations WHERE user_id = ? AND restored = 0 AND status IN ('ended', 'broken')", { user_id })) do
        Vacation.restore(user_id, pending)
        Evora.notify(P.getSource(user_id), "vacation_restored", nil, "success")
    end
end)

Citizen.CreateThread(function()
    while true do
        Citizen.Wait((cfg().CheckInterval or 60) * 1000)
        local now = Evora.now()
        for uid, row in pairs(Vacation.active) do
            if tonumber(row.end_at) <= now then Vacation.finish(uid, "ended", 0) end
        end
    end
end)

---------------------------------------------------------------------------
-- RPC
---------------------------------------------------------------------------
Evora.RPC.register("vacation:request", { feature = "Vacation", perm = "vacation", cooldown = 3000 }, function(ctx, data)
    local row, err = Vacation.request(ctx.user_id, ctx.source, ctx.profile, data.days)
    if not row then return nil, err end
    return { endsAt = row.end_at, days = row.days }
end)

Evora.RPC.register("vacation:break", { feature = "Vacation", military = true, allowVacation = true, cooldown = 3000 }, function(ctx)
    if not Vacation.isOnVacation(ctx.user_id) then return nil, L("vacation_none") end
    local ok, err = Vacation.finish(ctx.user_id, "broken", ctx.user_id)
    if not ok then return nil, err end
    return true
end)
