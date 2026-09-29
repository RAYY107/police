--[[
    Evora_Police — jail (السجن)

    * Sentences require the target's confirmation (F5 / F6).
    * The remaining time lives on the server (1 s tick) and is persisted every PersistInterval.
    * Original clothing and cuff state are saved in the database BEFORE they are changed and are
      restored on release — also after a resource or server restart.
    * Escapes are detected server-side (OneSync) and only ever affect players marked as jailed.
    * Task rewards are validated on the server (position, duration, cooldown, caps).
]]

local Jail = { active = {}, tasks = {}, taskCooldowns = {} }
Evora.Jail = Jail

local DB, P, Gov, Logs, Officers, Confirm, Targets, RPC =
    Evora.DB, Evora.Players, Evora.Gov, Evora.Logs, Evora.Officers, Evora.Confirm, Evora.Targets, Evora.RPC
local I = Evora.Integrations

local function cfg() return Config.Jail or {} end

local function center() return cfg().Center or cfg().Entry end
local function returnPoint() return cfg().ReturnLocation or cfg().Entry end

function Jail.isJailed(user_id)
    local e = Jail.active[tonumber(user_id)]
    return e ~= nil and not e.pendingRelease
end

function Jail.findReason(id)
    for _, r in ipairs(cfg().Reasons or {}) do
        if r.id == id then return r end
    end
    return nil
end

function Jail.status(user_id)
    local e = Jail.active[tonumber(user_id)]
    if not e or e.pendingRelease then return { jailed = false } end
    return {
        jailed = true,
        user_id = e.user_id,
        name = P.name(e.user_id),
        remaining = e.remaining,
        total = e.total,
        reason = e.reason_label,
        officer = { id = e.officer_id, name = e.officer_name },
        jailName = cfg().Name,
        startedAt = e.started_at,
        online = P.isOnline(e.user_id),
    }
end

local function clientState(e)
    local tasks = {}
    if cfg().Tasks and cfg().Tasks.Enabled then
        for _, t in ipairs(cfg().Tasks.List or {}) do
            local typeDef = cfg().Tasks.Types and cfg().Tasks.Types[t.type] or {}
            tasks[#tasks + 1] = {
                id = t.id, label = t.label, coords = Utils.vec(t.coords), radius = t.radius or 2.0,
                typeLabel = typeDef.label or t.type, duration = t.duration, reduction = t.reduction,
            }
        end
    end
    return {
        name = cfg().Name,
        remaining = e.remaining,
        total = e.total,
        reason = e.reason_label,
        officer = e.officer_name,
        center = Utils.vec(center()),
        radius = cfg().Radius,
        escape = cfg().Escape and cfg().Escape.Enabled == true,
        hud = not cfg().Hud or cfg().Hud.Enabled ~= false,
        tasks = tasks,
    }
end

Jail.clientState = clientState

local function persist(e)
    DB.execute("UPDATE evora_police_jail SET remaining_seconds = ?, added_seconds = ?, reduced_seconds = ?, updated_at = ? WHERE user_id = ?",
        { math.max(0, e.remaining), e.added, e.reduced, Evora.now(), e.user_id })
    e.dirty = false
end

local function sync(e)
    local src = P.getSource(e.user_id)
    if src then TriggerClientEvent("evora_police:jail:sync", src, math.max(0, e.remaining)) end
end

---------------------------------------------------------------------------
-- Applying / releasing
---------------------------------------------------------------------------
local function jailPreset()
    return { Male = cfg().Clothing.Male, Female = cfg().Clothing.Female }
end

-- Puts an online prisoner in jail: teleport, cuffs, clothing, HUD.
function Jail.apply(e, src)
    -- The client needs a moment to teleport and load collision: no escape checks meanwhile.
    e.grace = GetGameTimer() + 15000
    P.teleport(src, cfg().Entry, cfg().EntryHeading)
    if cfg().Handcuff and cfg().Handcuff.Enabled then I.Handcuff.set(src, true) end
    if cfg().Clothing and cfg().Clothing.Enabled then I.Clothing.applyPreset(src, jailPreset()) end
    TriggerClientEvent("evora_police:jail:start", src, clientState(e))
    Officers.pushState(e.user_id)
    Evora.debug("jail", "applied sentence of %d (%ds left)", e.user_id, e.remaining)
end

-- Clothing, cuffs, teleport to the exit and HUD removal.
local function physicalRelease(e, src)
    if cfg().Clothing and cfg().Clothing.Enabled then
        local original = I.Clothing.decode(e.clothing)
        if original then I.Clothing.set(src, original) end
    end
    if cfg().Handcuff and cfg().Handcuff.Enabled and cfg().Handcuff.RemoveOnRelease ~= false then
        I.Handcuff.set(src, false)
    end
    P.teleport(src, cfg().Exit, cfg().ExitHeading)
    TriggerClientEvent("evora_police:jail:end", src)
    Jail.tasks[e.user_id] = nil
end

function Jail.start(target_id, target_src, info)
    local now = Evora.now()
    local clothing = ""
    if cfg().Clothing and cfg().Clothing.Enabled then
        local current = I.Clothing.get(target_src)
        if current then clothing = I.Clothing.encode(current) end
    end
    local wasCuffed = I.Handcuff.isCuffed(target_src)
    local e = {
        user_id = target_id,
        officer_id = info.officer_id or 0,
        officer_name = info.officer_name or "",
        reason_id = info.reason_id or "",
        reason_label = info.reason_label or "",
        total = info.seconds,
        remaining = info.seconds,
        added = 0,
        reduced = 0,
        started_at = now,
        clothing = clothing,
        was_cuffed = wasCuffed and 1 or 0,
    }
    DB.execute("DELETE FROM evora_police_jail WHERE user_id = ?", { target_id })
    DB.execute(
        "INSERT INTO evora_police_jail (user_id, name, officer_id, officer_name, reason_id, reason_label, total_seconds, remaining_seconds, added_seconds, reduced_seconds, started_at, updated_at, clothing, was_cuffed) VALUES (?, ?, ?, ?, ?, ?, ?, ?, 0, 0, ?, ?, ?, ?)",
        { target_id, P.name(target_id), e.officer_id, e.officer_name, e.reason_id, e.reason_label, e.total, e.remaining, now, now, clothing, e.was_cuffed }
    )
    Jail.active[target_id] = e
    Jail.apply(e, target_src)
    return e
end

-- endType: "served" | "released" | "modified". Writes history/logs now; the physical release
-- happens immediately when online or on the next join otherwise.
function Jail.finish(user_id, endType, byId, reason)
    local e = Jail.active[user_id]
    if not e or e.finishing or e.pendingRelease then return false end
    e.finishing = true
    local now = Evora.now()
    DB.execute(
        "INSERT INTO evora_police_jail_history (user_id, name, officer_id, officer_name, reason_label, total_seconds, started_at, ended_at, end_type, released_by_id, released_by_name, release_reason) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
        { user_id, P.name(user_id), e.officer_id, e.officer_name, e.reason_label, e.total, e.started_at, now, endType,
          byId or 0, (byId and byId > 0) and P.name(byId) or "", reason or "" }
    )
    local src = P.getSource(user_id)
    local vars = { target = P.name(user_id), target_id = user_id, officer = byId and byId > 0 and P.name(byId) or "", officer_id = byId or 0 }
    if endType == "released" then
        I.Chat.announce("JailRelease", vars, { src })
        Logs.add("jail", "jail_release", { actor = byId, target = user_id, fields = { { L("log_field_reason"), reason or "-" } } })
    elseif endType == "served" then
        I.Chat.announce("JailServed", vars, { src })
        Logs.add("jail", "jail_served", { target = user_id, fields = { { L("log_field_total"), Utils.humanDuration(e.total) } } })
    end
    if src then
        physicalRelease(e, src)
        DB.execute("DELETE FROM evora_police_jail WHERE user_id = ?", { user_id })
        Jail.active[user_id] = nil
        Evora.notify(src, endType == "released" and "jail_released_target" or "jail_served_target", { reason = reason or "" }, "success", 10)
        Officers.pushState(user_id)
    else
        e.remaining = 0
        e.pendingRelease = true
        e.finishing = false
        persist(e)
    end
    return true
end

---------------------------------------------------------------------------
-- Sentencing (officer flow)
---------------------------------------------------------------------------
local function officerAllowed(user_id)
    local profile = Gov.getProfile(user_id, true)
    if not Evora.feature("Jail") or not Gov.has(profile, "jail") then return false, L("err_no_permission") end
    if not Officers.dutyOk(user_id, "jail") then return false, L("err_not_on_duty") end
    return true
end

function Jail.sentence(officerSrc, reasonId, targetSrc, targetId)
    local officerId = P.getUserId(officerSrc)
    if not officerId then return end
    local ok, err = officerAllowed(officerId)
    if not ok then return Evora.notify(officerSrc, err, nil, "error") end
    local reason = Jail.findReason(reasonId)
    if not reason then return Evora.notify(officerSrc, "err_invalid_request", nil, "error") end
    if targetId == officerId then return Evora.notify(officerSrc, "target_self", nil, "error") end
    if Jail.isJailed(targetId) then return Evora.notify(officerSrc, "jail_already", nil, "error") end
    ok, err = Targets.check(officerSrc, targetSrc, targetId)
    if not ok then return Evora.notify(officerSrc, err, nil, "error") end

    local minutes = Utils.clamp(math.floor(tonumber(reason.duration) or 1), cfg().MinMinutes or 1, cfg().MaxMinutes or 300)
    local officerName, targetName = P.name(officerId), P.name(targetId)
    Evora.notify(officerSrc, "confirm_waiting", { name = targetName }, "info")
    local accepted, why = Confirm.forAction("jail", officerSrc, targetSrc, {
        title = L("confirm_jail_title"),
        message = L("confirm_jail_msg", { officer = officerName, officer_id = officerId }),
        details = {
            { L("field_jail"), cfg().Name },
            { L("field_reason"), reason.label },
            { L("field_duration"), L("minutes_value", { minutes = minutes }) },
            { L("field_description"), reason.description or "-" },
        },
        timeout = cfg().ConfirmTimeout,
        icon = "jail",
    })
    if not accepted then
        Evora.notify(officerSrc, Confirm.failMessage(why), nil, "error")
        if why == "rejected" then
            Logs.add("jail", "jail_rejected", { actor = officerId, target = targetId, fields = { { L("field_reason"), reason.label } } })
        end
        return
    end

    ok, err = officerAllowed(officerId)
    if not ok then return Evora.notify(officerSrc, err, nil, "error") end
    if P.bySource[targetSrc] ~= targetId then return Evora.notify(officerSrc, "err_target_offline", nil, "error") end
    if Jail.isJailed(targetId) then return Evora.notify(officerSrc, "jail_already", nil, "error") end

    Jail.start(targetId, targetSrc, {
        officer_id = officerId, officer_name = officerName, reason_id = reason.id, reason_label = reason.label, seconds = minutes * 60,
    })
    Officers.increment(officerId, "jails_issued", 1)
    local vars = { officer = officerName, officer_id = officerId, target = targetName, target_id = targetId, minutes = minutes, reason = reason.label, jail = cfg().Name }
    Evora.notify(targetSrc, "jail_target_notice", {
        officer = officerName, jail = cfg().Name, duration = L("minutes_value", { minutes = minutes }), reason = reason.label,
    }, "error", 12)
    Evora.notify(officerSrc, "jail_officer_done", vars, "success")
    I.Chat.announce("Jail", vars, { officerSrc, targetSrc })
    Logs.add("jail", "jail", {
        actor = officerId, target = targetId, actorName = officerName, targetName = targetName,
        fields = {
            { L("field_reason"), reason.label, true },
            { L("field_duration"), L("minutes_value", { minutes = minutes }), true },
            { L("field_jail"), cfg().Name, true },
        },
    })
    if Config.Wanted and Config.Wanted.ClearOnJail then Evora.Wanted.clearForTarget(targetId, officerId, "wanted_clear_jail") end
end

function Jail.menu(source, parent)
    local items = {}
    for _, r in ipairs(cfg().Reasons or {}) do
        items[#items + 1] = {
            label = ("%s — %s"):format(r.label, L("minutes_value", { minutes = r.duration })),
            description = r.description or "",
            action = function(src)
                local ok, err = officerAllowed(P.getUserId(src))
                if not ok then return Evora.notify(src, err, nil, "error") end
                Targets.pick(src, L("target_pick_title"), function(targetSrc, targetId)
                    Jail.sentence(src, r.id, targetSrc, targetId)
                end, function(s) return Jail.menu(s, parent) end)
            end,
        }
    end
    return { title = L("menu_jail"), subtitle = cfg().Name, items = items, parent = parent }
end

function Jail.openMenu(source, parent)
    local ok, err = officerAllowed(P.getUserId(source))
    if not ok then return Evora.notify(source, err, nil, "error") end
    Evora.Menu.open(source, Jail.menu(source, parent))
end

---------------------------------------------------------------------------
-- Management (استعلامات)
---------------------------------------------------------------------------
local function requirePerm(source, perm)
    local user_id = P.getUserId(source)
    if not user_id then return nil end
    local profile = Gov.getProfile(user_id, true)
    if not Evora.feature("Jail") or not Gov.has(profile, perm) then
        Evora.notify(source, "err_no_permission", nil, "error")
        return nil
    end
    if not Officers.dutyOk(user_id, "inquiries") then
        Evora.notify(source, "err_not_on_duty", nil, "error")
        return nil
    end
    return user_id, profile
end

-- Prisoners list as menu items (onlineOnly for spectating).
function Jail.prisonerMenu(source, title, onlineOnly, onPick, parent)
    local items = {}
    local list = {}
    for uid, e in pairs(Jail.active) do
        if not e.pendingRelease and (not onlineOnly or P.isOnline(uid)) then list[#list + 1] = e end
    end
    table.sort(list, function(a, b) return a.remaining < b.remaining end)
    for _, e in ipairs(list) do
        local online = P.isOnline(e.user_id)
        items[#items + 1] = {
            label = ("%s | ID: %d"):format(P.name(e.user_id), e.user_id),
            description = L("jail_prisoner_desc", { remaining = Utils.mmss(e.remaining), reason = e.reason_label, state = online and L("online") or L("offline") }),
            action = function(src) onPick(src, e.user_id) end,
        }
    end
    if #items == 0 then
        Evora.notify(source, "jail_no_prisoners", nil, "info")
        return nil
    end
    return { title = title, items = items, parent = parent }
end

function Jail.checkFlow(source)
    local user_id = requirePerm(source, "jailCheck")
    if not user_id then return end
    local values = I.Popup.input(source, L("jail_check_title"), { { key = "id", label = L("field_citizen_id"), type = "number", min = 1 } })
    if not values then return Evora.notify(source, "action_cancelled", nil, "info") end
    if not requirePerm(source, "jailCheck") then return end
    if not P.exists(values.id) then return Evora.notify(source, "err_unknown_id", nil, "error") end
    local status = Jail.status(values.id)
    status.user_id = values.id
    status.name = P.name(values.id)
    status.jailName = cfg().Name
    Evora.ui(source, "panel", { kind = "jail", title = L("jail_check_title"), data = status })
    Logs.add("jail", "jail_check", { actor = user_id, target = values.id })
end

function Jail.modify(adminSrc, adminId, targetId, mode, minutes)
    local e = Jail.active[targetId]
    if not e or e.pendingRelease then return Evora.notify(adminSrc, "jail_not_jailed", nil, "error") end
    local before = e.remaining
    local after = before
    if mode == "add" then after = before + minutes * 60
    elseif mode == "remove" then after = before - minutes * 60
    else after = minutes * 60 end
    after = math.min(after, (cfg().MaxMinutes or 300) * 60)

    local accepted, reason = Confirm.forAction("jailModify", adminSrc, P.getSource(targetId), {
        title = L("confirm_jail_modify_title"),
        message = L("confirm_jail_modify_msg", { name = P.name(targetId), id = targetId }),
        details = {
            { L("jail_modify_before"), Utils.mmss(before) },
            { L("jail_modify_after"), Utils.mmss(math.max(0, after)) },
        },
        icon = "jail",
    })
    if not accepted then return Evora.notify(adminSrc, Confirm.failMessage(reason, true), nil, "error") end
    local _, profile = requirePerm(adminSrc, "jailModify")
    if not profile then return end
    e = Jail.active[targetId]
    if not e or e.pendingRelease then return Evora.notify(adminSrc, "jail_not_jailed", nil, "error") end

    Logs.add("jail", "jail_modify", {
        actor = adminId, target = targetId,
        fields = { { L("jail_modify_before"), Utils.mmss(before), true }, { L("jail_modify_after"), Utils.mmss(math.max(0, after)), true }, { L("jail_modify_mode"), L("jail_mode_" .. mode), true } },
    })
    if after <= 0 then
        Jail.finish(targetId, "released", adminId, L("jail_modify_zero"))
    else
        e.remaining = after
        persist(e)
        sync(e)
        local src = P.getSource(targetId)
        if src then Evora.notify(src, "jail_modified_target", { remaining = Utils.mmss(after) }, "info") end
    end
    Evora.notify(adminSrc, "jail_modified_admin", { remaining = Utils.mmss(math.max(0, after)) }, "success")
end

function Jail.modifyFlow(source, parent)
    local adminId = requirePerm(source, "jailModify")
    if not adminId then return end
    local onPick
    local function listMenu(s) return Jail.prisonerMenu(s, L("menu_jail_modify"), false, onPick, parent) end
    onPick = function(src, targetId)
        local modes = {}
        for _, mode in ipairs({ "add", "remove", "set" }) do
            modes[#modes + 1] = {
                label = L("jail_mode_" .. mode),
                action = function(s)
                    local values = I.Popup.input(s, L("jail_mode_" .. mode), {
                        { key = "minutes", label = L("field_minutes"), type = "number", min = mode == "set" and 1 or 1, max = cfg().MaxMinutes or 300 },
                    })
                    if not values then return Evora.notify(s, "action_cancelled", nil, "info") end
                    local id = requirePerm(s, "jailModify")
                    if id then Jail.modify(s, id, targetId, mode, values.minutes) end
                end,
            }
        end
        Evora.Menu.open(src, { title = ("%s | ID: %d"):format(P.name(targetId), targetId), items = modes, parent = listMenu })
    end
    local menu = listMenu(source)
    if menu then Evora.Menu.open(source, menu) end
end

function Jail.monitorFlow(source, parent)
    if not requirePerm(source, "jailMonitor") then return end
    local menu = Jail.prisonerMenu(source, L("menu_jail_monitor"), true, function(src, targetId)
        if not requirePerm(src, "jailMonitor") then return end
        local targetSrc = P.getSource(targetId)
        if not targetSrc or not Jail.isJailed(targetId) then return Evora.notify(src, "err_target_offline", nil, "error") end
        local adminId = P.getUserId(src)
        local ok, err = Evora.Spectate.start(src, targetSrc, "prisoner", function()
            return Evora.feature("Jail") and Jail.isJailed(targetId) and Gov.has(Gov.cached(adminId), "jailMonitor")
        end)
        if not ok then Evora.notify(src, err, nil, "error") end
    end, parent)
    if menu then Evora.Menu.open(source, menu) end
end

function Jail.releaseFlow(source, parent)
    if not requirePerm(source, "jailRelease") then return end
    local menu = Jail.prisonerMenu(source, L("menu_jail_release"), false, function(src, targetId)
        local values = I.Popup.input(src, L("jail_release_title"), {
            { key = "reason", label = L("field_release_reason"), type = "textarea", max = 200 },
        })
        if not values then return Evora.notify(src, "jail_release_reason_required", nil, "error") end
        local adminId = requirePerm(src, "jailRelease")
        if not adminId then return end
        local accepted, why = Confirm.forAction("jailRelease", src, P.getSource(targetId), {
            title = L("confirm_jail_release_title"),
            message = L("confirm_jail_release_msg", { name = P.name(targetId), id = targetId }),
            details = { { L("field_release_reason"), values.reason } },
            icon = "jail",
        })
        if not accepted then return Evora.notify(src, Confirm.failMessage(why, true), nil, "error") end
        adminId = requirePerm(src, "jailRelease")
        if not adminId then return end
        if not Jail.isJailed(targetId) then return Evora.notify(src, "jail_not_jailed", nil, "error") end
        Jail.finish(targetId, "released", adminId, values.reason)
        Evora.notify(src, "jail_released_admin", { name = P.name(targetId), id = targetId }, "success")
    end, parent)
    if menu then Evora.Menu.open(source, menu) end
end

---------------------------------------------------------------------------
-- Escapes
---------------------------------------------------------------------------
function Jail.onEscape(user_id, src)
    local e = Jail.active[user_id]
    if not e or e.pendingRelease or e.finishing then return end
    local esc = cfg().Escape or {}
    if not esc.Enabled then return end
    local now = GetGameTimer()
    if (e.lastEscape and now - e.lastEscape < 6000) or (e.grace and now < e.grace) then return end
    e.lastEscape = now
    e.grace = now + 6000
    P.teleport(src, returnPoint(), cfg().EntryHeading)
    local added = 0
    local cap = (esc.MaxAddedMinutes or 60) * 60
    if (esc.AddMinutes or 0) > 0 and e.added < cap then
        added = math.min((esc.AddMinutes or 0) * 60, cap - e.added)
        e.remaining = e.remaining + added
        e.added = e.added + added
        persist(e)
    end
    sync(e)
    TriggerClientEvent("evora_police:jail:escape", src, esc.Message or "", added)
    Evora.notify(src, esc.Message or "", nil, "error", 8)
    Logs.add("jail", "jail_escape", { target = user_id, fields = { { L("log_field_added"), Utils.humanDuration(added) } } })
end

-- Client-side perimeter report (used without OneSync). Only ever makes things worse for the
-- reporting prisoner, so trusting it is safe.
RPC.register("jail:escaped", { feature = "Jail", cooldown = 3000 }, function(ctx)
    if not Jail.isJailed(ctx.user_id) then return true end
    if P.oneSync() then
        local c = P.coords(ctx.source)
        if not c or Utils.dist2d(c, center()) <= (cfg().Radius or 150) then return true end
    end
    Jail.onEscape(ctx.user_id, ctx.source)
    return true
end)

---------------------------------------------------------------------------
-- Tasks
---------------------------------------------------------------------------
local function findTask(id)
    for _, t in ipairs((cfg().Tasks and cfg().Tasks.List) or {}) do
        if t.id == id then return t end
    end
    return nil
end

local function atTask(src, task)
    local c = P.coords(src)
    return c ~= nil and Utils.dist(c, task.coords) <= (task.radius or 2.0) + 1.0
end

RPC.register("jail:taskStart", { feature = "Jail", cooldown = 1000 }, function(ctx, data)
    local tcfg = cfg().Tasks or {}
    if not tcfg.Enabled then return nil, L("err_feature_disabled") end
    if not Jail.isJailed(ctx.user_id) then return nil, L("jail_not_jailed_self") end
    local task = type(data.id) == "string" and findTask(data.id)
    if not task then return nil, L("err_invalid_request") end
    if Jail.tasks[ctx.user_id] then return nil, L("jail_task_busy") end
    local cooldowns = Jail.taskCooldowns[ctx.user_id] or {}
    Jail.taskCooldowns[ctx.user_id] = cooldowns
    if cooldowns[task.id] and cooldowns[task.id] > Evora.now() then
        return nil, L("jail_task_cooldown", { seconds = cooldowns[task.id] - Evora.now() })
    end
    if not atTask(ctx.source, task) then return nil, L("jail_task_far") end
    Jail.tasks[ctx.user_id] = { id = task.id, startedAt = GetGameTimer() }
    local typeDef = tcfg.Types and tcfg.Types[task.type] or {}
    local difficulty = tcfg.Difficulties and tcfg.Difficulties[task.difficulty] or { checks = 1, speed = 1, zone = 0.2 }
    return {
        id = task.id, label = task.label, duration = task.duration,
        anim = { scenario = typeDef.scenario, dict = typeDef.dict, name = typeDef.anim },
        difficulty = difficulty,
    }
end)

RPC.register("jail:taskComplete", { feature = "Jail", cooldown = 500 }, function(ctx, data)
    local session = Jail.tasks[ctx.user_id]
    Jail.tasks[ctx.user_id] = nil
    if not session or session.id ~= data.id then return nil, L("err_invalid_request") end
    local e = Jail.active[ctx.user_id]
    if not e or e.pendingRelease then return nil, L("jail_not_jailed_self") end
    local task = findTask(session.id)
    if not task then return nil, L("err_invalid_request") end
    if data.success ~= true then return { reduced = 0, failed = true } end
    if GetGameTimer() - session.startedAt < (task.duration * 1000) - 1500 then return nil, L("jail_task_too_fast") end
    if not atTask(ctx.source, task) then return nil, L("jail_task_far") end

    local tcfg = cfg().Tasks or {}
    Jail.taskCooldowns[ctx.user_id][task.id] = Evora.now() + (task.cooldown or 120)
    local maxTotal = math.floor(e.total * (tcfg.MaxReductionPercent or 50) / 100)
    local allowed = math.max(0, maxTotal - e.reduced)
    local reduction = math.min(task.reduction or 0, allowed, math.max(0, e.remaining - (tcfg.MinRemaining or 60)))
    if reduction <= 0 then return { reduced = 0, capped = true } end
    e.remaining = e.remaining - reduction
    e.reduced = e.reduced + reduction
    persist(e)
    sync(e)
    Logs.add("jail", "jail_task", { target = ctx.user_id, fields = { { L("field_task"), task.label, true }, { L("log_field_reduced"), Utils.humanDuration(reduction), true } } })
    return { reduced = reduction, remaining = e.remaining }
end)

RPC.register("jail:taskCancel", { feature = "Jail" }, function(ctx)
    Jail.tasks[ctx.user_id] = nil
    return true
end)

---------------------------------------------------------------------------
-- Lifecycle, timers and persistence
---------------------------------------------------------------------------
function Jail.load()
    Jail.active = {}
    for _, row in ipairs(DB.query("SELECT * FROM evora_police_jail")) do
        local uid = tonumber(row.user_id)
        Jail.active[uid] = {
            user_id = uid,
            officer_id = tonumber(row.officer_id) or 0,
            officer_name = row.officer_name or "",
            reason_id = row.reason_id or "",
            reason_label = row.reason_label or "",
            total = tonumber(row.total_seconds) or 0,
            remaining = tonumber(row.remaining_seconds) or 0,
            added = tonumber(row.added_seconds) or 0,
            reduced = tonumber(row.reduced_seconds) or 0,
            started_at = tonumber(row.started_at) or 0,
            clothing = row.clothing or "",
            was_cuffed = tonumber(row.was_cuffed) or 0,
            pendingRelease = (tonumber(row.remaining_seconds) or 0) <= 0,
        }
    end
    Evora.debug("jail", "%d sentences loaded", Utils.count(Jail.active))
end

-- Join / restart / respawn: re-apply the sentence (never re-saving the original clothing).
Evora.on("playerReady", function(user_id, source)
    local e = Jail.active[user_id]
    if not e then return end
    if e.pendingRelease or e.remaining <= 0 then
        physicalRelease(e, source)
        DB.execute("DELETE FROM evora_police_jail WHERE user_id = ?", { user_id })
        Jail.active[user_id] = nil
        Evora.notify(source, "jail_served_target", nil, "success", 10)
        Officers.pushState(user_id)
        return
    end
    Jail.apply(e, source)
end)

Evora.on("playerRespawn", function(user_id, source)
    local e = Jail.active[user_id]
    if e and not e.pendingRelease then
        SetTimeout(1500, function()
            if Jail.active[user_id] == e and P.getSource(user_id) == source then Jail.apply(e, source) end
        end)
    end
end)

Evora.on("playerDropped", function(user_id)
    local e = Jail.active[user_id]
    if e then persist(e) end
    Jail.tasks[user_id] = nil
end)

-- 1 s authoritative timer. Counts elapsed game time, so server hitches do not stretch sentences.
Citizen.CreateThread(function()
    local last = GetGameTimer()
    while true do
        Citizen.Wait(1000)
        local step = math.floor((GetGameTimer() - last) / 1000)
        last = last + step * 1000
        local countOffline = cfg().CountOfflineTime == true
        for uid, e in pairs(Jail.active) do
            if step > 0 and not e.pendingRelease and not e.finishing and (countOffline or P.byUser[uid]) then
                e.remaining = e.remaining - step
                e.dirty = true
                if e.remaining <= 0 then
                    e.remaining = 0
                    Evora.thread(Jail.finish, uid, "served", 0, nil)
                end
            end
        end
    end
end)

-- Persistence + periodic HUD re-sync.
Citizen.CreateThread(function()
    while true do
        Citizen.Wait((cfg().PersistInterval or 30) * 1000)
        for _, e in pairs(Jail.active) do
            if e.dirty and not e.finishing then
                persist(e)
                sync(e)
            end
        end
    end
end)

-- Escape detection (server-side positions, OneSync).
Citizen.CreateThread(function()
    while true do
        local esc = cfg().Escape or {}
        Citizen.Wait((esc.CheckInterval or 2) * 1000)
        if esc.Enabled and P.oneSync() then
            local c, radius = center(), cfg().Radius or 150
            for uid, e in pairs(Jail.active) do
                local src = not e.pendingRelease and not e.finishing and P.byUser[uid]
                if src then
                    local pos = P.coords(src)
                    if pos and Utils.dist2d(pos, c) > radius then Jail.onEscape(uid, src) end
                end
            end
        end
    end
end)

-- Resource stop: hand the latest remaining times to the database driver immediately.
AddEventHandler("onResourceStop", function(resource)
    if resource ~= GetCurrentResourceName() then return end
    for _, e in pairs(Jail.active) do
        if not e.finishing then
            DB.fire("UPDATE evora_police_jail SET remaining_seconds = ?, added_seconds = ?, reduced_seconds = ?, updated_at = ? WHERE user_id = ?",
                { math.max(0, e.remaining), e.added, e.reduced, Evora.now(), e.user_id })
        end
    end
end)

-- Keep prisoners restrained.
Citizen.CreateThread(function()
    while true do
        local cuffs = cfg().Handcuff or {}
        Citizen.Wait((cuffs.EnforceInterval or 15) * 1000)
        if cuffs.Enabled and cuffs.Enforce then
            for uid, e in pairs(Jail.active) do
                local src = not e.pendingRelease and not e.finishing and P.byUser[uid]
                if src and not Jail.tasks[uid] and not I.Handcuff.isCuffed(src) then I.Handcuff.set(src, true) end
            end
        end
    end
end)
