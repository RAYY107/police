--[[
    Evora_Police — barricades (الحواجز)

    The officer positions a local preview; the server validates distance, model and limits and
    creates the networked object itself (OneSync). Without OneSync the client creates it and the
    server only tracks it. Officers remove their own barricades; barricadesAdmin removes any.
]]

local Barricades = { list = {} } -- [netId] = { entity, owner, index, label, createdAt, coords }
Evora.Barricades = Barricades

local P, Gov, Logs, Officers, RPC = Evora.Players, Evora.Gov, Evora.Logs, Evora.Officers, Evora.RPC

local function options() return Config.BarricadeOptions or {} end

local function object(index)
    local o = Config.Barricades and Config.Barricades[index]
    if type(o) == "table" and o.enabled ~= false and type(o.model) == "string" then return o end
    return nil
end

local function gate(source)
    local user_id = P.getUserId(source)
    if not user_id then return nil end
    local profile = Gov.getProfile(user_id, true)
    if not Evora.feature("Barricades") or not Gov.has(profile, "barricades") then
        Evora.notify(source, "err_no_permission", nil, "error")
        return nil
    end
    if not Officers.dutyOk(user_id, "barricades") then
        Evora.notify(source, "err_not_on_duty", nil, "error")
        return nil
    end
    return user_id, profile
end

local function countOwned(user_id)
    local n = 0
    for _, b in pairs(Barricades.list) do
        if b.owner == user_id then n = n + 1 end
    end
    return n
end

local function deleteEntry(netId, b)
    Barricades.list[netId] = nil
    if b.entity and DoesEntityExist(b.entity) then
        DeleteEntity(b.entity)
    else
        TriggerClientEvent("evora_police:barricade:delete", -1, netId)
    end
end

function Barricades.startPlacement(source, index)
    local user_id = gate(source)
    if not user_id then return end
    local o = object(index)
    if not o then return Evora.notify(source, "err_invalid_request", nil, "error") end
    if countOwned(user_id) >= (options().MaxPerOfficer or 10) then return Evora.notify(source, "barricade_limit", nil, "error") end
    TriggerClientEvent("evora_police:barricade:place", source, index, o.model, o.label, options().PlaceDistance or 2.2, P.oneSync())
end

RPC.register("barricade:place", { feature = "Barricades", perm = "barricades", duty = "barricades", cooldown = 800 }, function(ctx, data)
    local index = RPC.int(data.index, 1)
    local o = index and object(index)
    local x, y, z = Utils.toNumber(data.x), Utils.toNumber(data.y), Utils.toNumber(data.z)
    local heading = Utils.toNumber(data.heading) or 0.0
    if not o or not x or not y or not z then return nil, L("err_invalid_request") end
    if countOwned(ctx.user_id) >= (options().MaxPerOfficer or 10) then return nil, L("barricade_limit") end
    if Utils.count(Barricades.list) >= (options().MaxTotal or 80) then return nil, L("barricade_limit_total") end
    local officer = P.coords(ctx.source)
    local pos = { x = x, y = y, z = z }
    if not officer or Utils.dist(officer, pos) > (options().MaxPlaceDistance or 6.0) then return nil, L("barricade_too_far") end

    local entry = { owner = ctx.user_id, index = index, label = o.label, createdAt = Evora.now(), coords = pos }
    local netId
    if P.oneSync() and CreateObjectNoOffset then
        local entity = CreateObjectNoOffset(GetHashKey(o.model), x, y, z, true, true, false)
        local tries = 0
        while not DoesEntityExist(entity) and tries < 50 do
            Citizen.Wait(10)
            tries = tries + 1
        end
        if not DoesEntityExist(entity) then return nil, L("err_internal") end
        SetEntityHeading(entity, heading)
        FreezeEntityPosition(entity, true)
        netId = NetworkGetNetworkIdFromEntity(entity)
        entry.entity = entity
    else
        netId = RPC.int(data.netId, 1)
        if not netId or Barricades.list[netId] then return nil, L("err_invalid_request") end
    end
    Barricades.list[netId] = entry
    Logs.add("security", "barricade_spawn", { actor = ctx.user_id, fields = { { L("field_object"), o.label, true },
        { L("field_coords"), ("%.1f, %.1f, %.1f"):format(x, y, z), true } } })
    return { netId = netId }
end)

function Barricades.removeNearest(source)
    local user_id, profile = gate(source)
    if not user_id then return end
    local origin = P.coords(source)
    if not origin then return end
    local admin = Gov.has(profile, "barricadesAdmin")
    local bestId, best, bestDist
    for netId, b in pairs(Barricades.list) do
        if b.owner == user_id or admin then
            local pos = b.entity and DoesEntityExist(b.entity) and Utils.vec(GetEntityCoords(b.entity)) or b.coords
            local d = Utils.dist(origin, pos)
            if d <= (options().DeleteRadius or 3.5) and (not bestDist or d < bestDist) then bestId, best, bestDist = netId, b, d end
        end
    end
    if not best then return Evora.notify(source, "barricade_none_near", nil, "error") end
    deleteEntry(bestId, best)
    Evora.notify(source, "barricade_removed", { label = best.label }, "success")
    Logs.add("security", "barricade_remove", { actor = user_id, target = best.owner ~= user_id and best.owner or nil,
        fields = { { L("field_object"), best.label, true } } })
end

function Barricades.removeAllMine(source)
    local user_id = gate(source)
    if not user_id then return end
    local n = 0
    for netId, b in pairs(Barricades.list) do
        if b.owner == user_id then
            deleteEntry(netId, b)
            n = n + 1
        end
    end
    Evora.notify(source, "barricade_removed_all", { count = n }, "success")
    if n > 0 then Logs.add("security", "barricade_remove_all", { actor = user_id, fields = { { L("log_field_count"), n, true } } }) end
end

function Barricades.menu(source, parent)
    if not gate(source) then return nil end
    local function spawnMenu(s)
        local items = {}
        for i, o in ipairs(Config.Barricades or {}) do
            if o.enabled ~= false then
                items[#items + 1] = { label = o.label, description = o.model, action = function(src) Barricades.startPlacement(src, i) end }
            end
        end
        return { title = L("barricade_spawn"), items = items, parent = function(x) return Barricades.menu(x, parent) end }
    end
    return {
        title = L("menu_barricades"),
        items = {
            { label = L("barricade_spawn"), description = L("barricade_spawn_desc"), action = function(src) Evora.Menu.open(src, spawnMenu(src)) end },
            { label = L("barricade_remove"), description = L("barricade_remove_desc"), action = function(src) Barricades.removeNearest(src) end },
            { label = L("barricade_remove_all"), description = L("barricade_remove_all_desc"), action = function(src) Barricades.removeAllMine(src) end },
        },
        parent = parent,
    }
end

-- Cleanup: owner disconnect, lifetime, resource stop.
Evora.on("playerDropped", function(user_id)
    if not options().DeleteOnDisconnect then return end
    for netId, b in pairs(Barricades.list) do
        if b.owner == user_id then deleteEntry(netId, b) end
    end
end)

Citizen.CreateThread(function()
    while true do
        Citizen.Wait(60000)
        local lifetime = (options().LifetimeMinutes or 0) * 60
        if lifetime > 0 then
            local now = Evora.now()
            for netId, b in pairs(Barricades.list) do
                if now - b.createdAt >= lifetime then deleteEntry(netId, b) end
            end
        end
    end
end)

AddEventHandler("onResourceStop", function(resource)
    if resource ~= GetCurrentResourceName() then return end
    for netId, b in pairs(Barricades.list) do
        if b.entity and DoesEntityExist(b.entity) then DeleteEntity(b.entity) end
    end
end)
