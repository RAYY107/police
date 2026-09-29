--[[
    Evora_Police — security alert effects (client)

    exempt = true  : this player was inside the zone when the alert started → not affected
                     (until they leave, if ExemptionEndsOnExit)
    exempt = false : affected whenever inside the zone
    exempt = nil   : decided at receipt (servers without OneSync)
]]

local alerts = {}      -- [id] = { data, exempt, blips }
local monitoring = false
local affected = false
local limitedVehicle = nil

local function makeBlips(a)
    local list = {}
    local z = a.mapZone or {}
    if z.enabled ~= false then
        local radius = AddBlipForRadius(a.coords.x, a.coords.y, a.coords.z, a.radius + 0.0)
        SetBlipColour(radius, z.color or 1)
        SetBlipAlpha(radius, z.alpha or 110)
        list[#list + 1] = radius
        if z.blip and z.blip.enabled ~= false then
            local b = AddBlipForCoord(a.coords.x, a.coords.y, a.coords.z)
            SetBlipSprite(b, z.blip.sprite or 161)
            SetBlipColour(b, z.blip.color or 1)
            SetBlipScale(b, z.blip.scale or 1.2)
            SetBlipAsShortRange(b, false)
            BeginTextCommandSetBlipName("STRING")
            AddTextComponentSubstringPlayerName(z.blip.label or a.label)
            EndTextCommandSetBlipName(b)
            list[#list + 1] = b
        end
    end
    return list
end

local function removeBlips(entry)
    for _, b in ipairs(entry.blips or {}) do
        if DoesBlipExist(b) then RemoveBlip(b) end
    end
end

local function resetVehicle()
    if limitedVehicle and DoesEntityExist(limitedVehicle) then SetVehicleMaxSpeed(limitedVehicle, 0.0) end
    limitedVehicle = nil
end

local function setAffected(state, data)
    if affected == state then return end
    affected = state
    UI.send("alert:status", { active = state, label = data and data.label or "" })
    if not state then
        resetVehicle()
        SetPedMoveRateOverride(PlayerPedId(), 1.0)
        return
    end
    -- Per-frame effects only while affected.
    Citizen.CreateThread(function()
        while affected do
            local ped = PlayerPedId()
            local p = data.player or {}
            if p.enabled ~= false then
                if p.disableSprint ~= false then DisableControlAction(0, 21, true) end
                if p.disableJump then DisableControlAction(0, 22, true) end
                if p.moveRate then SetPedMoveRateOverride(ped, p.moveRate + 0.0) end
            end
            local v = data.vehicle or {}
            if v.enabled ~= false and IsPedInAnyVehicle(ped, false) then
                local veh = GetVehiclePedIsIn(ped, false)
                if GetPedInVehicleSeat(veh, -1) == ped and limitedVehicle ~= veh then
                    resetVehicle()
                    limitedVehicle = veh
                    SetVehicleMaxSpeed(veh, (v.maxSpeed or 40.0) / 3.6)
                end
            elseif limitedVehicle then
                resetVehicle()
            end
            Citizen.Wait(0)
        end
    end)
end

local function monitor()
    if monitoring then return end
    monitoring = true
    Citizen.CreateThread(function()
        while next(alerts) do
            local pos = GetEntityCoords(PlayerPedId())
            local hit = nil
            local interval = 400
            for _, entry in pairs(alerts) do
                local a = entry.data
                interval = a.interval or interval
                local inside = Utils.dist2d(pos, a.coords) <= a.radius
                if entry.exempt and not inside and a.exemptionEndsOnExit ~= false then entry.exempt = false end
                local officerExempt = a.exemptOfficers and Evora.state.onDuty
                if inside and not entry.exempt and not officerExempt then hit = a end
            end
            setAffected(hit ~= nil, hit)
            Citizen.Wait(interval)
        end
        setAffected(false)
        monitoring = false
    end)
end

local function add(data, exempt)
    if alerts[data.id] then removeBlips(alerts[data.id]) end
    if exempt == nil then
        exempt = Utils.dist2d(GetEntityCoords(PlayerPedId()), data.coords) <= data.radius
    end
    alerts[data.id] = { data = data, exempt = exempt == true, blips = makeBlips(data) }
    monitor()
end

RegisterNetEvent("evora_police:alert:start", function(data, exempt)
    if type(data) == "table" then add(data, exempt) end
end)

-- Alerts that were already running when this player joined: never exempt.
RegisterNetEvent("evora_police:alert:sync", function(list)
    for _, data in ipairs(list or {}) do
        if not alerts[data.id] then add(data, false) end
    end
end)

RegisterNetEvent("evora_police:alert:stop", function(id)
    local entry = alerts[id]
    if not entry then return end
    removeBlips(entry)
    alerts[id] = nil
    if not next(alerts) then setAffected(false) end
end)

AddEventHandler("onResourceStop", function(resource)
    if resource ~= GetCurrentResourceName() then return end
    for _, entry in pairs(alerts) do removeBlips(entry) end
    alerts = {}
    affected = false
    resetVehicle()
    SetPedMoveRateOverride(PlayerPedId(), 1.0)
end)
