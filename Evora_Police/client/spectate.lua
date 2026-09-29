--[[
    Evora_Police — reusable spectate client (officer monitoring + prisoner monitoring)

    Saves the admin's position / vehicle / visibility, hides the admin near the target so the
    target streams in, follows the target, and restores everything when stopped (manually,
    when the target leaves, or when the resource stops).
]]

local session = nil

local function restoreSelf(s)
    local ped = PlayerPedId()
    NetworkSetInSpectatorMode(false, ped)
    FreezeEntityPosition(ped, false)
    SetEntityCollision(ped, true, true)
    SetEntityVisible(ped, true, false)
    NetworkSetEntityInvisibleToNetwork(ped, false)
    SetEntityInvincible(ped, false)
    if s and s.origin then
        RequestCollisionAtCoord(s.origin.x, s.origin.y, s.origin.z)
        SetEntityCoords(ped, s.origin.x, s.origin.y, s.origin.z, false, false, false, false)
        SetEntityHeading(ped, s.heading or 0.0)
        if s.vehicle and DoesEntityExist(s.vehicle) and IsVehicleSeatFree(s.vehicle, s.seat or -1) then
            TaskWarpPedIntoVehicle(ped, s.vehicle, s.seat or -1)
        end
    end
end

local function stop(reason, silentServer)
    local s = session
    if not s then return end
    session = nil
    UI.send("spectate:hide", {})
    DoScreenFadeOut(200)
    Citizen.Wait(250)
    restoreSelf(s)
    Citizen.Wait(200)
    DoScreenFadeIn(400)
    if not silentServer then
        Citizen.CreateThread(function() Evora.rpc("spectate:stop", {}) end)
    end
    Evora.debug("spectate", "stopped (%s)", tostring(reason))
end

local function start(data)
    if session then stop("switch", true) end
    TriggerEvent("evora_police:client:spectateStarting")
    local ped = PlayerPedId()
    local veh = GetVehiclePedIsIn(ped, false)
    local seat = nil
    if veh ~= 0 then
        for s = -1, GetVehicleMaxNumberOfPassengers(veh) - 1 do
            if GetPedInVehicleSeat(veh, s) == ped then seat = s end
        end
    end
    local origin = GetEntityCoords(ped)
    session = {
        target = data.target, id = data.id, name = data.name, kind = data.kind,
        origin = { x = origin.x, y = origin.y, z = origin.z }, heading = GetEntityHeading(ped),
        vehicle = veh ~= 0 and veh or nil, seat = seat, targetCoords = data.coords,
    }
    local s = session
    Citizen.CreateThread(function()
        DoScreenFadeOut(250)
        Citizen.Wait(300)
        local me = PlayerPedId()
        if IsPedInAnyVehicle(me, false) then ClearPedTasksImmediately(me) end
        SetEntityVisible(me, false, false)
        NetworkSetEntityInvisibleToNetwork(me, true)
        SetEntityCollision(me, false, false)
        SetEntityInvincible(me, true)
        FreezeEntityPosition(me, true)
        local c = s.targetCoords
        if c then
            RequestCollisionAtCoord(c.x, c.y, c.z)
            SetEntityCoords(me, c.x, c.y, c.z - 15.0, false, false, false, false)
        end
        -- wait for the target ped to stream in
        local targetPed = 0
        local timeout = GetGameTimer() + 5000
        while session == s and GetGameTimer() < timeout do
            local player = GetPlayerFromServerId(s.target)
            if player ~= -1 then
                targetPed = GetPlayerPed(player)
                if DoesEntityExist(targetPed) then break end
            end
            Citizen.Wait(50)
        end
        DoScreenFadeIn(400)
        if session ~= s then return end
        if not DoesEntityExist(targetPed) then
            UI.notify(L("err_target_offline"), "error")
            stop("not_streamed")
            return
        end
        NetworkSetInSpectatorMode(true, targetPed)
        UI.send("spectate:show", { name = s.name, id = s.id, kind = s.kind, key = Config.Spectate.StopKeyLabel })

        local lastFollow = 0
        while session == s do
            local now = GetGameTimer()
            local player = GetPlayerFromServerId(s.target)
            local tp = player ~= -1 and GetPlayerPed(player) or 0
            if now - lastFollow > (Config.Spectate.FollowInterval or 500) then
                lastFollow = now
                local tc = DoesEntityExist(tp) and GetEntityCoords(tp) or s.targetCoords
                if tc then SetEntityCoords(PlayerPedId(), tc.x, tc.y, tc.z - 15.0, false, false, false, false) end
                if DoesEntityExist(tp) then NetworkSetInSpectatorMode(true, tp) end
            end
            DisableControlAction(0, Config.Spectate.StopKey or 194, true)
            if IsDisabledControlJustReleased(0, Config.Spectate.StopKey or 194) then
                stop("manual")
                break
            end
            Citizen.Wait(0)
        end
    end)
end

RegisterNetEvent("evora_police:spectate:start", function(data)
    if type(data) == "table" then start(data) end
end)

RegisterNetEvent("evora_police:spectate:stop", function(reason)
    if not session then return end
    if reason == "target_left" then UI.notify(L("err_target_offline"), "info") end
    Citizen.CreateThread(function() stop(reason, true) end)
end)

RegisterNetEvent("evora_police:spectate:coords", function(coords)
    if session and type(coords) == "table" then session.targetCoords = coords end
end)

RegisterNUICallback("spectateStop", function(_, cb)
    if session then Citizen.CreateThread(function() stop("manual") end) end
    cb({ ok = true })
end)

if Config.Spectate and Config.Spectate.Command then
    RegisterCommand(Config.Spectate.Command, function()
        if session then Citizen.CreateThread(function() stop("command") end) end
    end, false)
end

-- Never leave an admin hidden and frozen when the resource stops.
AddEventHandler("onResourceStop", function(resource)
    if resource ~= GetCurrentResourceName() or not session then return end
    local s = session
    session = nil
    restoreSelf(s)
    DoScreenFadeIn(0)
end)
