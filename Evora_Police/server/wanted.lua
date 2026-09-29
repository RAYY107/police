--[[
    Evora_Police — wanted persons (تعميم بلاغ → مطلوبين الدولة)
]]

local Wanted = {}
Evora.Wanted = Wanted

local DB, P, Gov, Logs, Officers, RPC = Evora.DB, Evora.Players, Evora.Gov, Evora.Logs, Evora.Officers, Evora.RPC

local function cfg() return Config.Wanted or {} end

function Wanted.getActive(target_id)
    return DB.single("SELECT * FROM evora_police_wanted WHERE target_id = ? AND active = 1 ORDER BY id DESC LIMIT 1", { target_id })
end

local function entry(r)
    local uid = tonumber(r.target_id)
    local job = r.target_job
    if P.isOnline(uid) then job = Evora.Integrations.Job.get(uid) end
    return {
        id = tonumber(r.id),
        target = { id = uid, name = r.target_name, online = P.isOnline(uid) },
        job = job ~= "" and job or "—",
        reason = r.reason,
        createdBy = { id = tonumber(r.created_by_id), name = r.created_by_name },
        createdAt = tonumber(r.created_at),
    }
end

function Wanted.create(officerId, officerSrc, targetId, reason)
    targetId = Utils.toInt(targetId)
    if not targetId or not P.exists(targetId) then return nil, L("err_unknown_id") end
    reason = Utils.sanitize(reason or "", cfg().MaxReasonLength or 250)
    if reason == "" then return nil, L("wanted_reason_required") end
    if Wanted.getActive(targetId) then return nil, L("wanted_exists") end
    local now = Evora.now()
    local targetName = P.name(targetId)
    local job = Evora.Integrations.Job.get(targetId)
    local id = DB.insert(
        "INSERT INTO evora_police_wanted (target_id, target_name, target_job, reason, created_by_id, created_by_name, created_at, active) VALUES (?, ?, ?, ?, ?, ?, ?, 1)",
        { targetId, targetName, job, reason, officerId, P.name(officerId), now }
    )
    if not id then return nil, L("err_internal") end

    local audience = cfg().NotifyOfficers == "all" and Officers.militarySources() or Officers.onDutySources()
    local alert = {
        id = id, name = targetName, user_id = targetId, reason = reason, officer = P.name(officerId),
        quickOpen = cfg().QuickOpen,
    }
    for _, src in ipairs(audience) do
        Evora.notify(src, "wanted_alert", { name = targetName, id = targetId, reason = reason }, "warning", 10)
        TriggerClientEvent("evora_police:wanted:alert", src, alert)
    end
    Logs.add("wanted", "wanted_create", {
        actor = officerId, target = targetId, targetName = targetName,
        fields = { { L("log_field_job"), job, true } }, description = reason,
    })
    return id
end

-- Builder Menu flow: "تعميم بلاغ"
function Wanted.createFlow(source)
    local user_id = P.getUserId(source)
    if not user_id then return end
    local profile = Gov.getProfile(user_id, true)
    if not Evora.feature("Wanted") or not Gov.has(profile, "wanted") then return Evora.notify(source, "err_no_permission", nil, "error") end
    if not Officers.dutyOk(user_id, "wanted") then return Evora.notify(source, "err_not_on_duty", nil, "error") end
    local values = Evora.Integrations.Popup.input(source, L("wanted_title"), {
        { key = "id", label = L("field_target_id"), type = "number", min = 1 },
        { key = "reason", label = L("field_reason"), type = "textarea", max = cfg().MaxReasonLength or 250 },
    })
    if not values then return Evora.notify(source, "action_cancelled", nil, "info") end
    profile = Gov.getProfile(user_id, true)
    if not Gov.has(profile, "wanted") then return Evora.notify(source, "err_no_permission", nil, "error") end
    local id, err = Wanted.create(user_id, source, values.id, values.reason)
    if not id then return Evora.notify(source, err, nil, "error") end
    Evora.notify(source, "wanted_created", { id = values.id }, "success")
end

function Wanted.clear(wantedId, byId, reasonKey)
    local r = DB.single("SELECT * FROM evora_police_wanted WHERE id = ? AND active = 1", { wantedId })
    if not r then return nil, L("wanted_not_found") end
    DB.execute("UPDATE evora_police_wanted SET active = 0, cleared_by_id = ?, cleared_by_name = ?, cleared_at = ? WHERE id = ?",
        { byId or 0, byId and byId > 0 and P.name(byId) or "", Evora.now(), wantedId })
    Logs.add("wanted", "wanted_clear", {
        actor = byId, target = tonumber(r.target_id), targetName = r.target_name,
        fields = { { L("log_field_reason"), L(reasonKey or "wanted_clear_manual") } },
    })
    return true
end

function Wanted.clearForTarget(targetId, byId, reasonKey)
    local r = Wanted.getActive(targetId)
    if r then Wanted.clear(tonumber(r.id), byId, reasonKey) end
end

RPC.register("wanted:list", { feature = "Wanted", perm = "ipad" }, function()
    local list = {}
    for _, r in ipairs(DB.query("SELECT * FROM evora_police_wanted WHERE active = 1 ORDER BY id DESC LIMIT " .. (cfg().ListLimit or 100))) do
        list[#list + 1] = entry(r)
    end
    return list
end)

RPC.register("wanted:clear", { feature = "Wanted", perm = "wantedClear", cooldown = 800 }, function(ctx, data)
    local id = RPC.int(data.id, 1)
    if not id then return nil, L("err_invalid_request") end
    local ok, err = Wanted.clear(id, ctx.user_id, "wanted_clear_manual")
    if not ok then return nil, err end
    return true
end)
