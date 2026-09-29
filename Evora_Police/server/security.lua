--[[
    Evora_Police — security alert (الاستنفار الأمني)

    CRITICAL RULE: players already inside the zone when the alert starts are NOT affected;
    players who enter after the start ARE affected. The occupants are captured on the server at
    activation time (server-side positions with OneSync) and each client receives its own
    exemption flag with the alert.
]]

local Alert = { active = {}, seq = 0 }
Evora.Alert = Alert

local P, Gov, Logs, Officers = Evora.Players, Evora.Gov, Evora.Logs, Evora.Officers

local function cfg() return Config.SecurityAlert or {} end

local function publicAlert(a)
    return {
        id = a.id, label = a.label, coords = a.coords, radius = a.radius,
        startedAt = a.startedAt, by = a.byName,
        mapZone = cfg().MapZone, vehicle = cfg().VehicleSlowdown, player = cfg().PlayerSlowdown,
        exemptOfficers = cfg().ExemptOfficers ~= false, exemptionEndsOnExit = cfg().ExemptionEndsOnExit ~= false,
        interval = cfg().CheckInterval or 400,
    }
end

Alert.public = publicAlert

local function gate(source)
    local user_id = P.getUserId(source)
    if not user_id then return nil end
    local profile = Gov.getProfile(user_id, true)
    if not Evora.feature("SecurityTools") or not Gov.has(profile, "securityAlert") then
        Evora.notify(source, "err_no_permission", nil, "error")
        return nil
    end
    if not Officers.dutyOk(user_id, "securityAlert") then
        Evora.notify(source, "err_not_on_duty", nil, "error")
        return nil
    end
    return user_id
end

function Alert.start(source, zone)
    local user_id = gate(source)
    if not user_id then return end
    if Utils.count(Alert.active) >= (cfg().MaxActive or 3) then return Evora.notify(source, "alert_max", nil, "error") end
    local coords, radius, label
    if zone then
        coords, radius, label = Utils.vec(zone.coords), tonumber(zone.radius) or cfg().DefaultRadius or 200.0, zone.label
    else
        coords = P.coords(source)
        if not coords then return Evora.notify(source, "err_internal", nil, "error") end
        radius, label = cfg().DefaultRadius or 200.0, L("alert_current_location")
    end
    Alert.seq = Alert.seq + 1
    local a = {
        id = Alert.seq, label = label, coords = coords, radius = radius,
        startedAt = Evora.now(), by = user_id, byName = P.name(user_id), exempt = {},
    }
    -- Capture the occupants at activation time.
    local serverSide = P.oneSync()
    if serverSide then
        for _, p in ipairs(P.online()) do
            local c = P.coords(p.source)
            if c and Utils.dist2d(c, coords) <= radius then a.exempt[p.source] = true end
        end
    end
    Alert.active[a.id] = a
    local payload = publicAlert(a)
    for _, p in ipairs(P.online()) do
        -- true = exempt, false = affected on entry, nil = client decides at receipt (no OneSync)
        local exempt = nil
        if serverSide then exempt = a.exempt[p.source] == true end
        TriggerClientEvent("evora_police:alert:start", p.source, payload, exempt)
    end
    if cfg().AnnounceToCitizens then
        TriggerClientEvent("evora_police:ui", -1, "broadcast", {
            kind = "alert", title = L("alert_broadcast_title"), message = L("alert_broadcast_start", { zone = label }),
            duration = Config.Broadcast.Duration, style = Config.Broadcast.Style, sound = Config.Broadcast.Sound,
        })
    end
    Evora.notify(source, "alert_started", { zone = label }, "success")
    Logs.add("security", "alert_start", { actor = user_id, fields = {
        { L("alert_zone"), label, true }, { L("alert_radius"), ("%dm"):format(math.floor(radius)), true },
        { L("alert_exempt"), Utils.count(a.exempt), true },
    } })
end

function Alert.stop(source, id)
    local user_id = gate(source)
    if not user_id then return end
    local a = Alert.active[id]
    if not a then return Evora.notify(source, "alert_not_found", nil, "error") end
    Alert.active[id] = nil
    TriggerClientEvent("evora_police:alert:stop", -1, id)
    if cfg().AnnounceToCitizens then
        TriggerClientEvent("evora_police:ui", -1, "broadcast", {
            kind = "alert", title = L("alert_broadcast_title"), message = L("alert_broadcast_stop", { zone = a.label }),
            duration = Config.Broadcast.Duration, style = Config.Broadcast.Style, sound = Config.Broadcast.Sound,
        })
    end
    Evora.notify(source, "alert_stopped", { zone = a.label }, "success")
    Logs.add("security", "alert_stop", { actor = user_id, fields = { { L("alert_zone"), a.label, true },
        { L("log_field_duration"), Utils.humanDuration(Evora.now() - a.startedAt), true } } })
end

function Alert.menu(source, parent)
    if not gate(source) then return nil end
    local function startMenu(s)
        local items = {}
        for _, zone in ipairs(cfg().Zones or {}) do
            items[#items + 1] = {
                label = zone.label,
                description = L("alert_zone_desc", { radius = math.floor(zone.radius or cfg().DefaultRadius or 200) }),
                action = function(src) Alert.start(src, zone) end,
            }
        end
        if cfg().AllowCurrentLocation then
            items[#items + 1] = { label = L("alert_current_location"), description = L("alert_zone_desc", { radius = math.floor(cfg().DefaultRadius or 200) }),
                action = function(src) Alert.start(src, nil) end }
        end
        return { title = L("alert_start"), items = items, parent = function(x) return Alert.menu(x, parent) end }
    end
    local function stopMenu(s)
        local items = {}
        for id, a in pairs(Alert.active) do
            items[#items + 1] = {
                label = a.label,
                description = L("alert_active_desc", { by = a.byName, since = Utils.humanDuration(Evora.now() - a.startedAt) }),
                action = function(src) Alert.stop(src, id) end,
            }
        end
        if #items == 0 then
            Evora.notify(s, "alert_none_active", nil, "info")
            return nil
        end
        return { title = L("alert_stop"), items = items, parent = function(x) return Alert.menu(x, parent) end }
    end
    return {
        title = L("menu_security_alert"),
        items = {
            { label = L("alert_start"), description = L("alert_start_desc"), action = function(src) Evora.Menu.open(src, startMenu(src)) end },
            { label = L("alert_stop"), description = L("alert_stop_desc", { count = Utils.count(Alert.active) }), action = function(src) local m = stopMenu(src) if m then Evora.Menu.open(src, m) end end },
        },
        parent = parent,
    }
end

-- Late joiners: active alerts affect them (they were not inside at activation).
Evora.on("playerReady", function(user_id, source)
    local list = {}
    for _, a in pairs(Alert.active) do list[#list + 1] = publicAlert(a) end
    if #list > 0 then TriggerClientEvent("evora_police:alert:sync", source, list) end
end)

Evora.on("playerDropped", function(_, source)
    for _, a in pairs(Alert.active) do
        if source then a.exempt[source] = nil end
    end
end)
