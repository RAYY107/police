--[[
    Evora_Police — statistics: ONE combined Top 10 (attendance + issued fines)

    score = attendance hours × Weights.attendanceHour + issued fines × Weights.fine
    Only officers inside the viewer's "statistics" scope are ranked.
]]

local Stats = {}
Evora.Stats = Stats

local DB, P, Gov, Officers = Evora.DB, Evora.Players, Evora.Gov, Evora.Officers

local function visible(profile, uid, groups)
    if uid == profile.user_id then return profile.isMilitary end
    local resolved = Gov.resolve(groups)
    return resolved.primary ~= nil and Gov.canOnRank(profile, "statistics", resolved.primary)
end

function Stats.top(profile)
    local cfg = Config.Statistics or {}
    local w = cfg.Weights or { attendanceHour = 1, fine = 0.5 }
    local list = {}
    for _, row in ipairs(DB.query("SELECT user_id, name, rank_group, sector, groups_json, attendance_total, fines_issued FROM evora_police_officers WHERE active = 1")) do
        local uid = tonumber(row.user_id)
        local groups = Officers.decodeGroups(row.groups_json)
        if visible(profile, uid, groups) then
            local attendance = (tonumber(row.attendance_total) or 0) + Officers.sessionSeconds(uid)
            local fines = tonumber(row.fines_issued) or 0
            local resolved = Gov.resolve(groups)
            list[#list + 1] = {
                user_id = uid,
                name = (row.name and row.name ~= "") and row.name or P.name(uid),
                rank = resolved.primary and Gov.rankLabel(resolved.primary.group) or "",
                sectorLabel = resolved.memberSector and Gov.sectorLabel(resolved.memberSector)
                    or (resolved.primary and Gov.describeRank(resolved.primary).ministryLabel) or "",
                attendance = attendance,
                fines = fines,
                score = Utils.round((attendance / 3600) * (w.attendanceHour or 1) + fines * (w.fine or 0.5), 2),
            }
        end
    end
    table.sort(list, function(a, b)
        if a.score ~= b.score then return a.score > b.score end
        if a.attendance ~= b.attendance then return a.attendance > b.attendance end
        return a.fines > b.fines
    end)
    local top = {}
    for i = 1, math.min(cfg.Top or 10, #list) do
        list[i].position = i
        top[i] = list[i]
    end
    return top
end

function Stats.sendWebhook(actorId, top)
    local fields = {}
    for _, o in ipairs(top) do
        fields[#fields + 1] = {
            name = ("#%d • %s | ID: %d"):format(o.position, Evora.Logs.discordSafe(o.name), o.user_id),
            value = L("top_webhook_row", {
                sector = o.sectorLabel ~= "" and o.sectorLabel or "-",
                attendance = Utils.humanDuration(o.attendance),
                fines = o.fines,
            }),
            inline = false,
        }
    end
    Evora.Logs.webhook("statistics", {
        title = L("top_webhook_title", { count = #top }),
        description = #top == 0 and L("top_empty") or L("top_webhook_by", { name = Evora.Logs.who(actorId) }),
        fields = fields,
    })
    Evora.Logs.add("statistics", "top_report", { actor = actorId, fields = { { L("log_field_count"), #top } } })
end

Evora.RPC.register("affairs:top", { feature = "Affairs", perm = "statistics" }, function(ctx)
    return Stats.top(ctx.profile)
end)

Evora.RPC.register("affairs:topWebhook", { feature = "Affairs", perm = "statistics",
    cooldown = ((Config.Statistics and Config.Statistics.WebhookCooldown) or 60) * 1000 }, function(ctx)
    Stats.sendWebhook(ctx.user_id, Stats.top(ctx.profile))
    return true
end)
