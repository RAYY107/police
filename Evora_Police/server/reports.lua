--[[
    Evora_Police — citizen reports (إبلاغ عن مجرم → البلاغات)

    Status flow: new (جديد) → claimed (مستلم) → processing (قيد المعالجة) → closed (مغلق) | cancelled (ملغي)
]]

local Reports = { lastByReporter = {} }
Evora.Reports = Reports

local DB, P, Gov, Logs, Officers, RPC = Evora.DB, Evora.Players, Evora.Gov, Evora.Logs, Evora.Officers, Evora.RPC

local STATUSES = { "new", "claimed", "processing", "closed", "cancelled" }
local TRANSITIONS = {
    claimed = { processing = true, closed = true, cancelled = true },
    processing = { closed = true, cancelled = true },
}

local function cfg() return Config.Reports or {} end

local function row(r)
    return {
        id = tonumber(r.id),
        reporter = { id = tonumber(r.reporter_id), name = r.reporter_name },
        target = { id = tonumber(r.target_id), name = r.target_name },
        reason = r.reason,
        status = r.status,
        assigned = tonumber(r.assigned_id) > 0 and { id = tonumber(r.assigned_id), name = r.assigned_name } or nil,
        hasLocation = (tonumber(r.pos_x) or 0) ~= 0 or (tonumber(r.pos_y) or 0) ~= 0,
        createdAt = tonumber(r.created_at),
        updatedAt = tonumber(r.updated_at),
    }
end

local function notifyOfficers(key, vars)
    local mode = cfg().NotifyOfficers or "onduty"
    if mode == "none" then return end
    local targets = mode == "all" and Officers.militarySources() or Officers.onDutySources()
    for _, src in ipairs(targets) do
        local uid = P.bySource[src]
        if uid and Gov.has(Gov.cached(uid), "reports") then
            Evora.notify(src, key, vars, "warning", 8)
            TriggerClientEvent("evora_police:ipad:push", src, "reports", {})
        end
    end
end

-- Creates a report. Returns the report id or nil, error.
function Reports.create(reporterId, reporterSrc, targetId, reason)
    if not Evora.feature("CitizenReport") then return nil, L("err_feature_disabled") end
    local c = cfg()
    local now = Evora.now()
    local last = Reports.lastByReporter[reporterId]
    if last and now - last < (c.Cooldown or 60) then
        return nil, L("report_cooldown", { seconds = (c.Cooldown or 60) - (now - last) })
    end
    targetId = Utils.toInt(targetId)
    if not targetId or not P.exists(targetId) then return nil, L("err_unknown_id") end
    if targetId == reporterId and not c.AllowSelfReport then return nil, L("report_self") end
    reason = Utils.sanitize(reason or "", c.MaxReasonLength or 250)
    if reason == "" then return nil, L("report_reason_required") end
    local open = tonumber(DB.scalar("SELECT COUNT(*) AS c FROM evora_police_reports WHERE reporter_id = ? AND status IN ('new', 'claimed', 'processing')", { reporterId })) or 0
    if open >= (c.MaxOpenPerReporter or 3) then return nil, L("report_too_many") end

    local pos = { x = 0.0, y = 0.0, z = 0.0 }
    if c.StoreLocation then pos = P.coords(reporterSrc) or pos end
    local reporterName, targetName = P.name(reporterId), P.name(targetId)
    local id = DB.insert(
        "INSERT INTO evora_police_reports (reporter_id, reporter_name, target_id, target_name, reason, status, pos_x, pos_y, pos_z, created_at, updated_at) VALUES (?, ?, ?, ?, ?, 'new', ?, ?, ?, ?, ?)",
        { reporterId, reporterName, targetId, targetName, reason, pos.x, pos.y, pos.z, now, now }
    )
    if not id then return nil, L("err_internal") end
    Reports.lastByReporter[reporterId] = now

    notifyOfficers("report_new_officers", { id = id, target = targetName, target_id = targetId, reason = reason })
    Logs.add("reports", "report_create", {
        actor = reporterId, target = targetId, actorName = reporterName, targetName = targetName,
        actorLabel = L("log_field_reporter"), targetLabel = L("log_field_reported"),
        fields = { { L("log_field_report"), "#" .. id, true } }, description = reason,
    })
    return id
end

-- Builder Menu flow: "إبلاغ عن مجرم" (available to everyone).
function Reports.createFlow(source)
    local user_id = P.getUserId(source)
    if not user_id then return end
    if not Evora.feature("CitizenReport") then return Evora.notify(source, "err_feature_disabled", nil, "error") end
    local values = Evora.Integrations.Popup.input(source, L("report_title"), {
        { key = "id", label = L("field_target_id"), type = "number", min = 1 },
        { key = "reason", label = L("field_reason"), type = "textarea", max = cfg().MaxReasonLength or 250 },
    })
    if not values then return Evora.notify(source, "action_cancelled", nil, "info") end
    local id, err = Reports.create(user_id, source, values.id, values.reason)
    if not id then return Evora.notify(source, err, nil, "error") end
    Evora.notify(source, "report_sent", { id = id }, "success")
end

---------------------------------------------------------------------------
-- iPad
---------------------------------------------------------------------------
RPC.register("reports:list", { feature = "Reports", perm = "reports", duty = "reports" }, function(ctx, data)
    local status = RPC.oneOf(data.status, STATUSES)
    local limit = cfg().ListLimit or 100
    local rows
    if status then
        rows = DB.query("SELECT * FROM evora_police_reports WHERE status = ? ORDER BY id DESC LIMIT " .. limit, { status })
    else
        rows = DB.query("SELECT * FROM evora_police_reports WHERE status IN ('new', 'claimed', 'processing') ORDER BY id DESC LIMIT " .. limit)
    end
    local list = {}
    for _, r in ipairs(rows) do list[#list + 1] = row(r) end
    local counts = {}
    for _, r in ipairs(DB.query("SELECT status, COUNT(*) AS c FROM evora_police_reports GROUP BY status")) do
        counts[r.status] = tonumber(r.c) or 0
    end
    return { list = list, counts = counts, me = ctx.user_id }
end)

RPC.register("reports:claim", { feature = "Reports", perm = "reports", duty = "reports", cooldown = 800 }, function(ctx, data)
    local id = RPC.int(data.id, 1)
    if not id then return nil, L("err_invalid_request") end
    local now = Evora.now()
    local changed = DB.execute(
        "UPDATE evora_police_reports SET status = 'claimed', assigned_id = ?, assigned_name = ?, updated_at = ? WHERE id = ? AND status = 'new'",
        { ctx.user_id, ctx.name, now, id }
    )
    if changed < 1 then return nil, L("report_already_claimed") end
    local r = DB.single("SELECT * FROM evora_police_reports WHERE id = ?", { id })
    Logs.add("reports", "report_claim", { actor = ctx.user_id, fields = { { L("log_field_report"), "#" .. id, true } } })
    if r and cfg().NotifyReporterOnClaim then
        local reporterSrc = P.getSource(tonumber(r.reporter_id))
        if reporterSrc then Evora.notify(reporterSrc, "report_claimed_reporter", { id = id, officer = ctx.name }, "success") end
    end
    return row(r)
end)

RPC.register("reports:setStatus", { feature = "Reports", perm = "reports", duty = "reports", cooldown = 800 }, function(ctx, data)
    local id = RPC.int(data.id, 1)
    local status = RPC.oneOf(data.status, { "processing", "closed", "cancelled" })
    if not id or not status then return nil, L("err_invalid_request") end
    local r = DB.single("SELECT * FROM evora_police_reports WHERE id = ?", { id })
    if not r then return nil, L("report_not_found") end
    local assignedToMe = tonumber(r.assigned_id) == ctx.user_id
    if not assignedToMe and not Gov.has(ctx.profile, "affairs") then return nil, L("report_not_assigned") end
    if not (TRANSITIONS[r.status] and TRANSITIONS[r.status][status]) then return nil, L("report_bad_transition") end
    local changed = DB.execute("UPDATE evora_police_reports SET status = ?, updated_at = ? WHERE id = ? AND status = ?",
        { status, Evora.now(), id, r.status })
    if changed < 1 then return nil, L("report_bad_transition") end
    if status == "closed" and tonumber(r.assigned_id) > 0 then
        Officers.increment(tonumber(r.assigned_id), "reports_handled", 1)
    end
    Logs.add("reports", "report_" .. status, { actor = ctx.user_id, fields = { { L("log_field_report"), "#" .. id, true } } })
    r.status = status
    return row(r)
end)

RPC.register("reports:waypoint", { feature = "Reports", perm = "reports" }, function(ctx, data)
    local id = RPC.int(data.id, 1)
    local r = id and DB.single("SELECT pos_x, pos_y FROM evora_police_reports WHERE id = ?", { id })
    if not r or ((tonumber(r.pos_x) or 0) == 0 and (tonumber(r.pos_y) or 0) == 0) then return nil, L("report_no_location") end
    TriggerClientEvent("evora_police:waypoint", ctx.source, tonumber(r.pos_x), tonumber(r.pos_y))
    return true
end)
