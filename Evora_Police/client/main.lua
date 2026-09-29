--[[
    Evora_Police — client core: RPC client, NUI bridge, focus stack, state, generic events.
    The client never decides anything sensitive: it renders UI and performs local effects.
]]

Evora = Evora or {}
Evora.state = { military = false, onDuty = false, vacation = false, jailed = false, permissions = {} }
Evora.ready = false

function Evora.debug(category, msg, ...)
    if not Config.Debug then return end
    local ok, text = pcall(string.format, msg, ...)
    print(("^6[Evora_Police:%s]^7 %s"):format(category, ok and text or msg))
end

function Evora.hasPerm(perm)
    for _, p in ipairs(Evora.state.permissions or {}) do
        if p == perm then return true end
    end
    return false
end

---------------------------------------------------------------------------
-- RPC
---------------------------------------------------------------------------
local rpcSeq = 0
local pending = {}

-- Blocking (call from a thread). Returns ok, data | ok = false, errorMessage
function Evora.rpc(name, payload, timeoutMs)
    rpcSeq = rpcSeq + 1
    local id = rpcSeq
    local p = promise.new()
    pending[id] = p
    TriggerServerEvent("evora_police:rpc", id, name, payload or {})
    SetTimeout(timeoutMs or 90000, function()
        if pending[id] then
            pending[id] = nil
            p:resolve({ ok = false, data = "timeout" })
        end
    end)
    local r = Citizen.Await(p)
    return r.ok, r.data
end

RegisterNetEvent("evora_police:rpc:res", function(id, ok, data)
    local p = pending[id]
    if not p then return end
    pending[id] = nil
    p:resolve({ ok = ok == true, data = data })
end)

---------------------------------------------------------------------------
-- NUI bridge + focus stack
---------------------------------------------------------------------------
UI = UI or {}
local focusLayers = {}

function UI.send(action, data)
    SendNUIMessage({ action = action, data = data })
end

-- Several layers (iPad, dialog, panel, menu) can need focus at the same time.
function UI.focus(layer, state, cursor)
    if state then
        focusLayers[layer] = cursor ~= false
    else
        focusLayers[layer] = nil
    end
    local any, anyCursor = false, false
    for _, c in pairs(focusLayers) do
        any = true
        if c then anyCursor = true end
    end
    SetNuiFocus(any, anyCursor)
end

function UI.hasFocus(layer)
    if layer then return focusLayers[layer] ~= nil end
    return next(focusLayers) ~= nil
end

function UI.notify(message, kind, duration)
    UI.send("toast", { message = message, kind = kind or "info", duration = duration or 6 })
end

RegisterNUICallback("ready", function(_, cb)
    UI.send("init", {
        locale = LocaleUI,
        ui = Config.UI,
        confirm = { accept = Config.Confirm.AcceptLabel, reject = Config.Confirm.RejectLabel },
        broadcast = Config.Broadcast.Style,
        spectate = { key = Config.Spectate.StopKeyLabel },
        wanted = Config.Wanted.QuickOpen,
        vacation = { durations = Config.Vacation.Durations },
    })
    UI.send("state", Evora.state)
    cb({ ok = true })
end)

RegisterNUICallback("rpc", function(data, cb)
    if type(data) ~= "table" or type(data.name) ~= "string" then
        cb({ ok = false, data = "invalid" })
        return
    end
    Citizen.CreateThread(function()
        local ok, result = Evora.rpc(data.name, data.payload or {})
        cb({ ok = ok, data = result })
    end)
end)

RegisterNUICallback("close", function(data, cb)
    local layer = type(data) == "table" and data.layer or nil
    if layer then
        UI.focus(layer, false)
        TriggerEvent("evora_police:client:closed", layer)
    end
    cb({ ok = true })
end)

---------------------------------------------------------------------------
-- State
---------------------------------------------------------------------------
RegisterNetEvent("evora_police:state", function(state)
    if type(state) ~= "table" then return end
    Evora.state = state
    UI.send("state", state)
    TriggerEvent("evora_police:client:state", state)
end)

---------------------------------------------------------------------------
-- Server → client requests (facts about this client only)
---------------------------------------------------------------------------
Evora.responders = Evora.responders or {}

Evora.responders.coords = function()
    local c = GetEntityCoords(PlayerPedId())
    return { x = c.x, y = c.y, z = c.z }
end

Evora.responders.nearbyPlayers = function(args)
    local radius = tonumber(args and args.radius) or 4.0
    local me = PlayerPedId()
    local origin = GetEntityCoords(me)
    local list = {}
    for _, player in ipairs(GetActivePlayers()) do
        local ped = GetPlayerPed(player)
        if ped ~= me and DoesEntityExist(ped) then
            local d = Utils.dist(origin, GetEntityCoords(ped))
            if d <= radius then list[#list + 1] = { source = GetPlayerServerId(player), dist = d } end
        end
    end
    return list
end

local function vehicleInfo(veh, origin)
    return {
        plate = GetVehicleNumberPlateText(veh),
        model = GetEntityModel(veh),
        netId = NetworkGetEntityIsNetworked(veh) and NetworkGetNetworkIdFromEntity(veh) or nil,
        dist = Utils.dist(origin, GetEntityCoords(veh)),
    }
end

Evora.responders.nearestVehicle = function(args)
    local radius = tonumber(args and args.radius) or 5.0
    local origin = GetEntityCoords(PlayerPedId())
    local best, bestDist
    for _, veh in ipairs(GetGamePool("CVehicle")) do
        local d = Utils.dist(origin, GetEntityCoords(veh))
        if d <= radius and (not bestDist or d < bestDist) then best, bestDist = veh, d end
    end
    return best and vehicleInfo(best, origin) or nil
end

-- plates: one plate or a list of accepted spellings (garage prefixes).
local function plateMatches(veh, plates)
    local plate = Utils.normalizePlate(GetVehicleNumberPlateText(veh) or "")
    if plate == "" then return false end
    for _, p in ipairs(type(plates) == "table" and plates or { plates }) do
        if Utils.normalizePlate(tostring(p)) == plate then return true end
    end
    return false
end

Evora.responders.vehicleByPlate = function(args)
    local radius = tonumber(args and args.radius) or 8.0
    local plates = args and (args.plates or args.plate) or {}
    local origin = GetEntityCoords(PlayerPedId())
    for _, veh in ipairs(GetGamePool("CVehicle")) do
        if plateMatches(veh, plates) and Utils.dist(origin, GetEntityCoords(veh)) <= radius then
            return vehicleInfo(veh, origin)
        end
    end
    return nil
end

RegisterNetEvent("evora_police:creq", function(id, name, args)
    local responder = Evora.responders[name]
    local value = nil
    if responder then
        local ok, result = pcall(responder, args)
        if ok then value = result end
    end
    TriggerServerEvent("evora_police:cres", id, value)
end)

---------------------------------------------------------------------------
-- Generic effects requested by the server
---------------------------------------------------------------------------
RegisterNetEvent("evora_police:teleport", function(x, y, z, heading)
    Citizen.CreateThread(function()
        local ped = PlayerPedId()
        DoScreenFadeOut(400)
        local waited = 0
        while not IsScreenFadedOut() and waited < 1000 do
            Citizen.Wait(10)
            waited = waited + 10
        end
        if IsPedInAnyVehicle(ped, false) then
            ClearPedTasksImmediately(ped)
        end
        RequestCollisionAtCoord(x, y, z)
        SetEntityCoords(ped, x + 0.0, y + 0.0, z + 0.0, false, false, false, false)
        if heading then SetEntityHeading(ped, heading + 0.0) end
        local timeout = GetGameTimer() + 3000
        while not HasCollisionLoadedAroundEntity(ped) and GetGameTimer() < timeout do
            Citizen.Wait(10)
        end
        DoScreenFadeIn(500)
    end)
end)

RegisterNetEvent("evora_police:waypoint", function(x, y)
    if x and y then
        SetNewWaypoint(x + 0.0, y + 0.0)
        PlaySoundFrontend(-1, "WAYPOINT_SET", "HUD_FRONTEND_DEFAULT_SOUNDSET", true)
    end
end)

local function loadDict(dict)
    RequestAnimDict(dict)
    local timeout = GetGameTimer() + 3000
    while not HasAnimDictLoaded(dict) and GetGameTimer() < timeout do Citizen.Wait(10) end
    return HasAnimDictLoaded(dict)
end
Evora.loadDict = loadDict

RegisterNetEvent("evora_police:anim", function(dict, anim, duration)
    Citizen.CreateThread(function()
        if not loadDict(dict) then return end
        TaskPlayAnim(PlayerPedId(), dict, anim, 8.0, -8.0, duration or 1500, 48, 0, false, false, false)
        RemoveAnimDict(dict)
    end)
end)

RegisterNetEvent("evora_police:armour", function(value)
    SetPedArmour(PlayerPedId(), math.max(0, math.min(100, tonumber(value) or 0)))
end)

RegisterNetEvent("evora_police:vehicle:delete", function(netId, plates)
    if not netId or not NetworkDoesNetworkIdExist(netId) then return end
    local veh = NetworkGetEntityFromNetworkId(netId)
    -- Only the impounded vehicle itself: never another entity behind a stale or forged net id.
    if not DoesEntityExist(veh) or GetEntityType(veh) ~= 2 or not plateMatches(veh, plates) then return end
    Citizen.CreateThread(function()
        local timeout = GetGameTimer() + 2000
        NetworkRequestControlOfEntity(veh)
        while not NetworkHasControlOfEntity(veh) and GetGameTimer() < timeout do
            Citizen.Wait(10)
            NetworkRequestControlOfEntity(veh)
        end
        SetEntityAsMissionEntity(veh, true, true)
        DeleteVehicle(veh)
    end)
end)

---------------------------------------------------------------------------
-- Session start (also after a client-side resource restart)
---------------------------------------------------------------------------
Citizen.CreateThread(function()
    while not NetworkIsPlayerActive(PlayerId()) do Citizen.Wait(500) end
    for _ = 1, 60 do
        local ok = Evora.rpc("session:init", {}, 15000)
        if ok then
            Evora.ready = true
            break
        end
        Citizen.Wait(5000)
    end
end)

AddEventHandler("onResourceStop", function(resource)
    if resource ~= GetCurrentResourceName() then return end
    SetNuiFocus(false, false)
end)
