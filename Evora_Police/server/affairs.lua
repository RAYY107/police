--[[
    Evora_Police — الشؤون (administrative control centre)

    Every action resolves the administrator's live profile and checks that the target officer
    is inside the administrator's scope for that specific permission. Lists sent to the UI only
    contain officers inside that scope.
]]

local Affairs = { recalls = {} }
Evora.Affairs = Affairs

local DB, P, Gov, Logs, Officers, Confirm, RPC = Evora.DB, Evora.Players, Evora.Gov, Evora.Logs, Evora.Officers, Evora.Confirm, Evora.RPC
local Vacation = Evora.Vacation

local function decode(raw)
    local ok, list = pcall(json.decode, raw or "[]")
    return ok and type(list) == "table" and list or {}
end

local function contains(list, value)
    for _, v in ipairs(list) do if v == value then return true end end
    return false
end

---------------------------------------------------------------------------
-- Targets
---------------------------------------------------------------------------
-- Loads everything needed to judge an officer: live groups when online, the saved groups of a
-- vacation, or the stored groups of an offline record.
function Affairs.loadTarget(user_id)
    user_id = Utils.toInt(user_id)
    if not user_id or user_id < 1 then return nil end
    local record = Officers.get(user_id)
    local src = P.getSource(user_id)
    local vacation = Vacation.get(user_id)
    local groups = {}
    if src then groups = Gov.militaryGroups(Gov.getProfile(user_id, true).groups) end
    if #groups == 0 then
        if vacation then
            groups = decode(vacation.original_groups)
        elseif not src and record and tonumber(record.active) == 1 then
            groups = Officers.decodeGroups(record.groups_json)
        end
    end
    return {
        user_id = user_id, name = P.name(user_id), source = src, online = src ~= nil,
        groups = groups, record = record, vacation = vacation,
    }
end

local function inScope(ctx, perm, target)
    if not target or #target.groups == 0 then return nil, L("affairs_not_officer") end
    if target.user_id == ctx.user_id and not (Config.Hierarchy and Config.Hierarchy.AllowSelfManagement) then
        return nil, L("affairs_self")
    end
    if not Gov.canOnTarget(ctx.profile, perm, target.groups, target.user_id) then
        Evora.debug("permissions", "%d out of scope for %s on %d", ctx.user_id, perm, target.user_id)
        return nil, L("err_out_of_scope")
    end
    return true
end
Affairs.inScope = inScope

local function describeTarget(target)
    local resolved = Gov.resolve(target.groups)
    local d = resolved.primary and Gov.describeRank(resolved.primary) or {}
    return {
        user_id = target.user_id,
        name = target.name,
        rank = d.label or "",
        sectorLabel = resolved.memberSector and Gov.sectorLabel(resolved.memberSector) or d.sectorLabel or "",
        ministryLabel = d.ministryLabel or "",
        online = target.online,
        onDuty = Officers.isOnDuty(target.user_id),
        vacation = target.vacation ~= nil,
        order = resolved.primary and resolved.primary.global or 9999,
    }
end

-- Officers (online + stored + on vacation) inside the scope of `perm`.
function Affairs.officersInScope(profile, perm, query, onlineOnly)
    local seen, list = {}, {}
    query = Utils.trim(tostring(query or "")):lower()
    local function consider(uid, groups, row)
        if seen[uid] then return end
        seen[uid] = true
        if #groups == 0 then return end
        if uid == profile.user_id and not (Config.Hierarchy and Config.Hierarchy.AllowSelfManagement) then return end
        if not Gov.canOnTarget(profile, perm, groups, uid) then return end
        local src = P.getSource(uid)
        if onlineOnly and not src then return end
        local entry = describeTarget({
            user_id = uid, name = row and row.name ~= "" and row.name or P.name(uid), online = src ~= nil,
            groups = groups, vacation = Vacation.get(uid),
        })
        if query ~= "" and tostring(uid) ~= query and not entry.name:lower():find(query, 1, true) then return end
        list[#list + 1] = entry
    end
    for uid in pairs(P.byUser) do
        local prof = Gov.cached(uid)
        if prof.isMilitary then consider(uid, Gov.militaryGroups(prof.groups)) end
    end
    for uid, vac in pairs(Vacation.active) do consider(uid, decode(vac.original_groups)) end
    if not onlineOnly then
        for _, row in ipairs(DB.query("SELECT user_id, name, groups_json FROM evora_police_officers WHERE active = 1")) do
            consider(tonumber(row.user_id), Officers.decodeGroups(row.groups_json), row)
        end
    end
    table.sort(list, function(a, b)
        if a.online ~= b.online then return a.online end
        if a.order ~= b.order then return a.order < b.order end
        return a.name < b.name
    end)
    while #list > 150 do table.remove(list) end
    return list
end

---------------------------------------------------------------------------
-- Overview
---------------------------------------------------------------------------
local TILES = {
    { id = "recruit", perms = { "recruit", "dismiss" } },
    { id = "broadcastOfficers", perms = { "broadcastOfficers" } },
    { id = "broadcastCitizens", perms = { "broadcastCitizens" } },
    { id = "recall", perms = { "recall" } },
    { id = "monitor", perms = { "monitor" } },
    { id = "vacationBalance", perms = { "vacationBalance" } },
    { id = "officerInquiry", perms = { "officerInquiry" } },
    { id = "resetAttendance", perms = { "resetAttendance" } },
    { id = "resetFines", perms = { "resetFines" } },
    { id = "resetData", perms = { "resetData" } },
    { id = "statistics", perms = { "statistics" } },
}

RPC.register("affairs:overview", { feature = "Affairs", perm = "affairs" }, function(ctx)
    local tiles = {}
    for _, tile in ipairs(TILES) do
        if Gov.hasAny(ctx.profile, tile.perms) then
            if not ((tile.id == "broadcastOfficers" and not Config.Broadcast.OfficerEnabled)
                or (tile.id == "broadcastCitizens" and not Config.Broadcast.CitizenEnabled)) then
                tiles[#tiles + 1] = tile.id
            end
        end
    end
    local sectors = {}
    for perm in pairs(Gov.SCOPED) do
        for id in pairs(Gov.sectorsFor(ctx.profile, perm)) do sectors[id] = true end
    end
    local sectorLabels = {}
    for _, s in ipairs(Gov.sectorList) do
        if sectors[s.id] then sectorLabels[#sectorLabels + 1] = s.label end
    end
    local total, online, onDuty = 0, 0, 0
    for _, row in ipairs(DB.query("SELECT user_id, sector FROM evora_police_officers WHERE active = 1")) do
        if sectors[row.sector] then
            total = total + 1
            local uid = tonumber(row.user_id)
            if P.isOnline(uid) then online = online + 1 end
            if Officers.isOnDuty(uid) then onDuty = onDuty + 1 end
        end
    end
    return {
        tiles = tiles,
        scope = sectorLabels,
        stats = {
            officers = total, online = online, onDuty = onDuty,
            reports = tonumber(DB.scalar("SELECT COUNT(*) AS c FROM evora_police_reports WHERE status IN ('new', 'claimed', 'processing')")) or 0,
            wanted = tonumber(DB.scalar("SELECT COUNT(*) AS c FROM evora_police_wanted WHERE active = 1")) or 0,
            prisoners = tonumber(DB.scalar("SELECT COUNT(*) AS c FROM evora_police_jail")) or 0,
        },
        resetData = Config.Reset.Data,
        broadcastMax = Config.Broadcast.MaxLength,
        vacationMax = Config.Vacation.MaxBalance,
    }
end)

RPC.register("affairs:officers", { feature = "Affairs", perm = "affairs" }, function(ctx, data)
    local perm = type(data.perm) == "string" and Gov.SCOPED[data.perm] and data.perm or nil
    if not perm then return nil, L("err_invalid_request") end
    if not Gov.has(ctx.profile, perm) then return nil, L("err_no_permission") end
    return Affairs.officersInScope(ctx.profile, perm, data.query, data.onlineOnly == true)
end)

---------------------------------------------------------------------------
-- Recruitment (توظيف)
---------------------------------------------------------------------------
RPC.register("affairs:ranks", { feature = "Affairs", perm = "recruit" }, function(ctx)
    return Gov.assignableRanks(ctx.profile)
end)

-- Online players for the recruitment picker (name / id search).
RPC.register("affairs:players", { feature = "Affairs", perm = "recruit" }, function(ctx, data)
    local query = Utils.trim(tostring(data.query or "")):lower()
    local list = {}
    for uid in pairs(P.byUser) do
        local name = P.name(uid)
        if query == "" or tostring(uid) == query or name:lower():find(query, 1, true) then
            local prof = Gov.cached(uid)
            list[#list + 1] = {
                user_id = uid, name = name,
                rank = prof.primary and Gov.rankLabel(prof.primary.group) or "",
                sectorLabel = prof.memberSector and Gov.sectorLabel(prof.memberSector) or "",
                vacation = Vacation.isOnVacation(uid),
            }
        end
    end
    table.sort(list, function(a, b) return a.user_id < b.user_id end)
    while #list > 60 do table.remove(list) end
    return list
end)

RPC.register("affairs:recruit", { feature = "Affairs", perm = "recruit", cooldown = 1500 }, function(ctx, data)
    local uid = RPC.int(data.user_id, 1)
    local group = type(data.rank) == "string" and data.rank or nil
    local rank = group and Gov.ranks[group]
    if not uid or not rank then return nil, L("err_invalid_request") end
    if uid == ctx.user_id and not Config.Hierarchy.AllowSelfManagement then return nil, L("affairs_self") end
    if not Gov.canOnRank(ctx.profile, "recruit", rank) then return nil, L("err_out_of_scope") end
    if not P.exists(uid) then return nil, L("err_unknown_id") end
    if Vacation.isOnVacation(uid) then return nil, L("affairs_target_on_vacation") end

    local target = Affairs.loadTarget(uid)
    if contains(target.groups, group) then return nil, L("affairs_already_rank") end

    local replaced = {}
    for _, g in ipairs(target.groups) do
        if g ~= group and Gov.canOnRank(ctx.profile, "recruit", g) then replaced[#replaced + 1] = g end
    end

    local ok, reason = Confirm.forAction("recruit", ctx.source, target.source, {
        title = L("confirm_recruit_title"),
        message = L("confirm_recruit_msg", { name = target.name, id = uid, rank = Gov.rankLabel(group) }),
        icon = "recruit",
    })
    if not ok then return nil, Confirm.failMessage(reason, Confirm.mode("recruit") == "self") end

    ctx.profile = Gov.getProfile(ctx.user_id, true)
    if not Gov.canOnRank(ctx.profile, "recruit", rank) then return nil, L("err_out_of_scope") end

    local online = P.isOnline(uid)
    for _, g in ipairs(replaced) do Officers.setGroup(uid, g, false) end
    Officers.setGroup(uid, group, true)
    if online then
        local profile = Gov.getProfile(uid, true)
        Officers.sync(uid, profile)
    else
        local groups = {}
        for _, g in ipairs(target.groups) do
            if not contains(replaced, g) then groups[#groups + 1] = g end
        end
        groups[#groups + 1] = group
        Officers.storeGroups(uid, groups)
    end

    local d = Gov.describeRank(rank)
    Logs.add("recruitment", "recruit", {
        actor = ctx.user_id, target = uid,
        fields = {
            { L("log_field_rank"), d.label, true },
            { L("log_field_sector"), d.sectorLabel ~= "" and d.sectorLabel or d.ministryLabel, true },
            { L("log_field_replaced"), #replaced > 0 and table.concat(replaced, ", ") or "-" },
            { L("log_field_online"), online and L("yes") or L("no"), true },
        },
    })
    if online then
        Evora.notify(P.getSource(uid), "recruit_target", { rank = d.label, sector = d.sectorLabel ~= "" and d.sectorLabel or d.ministryLabel }, "success")
    end
    return { online = online, rank = d.label }
end)

---------------------------------------------------------------------------
-- Dismissal (فصل)
---------------------------------------------------------------------------
RPC.register("affairs:dismiss", { feature = "Affairs", perm = "dismiss", cooldown = 1500 }, function(ctx, data)
    local target = Affairs.loadTarget(data.user_id)
    local ok, err = inScope(ctx, "dismiss", target)
    if not ok then return nil, err end
    local toRemove = Gov.coveredRanks(ctx.profile, "dismiss", target.groups)
    if #toRemove == 0 then return nil, L("err_out_of_scope") end

    local d = describeTarget(target)
    local accepted, reason = Confirm.forAction("dismiss", ctx.source, target.source, {
        title = L("confirm_dismiss_title"),
        message = L("confirm_dismiss_msg", { name = target.name, id = target.user_id }),
        details = { { L("log_field_rank"), d.rank }, { L("log_field_sector"), d.sectorLabel } },
        icon = "dismiss",
    })
    if not accepted then return nil, Confirm.failMessage(reason, Confirm.mode("dismiss") == "self") end

    -- Re-validate after the confirmation wait.
    ctx.profile = Gov.getProfile(ctx.user_id, true)
    target = Affairs.loadTarget(target.user_id)
    ok, err = inScope(ctx, "dismiss", target)
    if not ok then return nil, err end
    toRemove = Gov.coveredRanks(ctx.profile, "dismiss", target.groups)
    if #toRemove == 0 then return nil, L("err_out_of_scope") end

    local remaining = {}
    for _, g in ipairs(target.groups) do
        if not contains(toRemove, g) then remaining[#remaining + 1] = g end
    end

    if target.vacation then
        if #remaining == 0 then
            Vacation.finish(target.user_id, "cancelled", ctx.user_id)
        else
            DB.execute("UPDATE evora_police_vacations SET original_groups = ? WHERE id = ?", { json.encode(remaining), target.vacation.id })
            target.vacation.original_groups = json.encode(remaining)
        end
        if not target.online then Officers.storeGroups(target.user_id, remaining) end
    else
        for _, g in ipairs(toRemove) do Officers.setGroup(target.user_id, g, false) end
        if target.online then
            Gov.getProfile(target.user_id, true)
        else
            Officers.storeGroups(target.user_id, remaining)
        end
    end

    if #remaining == 0 then
        if Officers.isOnDuty(target.user_id) then Officers.clockOut(target.user_id, "dismissed") end
        Officers.deactivate(target.user_id)
    end

    Logs.add("recruitment", "dismiss", {
        actor = ctx.user_id, target = target.user_id,
        fields = {
            { L("log_field_removed"), table.concat(toRemove, ", ") },
            { L("log_field_online"), target.online and L("yes") or L("no"), true },
        },
    })
    if target.online then Evora.notify(target.source, "dismiss_target", { rank = d.rank }, "error") end
    return { removed = toRemove, online = target.online }
end)

---------------------------------------------------------------------------
-- Broadcasts (تعميم على العساكر / المواطنين)
---------------------------------------------------------------------------
function Affairs.broadcast(audience, message, senderId)
    local b = Config.Broadcast
    local profile = Gov.getProfile(senderId)
    local summary = Gov.summary(profile)
    local payload = {
        kind = audience,
        title = audience == "officers" and b.OfficerTitle or b.CitizenTitle,
        message = message,
        sender = b.ShowSender and (P.name(senderId) .. (summary.rank ~= "" and (" — " .. summary.rank) or "")) or nil,
        duration = b.Duration,
        style = b.Style,
        sound = b.Sound,
    }
    if audience == "citizens" then
        TriggerClientEvent("evora_police:ui", -1, "broadcast", payload)
        return -1
    end
    local targets
    if b.OfficerAudience == "onduty" then
        targets = Officers.onDutySources()
    elseif b.OfficerAudience == "scope" then
        targets = {}
        for uid, src in pairs(P.byUser) do
            local prof = Gov.cached(uid)
            if prof.isMilitary and (uid == senderId or Gov.canOnTarget(profile, "broadcastOfficers", Gov.militaryGroups(prof.groups), uid)) then
                targets[#targets + 1] = src
            end
        end
    else
        targets = Officers.militarySources()
    end
    for _, src in ipairs(targets) do TriggerClientEvent("evora_police:ui", src, "broadcast", payload) end
    return #targets
end

RPC.register("affairs:broadcast", { feature = "Affairs", perm = { "broadcastOfficers", "broadcastCitizens" } }, function(ctx, data)
    local audience = RPC.oneOf(data.audience, { "officers", "citizens" })
    if not audience then return nil, L("err_invalid_request") end
    local perm = audience == "officers" and "broadcastOfficers" or "broadcastCitizens"
    if not Gov.has(ctx.profile, perm) then return nil, L("err_no_permission") end
    if (audience == "officers" and not Config.Broadcast.OfficerEnabled) or (audience == "citizens" and not Config.Broadcast.CitizenEnabled) then
        return nil, L("err_feature_disabled")
    end
    local message = RPC.text(data.message, Config.Broadcast.MaxLength, true)
    if not message then return nil, L("broadcast_empty") end
    local cooldowns = Affairs.broadcastCooldowns or {}
    Affairs.broadcastCooldowns = cooldowns
    local now = Evora.now()
    if cooldowns[ctx.user_id] and now - cooldowns[ctx.user_id] < (Config.Broadcast.Cooldown or 30) then
        return nil, L("err_cooldown")
    end
    cooldowns[ctx.user_id] = now
    local count = Affairs.broadcast(audience, message, ctx.user_id)
    Logs.add("affairs", audience == "officers" and "broadcast_officers" or "broadcast_citizens", {
        actor = ctx.user_id, description = message,
    })
    return { sent = count }
end)

---------------------------------------------------------------------------
-- Officer recall (سحب العساكر)
---------------------------------------------------------------------------
local function recallSnapshot(recall)
    local list, counts = {}, { accepted = 0, rejected = 0, pending = 0, timeout = 0 }
    for _, r in pairs(recall.results) do
        list[#list + 1] = { user_id = r.user_id, name = r.name, rank = r.rank, status = r.status }
        counts[r.status] = (counts[r.status] or 0) + 1
    end
    table.sort(list, function(a, b) return a.user_id < b.user_id end)
    return { id = recall.id, results = list, counts = counts, done = counts.pending == 0 }
end

RPC.register("affairs:recall", { feature = "Affairs", perm = "recall" }, function(ctx, data)
    local cfgRecall = Config.Recall
    local existing = Affairs.recalls[ctx.user_id]
    if existing and Evora.now() - existing.startedAt < (cfgRecall.Cooldown or 120) then return nil, L("err_cooldown") end
    local message = RPC.text(data.message, 200) or cfgRecall.DefaultMessage

    local officers = {}
    for uid, src in pairs(P.byUser) do
        local prof = Gov.cached(uid)
        if uid ~= ctx.user_id and prof.isMilitary and (cfgRecall.IncludeOffDuty or Officers.isOnDuty(uid))
            and Gov.canOnTarget(ctx.profile, "recall", Gov.militaryGroups(prof.groups), uid) then
            officers[#officers + 1] = { user_id = uid, source = src, profile = prof }
        end
    end
    if #officers == 0 then return nil, L("recall_none") end

    local callerCoords = P.coords(ctx.source)
    local recall = { id = Evora.now(), startedAt = Evora.now(), results = {} }
    Affairs.recalls[ctx.user_id] = recall
    for _, o in ipairs(officers) do
        recall.results[o.user_id] = {
            user_id = o.user_id, name = P.name(o.user_id), rank = Gov.summary(o.profile).rank, status = "pending",
        }
    end

    local adminName = ctx.name
    local adminSource = ctx.source
    local remaining = #officers
    for _, o in ipairs(officers) do
        Evora.thread(function()
            local accepted, reason = Evora.Confirm.ask(o.source, {
                title = L("recall_title"),
                message = message,
                details = { { L("recall_from"), adminName .. " | ID: " .. ctx.user_id } },
                timeout = cfgRecall.Timeout,
                icon = "recall",
            })
            local entry = recall.results[o.user_id]
            entry.status = accepted and "accepted" or (reason == "timeout" and "timeout" or "rejected")
            if accepted then
                local point = cfgRecall.Waypoint == "hq" and cfgRecall.HQ or (cfgRecall.Waypoint == "caller" and callerCoords) or nil
                if point then TriggerClientEvent("evora_police:waypoint", o.source, point.x, point.y) end
                if cfgRecall.AutoClockIn and not Officers.isOnDuty(o.user_id) then
                    Officers.clockIn(o.user_id, o.source, Gov.getProfile(o.user_id, true))
                end
            end
            remaining = remaining - 1
            if GetPlayerName(adminSource) then
                TriggerClientEvent("evora_police:ipad:push", adminSource, "recall", recallSnapshot(recall))
                if remaining == 0 then
                    local snap = recallSnapshot(recall)
                    Evora.notify(adminSource, "recall_done", {
                        accepted = snap.counts.accepted, rejected = snap.counts.rejected, timeout = snap.counts.timeout,
                    }, "info", 10)
                end
            end
            if remaining == 0 then
                local snap = recallSnapshot(recall)
                Logs.add("affairs", "recall", {
                    actor = ctx.user_id, description = message,
                    fields = {
                        { L("recall_accepted"), snap.counts.accepted, true },
                        { L("recall_rejected"), snap.counts.rejected, true },
                        { L("recall_timeout"), snap.counts.timeout, true },
                    },
                })
            end
        end)
    end
    return recallSnapshot(recall)
end)

---------------------------------------------------------------------------
-- Monitoring (مراقبة العساكر)
---------------------------------------------------------------------------
RPC.register("affairs:monitor", { feature = "Affairs", perm = "monitor" }, function(ctx, data)
    local target = Affairs.loadTarget(data.user_id)
    local ok, err = inScope(ctx, "monitor", target)
    if not ok then return nil, err end
    if not target.online then return nil, L("err_target_offline") end
    local started, startErr = Evora.Spectate.start(ctx.source, target.source, "officer")
    if not started then return nil, startErr end
    return true
end)

---------------------------------------------------------------------------
-- Vacation balance / break
---------------------------------------------------------------------------
RPC.register("affairs:vacationBalance", { feature = "Affairs", perm = "vacationBalance", cooldown = 1000 }, function(ctx, data)
    local days = RPC.int(data.days, 1, Config.Vacation.MaxBalance or 60)
    if not days then return nil, L("vacation_invalid_days") end
    local target = Affairs.loadTarget(data.user_id)
    local ok, err = inScope(ctx, "vacationBalance", target)
    if not ok then return nil, err end
    if not target.record then
        if target.online then Officers.sync(target.user_id, Gov.getProfile(target.user_id, true)) else Officers.storeGroups(target.user_id, target.groups) end
    end
    DB.execute("UPDATE evora_police_officers SET vacation_balance = LEAST(vacation_balance + ?, ?) WHERE user_id = ?",
        { days, Config.Vacation.MaxBalance or 60, target.user_id })
    Logs.add("affairs", "vacation_balance", { actor = ctx.user_id, target = target.user_id, fields = { { L("log_field_days"), days } } })
    if target.online then Evora.notify(target.source, "vacation_balance_added", { days = days }, "success") end
    local balance = DB.scalar("SELECT vacation_balance FROM evora_police_officers WHERE user_id = ?", { target.user_id })
    return { balance = tonumber(balance) or 0 }
end)

RPC.register("affairs:vacationBreak", { feature = "Affairs", perm = "vacationBreak", cooldown = 1000 }, function(ctx, data)
    local target = Affairs.loadTarget(data.user_id)
    local ok, err = inScope(ctx, "vacationBreak", target)
    if not ok then return nil, err end
    if not target.vacation then return nil, L("vacation_none") end
    local accepted, reason = Confirm.forAction("vacationBreak", ctx.source, target.source, {
        title = L("confirm_vacation_break_title"),
        message = L("confirm_vacation_break_msg", { name = target.name, id = target.user_id }),
        icon = "vacation",
    })
    if not accepted then return nil, Confirm.failMessage(reason, Confirm.mode("vacationBreak") == "self") end
    local done, finishErr = Vacation.finish(target.user_id, "broken", ctx.user_id)
    if not done then return nil, finishErr end
    return true
end)

---------------------------------------------------------------------------
-- Officer inquiry (استعلام عن عسكري)
---------------------------------------------------------------------------
function Affairs.details(ctx, target)
    local record = target.record or Officers.get(target.user_id) or {}
    local d = describeTarget(target)
    local session = Officers.sessionSeconds(target.user_id)
    local vac = target.vacation
    local function can(perm) return Gov.canOnTarget(ctx.profile, perm, target.groups, target.user_id) end
    return {
        user_id = target.user_id,
        name = target.name,
        avatar = Evora.Integrations.ProfileImage.get(target.user_id),
        rank = d.rank,
        sectorLabel = d.sectorLabel,
        ministryLabel = d.ministryLabel,
        online = target.online,
        onDuty = d.onDuty,
        code = record.military_code or "",
        attendance = (tonumber(record.attendance_total) or 0) + session,
        session = session,
        fines = tonumber(record.fines_issued) or 0,
        jails = tonumber(record.jails_issued) or 0,
        reports = tonumber(record.reports_handled) or 0,
        impounds = tonumber(record.impounds_issued) or 0,
        vacationBalance = tonumber(record.vacation_balance) or 0,
        vacation = vac and { active = true, endsAt = tonumber(vac.end_at), days = tonumber(vac.days) } or { active = false },
        lastClockIn = tonumber(record.last_clock_in) or 0,
        lastClockOut = tonumber(record.last_clock_out) or 0,
        actions = {
            dismiss = can("dismiss"),
            monitor = can("monitor") and target.online,
            vacationBalance = can("vacationBalance"),
            vacationBreak = can("vacationBreak") and vac ~= nil,
            resetAttendance = can("resetAttendance"),
            resetFines = can("resetFines"),
            resetData = can("resetData"),
        },
    }
end

RPC.register("affairs:officer", { feature = "Affairs", perm = "officerInquiry" }, function(ctx, data)
    local target = Affairs.loadTarget(data.user_id)
    local ok, err = inScope(ctx, "officerInquiry", target)
    if not ok then return nil, err end
    return Affairs.details(ctx, target)
end)

---------------------------------------------------------------------------
-- Resets (تصفير)
---------------------------------------------------------------------------
local RESETS = {
    attendance = { perm = "resetAttendance", action = "resetAttendance", log = "reset_attendance" },
    fines = { perm = "resetFines", action = "resetFines", log = "reset_fines" },
    data = { perm = "resetData", action = "resetData", log = "reset_data" },
}

function Affairs.applyReset(user_id, kind)
    local now = Evora.now()
    local function restartSession()
        local duty = Officers.duty[user_id]
        if duty then
            duty.startedAt = now
            DB.execute("UPDATE evora_police_officers SET duty_started_at = ?, duty_last_seen = ? WHERE user_id = ?", { now, now, user_id })
        end
    end
    if kind == "attendance" then
        DB.execute("UPDATE evora_police_officers SET attendance_total = 0 WHERE user_id = ?", { user_id })
        restartSession()
        return { "attendance" }
    elseif kind == "fines" then
        DB.execute("UPDATE evora_police_officers SET fines_issued = 0 WHERE user_id = ?", { user_id })
        return { "fines" }
    end
    local r = Config.Reset.Data or {}
    local sets, cleared = {}, {}
    if r.attendance then sets[#sets + 1] = "attendance_total = 0"; cleared[#cleared + 1] = "attendance"; restartSession() end
    if r.fines then sets[#sets + 1] = "fines_issued = 0"; cleared[#cleared + 1] = "fines" end
    if r.jails then sets[#sets + 1] = "jails_issued = 0"; cleared[#cleared + 1] = "jails" end
    if r.reports then sets[#sets + 1] = "reports_handled = 0"; cleared[#cleared + 1] = "reports" end
    if r.impounds then sets[#sets + 1] = "impounds_issued = 0"; cleared[#cleared + 1] = "impounds" end
    if r.militaryCode then sets[#sets + 1] = "military_code = ''"; cleared[#cleared + 1] = "militaryCode" end
    local params = {}
    if r.vacationBalance then
        sets[#sets + 1] = "vacation_balance = ?"
        params[#params + 1] = Config.Vacation.DefaultBalance or 0
        cleared[#cleared + 1] = "vacationBalance"
    end
    if #sets > 0 then
        params[#params + 1] = user_id
        DB.execute("UPDATE evora_police_officers SET " .. table.concat(sets, ", ") .. " WHERE user_id = ?", params)
    end
    if r.attendanceHistory then
        DB.execute("DELETE FROM evora_police_attendance WHERE user_id = ?", { user_id })
        cleared[#cleared + 1] = "attendanceHistory"
    end
    return cleared
end

RPC.register("affairs:reset", { feature = "Affairs", perm = { "resetAttendance", "resetFines", "resetData" }, cooldown = 1000 }, function(ctx, data)
    local def = RESETS[data.kind]
    if not def then return nil, L("err_invalid_request") end
    if not Gov.has(ctx.profile, def.perm) then return nil, L("err_no_permission") end
    local target = Affairs.loadTarget(data.user_id)
    local ok, err = inScope(ctx, def.perm, target)
    if not ok then return nil, err end
    if not target.record then return nil, L("affairs_no_record") end

    local accepted, reason = Confirm.forAction(def.action, ctx.source, target.source, {
        title = L("confirm_reset_title"),
        message = L("confirm_reset_" .. data.kind, { name = target.name, id = target.user_id }),
        icon = "reset",
    })
    if not accepted then return nil, Confirm.failMessage(reason, Confirm.mode(def.action) == "self") end

    ctx.profile = Gov.getProfile(ctx.user_id, true)
    ok, err = inScope(ctx, def.perm, Affairs.loadTarget(target.user_id))
    if not ok then return nil, err end

    local cleared = Affairs.applyReset(target.user_id, data.kind)
    Logs.add("affairs", def.log, {
        actor = ctx.user_id, target = target.user_id,
        fields = { { L("log_field_cleared"), table.concat(cleared, ", ") } },
    })
    if target.online then Evora.notify(target.source, "reset_target_" .. data.kind, nil, "info") end
    return { cleared = cleared }
end)
