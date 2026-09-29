--[[
    Evora_Police — client-side integration adapters.
    Used when an integration type is "builtin", "client_export" or when no server system exists.
]]

local function cfg(name) return (Config.Integrations and Config.Integrations[name]) or {} end

---------------------------------------------------------------------------
-- Notifications ("client_export" / "builtin")
---------------------------------------------------------------------------
RegisterNetEvent("evora_police:notify", function(message, kind, duration)
    local c = cfg("Notify")
    if c.type == "client_export" and type(c.resource) == "string" and GetResourceState(c.resource) == "started" then
        local args = { message }
        if type(c.format) == "function" then
            local ok, a = pcall(c.format, message, kind, duration)
            if ok and type(a) == "table" then args = a end
        end
        local ok = pcall(function() exports[c.resource][c.fn](exports[c.resource], table.unpack(args)) end)
        if ok then return end
    end
    UI.notify(message, kind, duration)
end)

---------------------------------------------------------------------------
-- Radio ("client_export")
---------------------------------------------------------------------------
RegisterNetEvent("evora_police:radio", function(code)
    local c = cfg("Radio")
    if c.type ~= "client_export" or type(c.resource) ~= "string" or GetResourceState(c.resource) ~= "started" then
        print("[Evora_Police] Radio integration unavailable.")
        return
    end
    local args = { code }
    if type(c.format) == "function" then
        local ok, a = pcall(c.format, code, {})
        if ok and type(a) == "table" then args = a end
    end
    pcall(function() exports[c.resource][c.fn](exports[c.resource], table.unpack(args)) end)
end)

---------------------------------------------------------------------------
-- Handcuffs (builtin)
---------------------------------------------------------------------------
local cuffed = false

local function applyCuffs(state)
    cuffed = state == true
    local ped = PlayerPedId()
    SetEnableHandcuffs(ped, cuffed)
    if cuffed then
        Citizen.CreateThread(function()
            if Evora.loadDict("mp_arresting") then
                TaskPlayAnim(ped, "mp_arresting", "idle", 8.0, -8.0, -1, 49, 0, false, false, false)
            end
            while cuffed do
                local p = PlayerPedId()
                DisableControlAction(0, 21, true)  -- sprint
                DisableControlAction(0, 22, true)  -- jump
                DisableControlAction(0, 24, true)  -- attack
                DisableControlAction(0, 25, true)  -- aim
                DisableControlAction(0, 140, true) -- melee
                DisableControlAction(0, 141, true)
                DisableControlAction(0, 142, true)
                DisableControlAction(0, 257, true)
                DisableControlAction(0, 263, true)
                DisableControlAction(0, 75, true)  -- leave vehicle
                DisablePlayerFiring(PlayerId(), true)
                if not IsEntityPlayingAnim(p, "mp_arresting", "idle", 3) and not IsPedInAnyVehicle(p, false)
                    and not (Evora.jailTask and Evora.jailTask.active) then
                    TaskPlayAnim(p, "mp_arresting", "idle", 8.0, -8.0, -1, 49, 0, false, false, false)
                end
                Citizen.Wait(0)
            end
        end)
    else
        ClearPedSecondaryTask(ped)
        StopAnimTask(ped, "mp_arresting", "idle", 1.0)
    end
end

RegisterNetEvent("evora_police:cuff:set", function(state) applyCuffs(state) end)
Evora.responders["cuff:get"] = function() return cuffed end

---------------------------------------------------------------------------
-- Drag (builtin): the target attaches to the officer
---------------------------------------------------------------------------
local dragger = nil

RegisterNetEvent("evora_police:drag", function(officerSource)
    local ped = PlayerPedId()
    if dragger then
        dragger = nil
        DetachEntity(ped, true, false)
        return
    end
    local officerPlayer = GetPlayerFromServerId(officerSource)
    if officerPlayer == -1 then return end
    dragger = officerSource
    Citizen.CreateThread(function()
        while dragger do
            local officerPed = GetPlayerPed(GetPlayerFromServerId(dragger))
            local me = PlayerPedId()
            if not DoesEntityExist(officerPed) or IsPedInAnyVehicle(me, false) or IsPedDeadOrDying(me, true) then
                dragger = nil
                DetachEntity(me, true, false)
                break
            end
            if not IsEntityAttachedToEntity(me, officerPed) then
                AttachEntityToEntity(me, officerPed, GetPedBoneIndex(officerPed, 11816), 0.45, 0.45, 0.0, 0.0, 0.0, 0.0, false, false, false, false, 2, true)
            end
            Citizen.Wait(250)
        end
    end)
end)

---------------------------------------------------------------------------
-- Seats (builtin)
---------------------------------------------------------------------------
local function nearestVehicle(radius)
    local origin = GetEntityCoords(PlayerPedId())
    local best, bestDist
    for _, veh in ipairs(GetGamePool("CVehicle")) do
        local d = Utils.dist(origin, GetEntityCoords(veh))
        if d <= radius and (not bestDist or d < bestDist) then best, bestDist = veh, d end
    end
    return best
end

RegisterNetEvent("evora_police:seat:putIn", function(radius)
    local veh = nearestVehicle(tonumber(radius) or 6.0)
    if not veh then return end
    if dragger then
        dragger = nil
        DetachEntity(PlayerPedId(), true, false)
    end
    local seats = GetVehicleMaxNumberOfPassengers(veh)
    for seat = seats - 1, 0, -1 do
        if IsVehicleSeatFree(veh, seat) then
            TaskWarpPedIntoVehicle(PlayerPedId(), veh, seat)
            return
        end
    end
end)

RegisterNetEvent("evora_police:seat:pullOut", function()
    local ped = PlayerPedId()
    if IsPedInAnyVehicle(ped, false) then
        TaskLeaveVehicle(ped, GetVehiclePedIsIn(ped, false), 16)
    end
end)

---------------------------------------------------------------------------
-- Clothing (builtin) — same format as vRP customization
---------------------------------------------------------------------------
Evora.responders["clothing:get"] = function()
    local ped = PlayerPedId()
    local custom = { modelhash = GetEntityModel(ped) }
    for i = 0, 11 do
        custom[i] = { GetPedDrawableVariation(ped, i), GetPedTextureVariation(ped, i), GetPedPaletteVariation(ped, i) }
    end
    for i = 0, 7 do
        custom["p" .. i] = { GetPedPropIndex(ped, i), math.max(GetPedPropTextureIndex(ped, i), 0) }
    end
    return custom
end

RegisterNetEvent("evora_police:clothing:set", function(custom)
    if type(custom) ~= "table" then return end
    local ped = PlayerPedId()
    for key, value in pairs(custom) do
        if type(value) == "table" then
            local prop = type(key) == "string" and key:match("^p(%d+)$")
            if prop then
                if (tonumber(value[1]) or -1) < 0 then
                    ClearPedProp(ped, tonumber(prop))
                else
                    SetPedPropIndex(ped, tonumber(prop), tonumber(value[1]), tonumber(value[2]) or 0, true)
                end
            elseif tonumber(key) then
                SetPedComponentVariation(ped, tonumber(key), tonumber(value[1]) or 0, tonumber(value[2]) or 0, tonumber(value[3]) or 2)
            end
        end
    end
end)

---------------------------------------------------------------------------
-- Weapons (builtin)
---------------------------------------------------------------------------
local KNOWN_WEAPONS = {
    "WEAPON_KNIFE", "WEAPON_NIGHTSTICK", "WEAPON_HAMMER", "WEAPON_BAT", "WEAPON_CROWBAR", "WEAPON_FLASHLIGHT",
    "WEAPON_MACHETE", "WEAPON_SWITCHBLADE", "WEAPON_KNUCKLE", "WEAPON_PISTOL", "WEAPON_PISTOL_MK2",
    "WEAPON_COMBATPISTOL", "WEAPON_APPISTOL", "WEAPON_STUNGUN", "WEAPON_PISTOL50", "WEAPON_SNSPISTOL",
    "WEAPON_HEAVYPISTOL", "WEAPON_VINTAGEPISTOL", "WEAPON_REVOLVER", "WEAPON_MICROSMG", "WEAPON_SMG",
    "WEAPON_ASSAULTSMG", "WEAPON_COMBATPDW", "WEAPON_MACHINEPISTOL", "WEAPON_MINISMG", "WEAPON_PUMPSHOTGUN",
    "WEAPON_SAWNOFFSHOTGUN", "WEAPON_ASSAULTSHOTGUN", "WEAPON_BULLPUPSHOTGUN", "WEAPON_ASSAULTRIFLE",
    "WEAPON_CARBINERIFLE", "WEAPON_ADVANCEDRIFLE", "WEAPON_SPECIALCARBINE", "WEAPON_BULLPUPRIFLE",
    "WEAPON_COMPACTRIFLE", "WEAPON_MG", "WEAPON_COMBATMG", "WEAPON_GUSENBERG", "WEAPON_SNIPERRIFLE",
    "WEAPON_HEAVYSNIPER", "WEAPON_MARKSMANRIFLE", "WEAPON_GRENADE", "WEAPON_BZGAS", "WEAPON_MOLOTOV",
    "WEAPON_SMOKEGRENADE", "WEAPON_FLARE", "WEAPON_PETROLCAN", "WEAPON_FIREEXTINGUISHER",
}

Evora.responders["weapons:get"] = function()
    local ped = PlayerPedId()
    local out = {}
    for _, name in ipairs(KNOWN_WEAPONS) do
        local hash = GetHashKey(name)
        if HasPedGotWeapon(ped, hash, false) then out[name] = { ammo = GetAmmoInPedWeapon(ped, hash) } end
    end
    return out
end

RegisterNetEvent("evora_police:weapons:clear", function()
    RemoveAllPedWeapons(PlayerPedId(), true)
end)

RegisterNetEvent("evora_police:weapons:give", function(weapons)
    local ped = PlayerPedId()
    for name, data in pairs(weapons or {}) do
        GiveWeaponToPed(ped, GetHashKey(name), tonumber(type(data) == "table" and data.ammo) or 0, false, false)
    end
end)

---------------------------------------------------------------------------
-- Identity presentation (the target shows the card)
---------------------------------------------------------------------------
RegisterNetEvent("evora_police:idcard:present", function()
    local a = Config.IdCard and Config.IdCard.Animation
    if not a then return end
    Citizen.CreateThread(function()
        if Evora.loadDict(a.dict) then
            TaskPlayAnim(PlayerPedId(), a.dict, a.name, 8.0, -8.0, a.duration or 1500, 48, 0, false, false, false)
            RemoveAnimDict(a.dict)
        end
    end)
end)
