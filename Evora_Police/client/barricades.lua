--[[
    Evora_Police — barricade placement preview (client)

    A local, non-networked ghost follows the officer; E places, arrows rotate, BACKSPACE
    cancels. The server validates and creates the real object (OneSync). Without OneSync the
    client creates it and the server only tracks it.
]]

local placing = false

local function loadModel(hash)
    RequestModel(hash)
    local timeout = GetGameTimer() + 3000
    while not HasModelLoaded(hash) and GetGameTimer() < timeout do Citizen.Wait(10) end
    return HasModelLoaded(hash)
end

RegisterNetEvent("evora_police:barricade:place", function(index, model, label, distance, serverSide)
    if placing then return end
    local hash = GetHashKey(model)
    if not IsModelInCdimage(hash) or not loadModel(hash) then
        UI.notify(model, "error")
        return
    end
    placing = true
    Citizen.CreateThread(function()
        local ped = PlayerPedId()
        local origin = GetEntityCoords(ped)
        local ghost = CreateObject(hash, origin.x, origin.y, origin.z, false, false, false)
        SetEntityAlpha(ghost, 160, false)
        SetEntityCollision(ghost, false, false)
        FreezeEntityPosition(ghost, true)
        local rotation = 0.0
        local confirmed = false
        UI.hint("E", label .. " — " .. LocaleUI.barricade_hint, "barricade")
        while placing do
            ped = PlayerPedId()
            local pos = GetEntityCoords(ped)
            local fwd = GetEntityForwardVector(ped)
            local x = pos.x + fwd.x * (distance or 2.2)
            local y = pos.y + fwd.y * (distance or 2.2)
            SetEntityCoords(ghost, x, y, pos.z, false, false, false, false)
            PlaceObjectOnGroundProperly(ghost)
            SetEntityHeading(ghost, GetEntityHeading(ped) + rotation)
            DisableControlAction(0, 174, true)
            DisableControlAction(0, 175, true)
            if IsDisabledControlPressed(0, 174) then rotation = rotation + 1.5 end
            if IsDisabledControlPressed(0, 175) then rotation = rotation - 1.5 end
            if IsControlJustReleased(0, 38) then
                confirmed = true
                break
            end
            if IsControlJustReleased(0, 194) or IsControlJustReleased(0, 177) or IsPedInAnyVehicle(ped, false) then
                break
            end
            Citizen.Wait(0)
        end
        local final = GetEntityCoords(ghost)
        local heading = GetEntityHeading(ghost)
        DeleteEntity(ghost)
        UI.hideHint("barricade")
        placing = false
        if not confirmed then
            SetModelAsNoLongerNeeded(hash)
            return
        end
        local payload = { index = index, x = final.x, y = final.y, z = final.z, heading = heading }
        local object
        if not serverSide then
            object = CreateObject(hash, final.x, final.y, final.z, true, true, false)
            SetEntityHeading(object, heading)
            PlaceObjectOnGroundProperly(object)
            FreezeEntityPosition(object, true)
            payload.netId = NetworkGetNetworkIdFromEntity(object)
        end
        SetModelAsNoLongerNeeded(hash)
        local ok, err = Evora.rpc("barricade:place", payload)
        if not ok then
            if object and DoesEntityExist(object) then DeleteEntity(object) end
            UI.notify(err, "error")
        else
            PlaySoundFrontend(-1, "SELECT", "HUD_FRONTEND_DEFAULT_SOUNDSET", true)
        end
    end)
end)

local barricadeModels = {}
for _, o in ipairs(Config.Barricades or {}) do
    if type(o) == "table" and type(o.model) == "string" then barricadeModels[GetHashKey(o.model)] = true end
end

-- Without OneSync the server asks every client to remove a tracked barricade. Net ids are
-- reported by the placing client, so only configured barricade props are ever deleted.
RegisterNetEvent("evora_police:barricade:delete", function(netId)
    if not netId or not NetworkDoesNetworkIdExist(netId) then return end
    local object = NetworkGetEntityFromNetworkId(netId)
    if not DoesEntityExist(object) or GetEntityType(object) ~= 3 or not barricadeModels[GetEntityModel(object)] then return end
    if NetworkHasControlOfEntity(object) then DeleteEntity(object) end
end)
