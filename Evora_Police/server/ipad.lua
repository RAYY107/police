--[[
    Evora_Police — iPad (القائمة العسكرية): bootstrap, مكتبي and المتصلين.
]]

local Ipad = {}
Evora.Ipad = Ipad

local P, Gov, Officers, Vacation, RPC = Evora.Players, Evora.Gov, Evora.Officers, Evora.Vacation, Evora.RPC

function Ipad.canOpen(user_id, profile)
    if not Evora.feature("Ipad") then return false end
    if Vacation.isOnVacation(user_id) then return true end
    return profile.isMilitary and Gov.has(profile, "ipad")
end

function Ipad.office(user_id)
    local record = Officers.get(user_id) or {}
    local session = Officers.sessionSeconds(user_id)
    local vac = Vacation.get(user_id)
    return {
        finesIssued = tonumber(record.fines_issued) or 0,
        jailsIssued = tonumber(record.jails_issued) or 0,
        reportsHandled = tonumber(record.reports_handled) or 0,
        session = session,
        attendance = (tonumber(record.attendance_total) or 0) + session,
        onDuty = Officers.isOnDuty(user_id),
        code = record.military_code or "",
        vacationBalance = tonumber(record.vacation_balance) or 0,
        vacation = vac and { active = true, endsAt = tonumber(vac.end_at), startedAt = tonumber(vac.start_at), days = tonumber(vac.days) } or { active = false },
        lastClockIn = tonumber(record.last_clock_in) or 0,
    }
end

-- Opens the iPad for a player (server decides; the client only renders).
function Ipad.open(source, tab)
    local user_id = P.getUserId(source)
    if not user_id then return end
    local profile = Gov.getProfile(user_id, true)
    if not Ipad.canOpen(user_id, profile) then
        Evora.notify(source, "err_no_permission", nil, "error")
        return
    end
    TriggerClientEvent("evora_police:ipad:open", source, tab or "office")
end

RPC.register("ipad:bootstrap", { feature = "Ipad", military = true, allowVacation = true }, function(ctx)
    if not Ipad.canOpen(ctx.user_id, ctx.profile) then return nil, L("err_no_permission") end
    local summary = Gov.summary(ctx.profile)
    local onVacation = Vacation.isOnVacation(ctx.user_id)
    local perms = {}
    if not onVacation then
        for _, p in ipairs(summary.permissions) do perms[p] = true end
    end
    local vcfg = Config.Vacation or {}
    return {
        me = {
            user_id = ctx.user_id,
            name = ctx.name,
            avatar = Evora.Integrations.ProfileImage.get(ctx.user_id),
            rank = summary.rank,
            sectorLabel = summary.sectorLabel,
            ministryLabel = summary.ministryLabel,
            military = summary.military,
            vacation = onVacation,
        },
        perms = perms,
        features = {
            clock = Evora.feature("Clock"),
            reports = Evora.feature("Reports") and Evora.feature("CitizenReport"),
            wanted = Evora.feature("Wanted"),
            affairs = Evora.feature("Affairs") and perms.affairs == true,
            vacation = Evora.feature("Vacation"),
        },
        office = Ipad.office(ctx.user_id),
        vacationOptions = {
            durations = vcfg.Durations or {},
            allowCustom = vcfg.AllowCustom == true,
            maxCustom = vcfg.MaxCustomDays or 30,
        },
        codeMax = (Config.MilitaryCode and Config.MilitaryCode.MaxLength) or 12,
        reportStatuses = { "new", "claimed", "processing", "closed", "cancelled" },
        now = Evora.now(),
    }
end)

RPC.register("ipad:office", { feature = "Ipad", military = true, allowVacation = true }, function(ctx)
    if not Ipad.canOpen(ctx.user_id, ctx.profile) then return nil, L("err_no_permission") end
    local office = Ipad.office(ctx.user_id)
    office.now = Evora.now()
    return office
end)

RPC.register("ipad:online", { feature = "Ipad", perm = "ipad" }, function()
    return { list = Officers.onlineList(), now = Evora.now() }
end)

RPC.register("office:clock", { feature = "Clock", perm = "clock", cooldown = 2000 }, function(ctx)
    if Officers.isOnDuty(ctx.user_id) then
        local duration = Officers.clockOut(ctx.user_id, "manual")
        return { onDuty = false, duration = duration }
    end
    local ok, err = Officers.clockIn(ctx.user_id, ctx.source, ctx.profile)
    if not ok then return nil, err end
    return { onDuty = true }
end)

RPC.register("office:setCode", { feature = "Ipad", perm = "militaryCode", cooldown = 2000 }, function(ctx, data)
    if type(data.code) ~= "string" then return nil, L("err_invalid_request") end
    Officers.sync(ctx.user_id, ctx.profile)
    local code = Officers.setCode(ctx.user_id, ctx.source, data.code)
    return { code = code }
end)

-- Toggle from the Builder Menu entry "تسجيل الدخول / تسجيل الخروج".
function Ipad.toggleDuty(source)
    local user_id = P.getUserId(source)
    if not user_id then return end
    local profile = Gov.getProfile(user_id, true)
    if not Evora.feature("Clock") or not Gov.has(profile, "clock") then
        return Evora.notify(source, "err_no_permission", nil, "error")
    end
    if Officers.isOnDuty(user_id) then
        local duration = Officers.clockOut(user_id, "manual")
        Evora.notify(source, "duty_out", { duration = Utils.humanDuration(duration or 0) }, "info")
    else
        local ok, err = Officers.clockIn(user_id, source, profile)
        if ok then Evora.notify(source, "duty_in", nil, "success") else Evora.notify(source, err, nil, "error") end
    end
end
