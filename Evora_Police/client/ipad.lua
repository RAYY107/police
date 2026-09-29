--[[
    Evora_Police — القائمة العسكرية (police iPad) controller.
    Opening is decided by the server (Ipad.open); every tab loads its data through RPC.
]]

local open = false
local prop = nil

local function startTabletAnim()
    local c = Config.Ipad or {}
    if not c.Animation then return end
    Citizen.CreateThread(function()
        local ped = PlayerPedId()
        if IsPedInAnyVehicle(ped, false) then return end
        if not Evora.loadDict(c.AnimDict) then return end
        local hash = GetHashKey(c.Prop or "prop_cs_tablet")
        RequestModel(hash)
        local timeout = GetGameTimer() + 2000
        while not HasModelLoaded(hash) and GetGameTimer() < timeout do Citizen.Wait(10) end
        if not open then return end
        local coords = GetEntityCoords(ped)
        prop = CreateObject(hash, coords.x, coords.y, coords.z + 0.2, true, true, false)
        AttachEntityToEntity(prop, ped, GetPedBoneIndex(ped, 28422), -0.05, 0.0, 0.0, 0.0, 0.0, 0.0, true, true, false, true, 1, true)
        SetModelAsNoLongerNeeded(hash)
        TaskPlayAnim(ped, c.AnimDict, c.AnimName, 3.0, 3.0, -1, 49, 0, false, false, false)
    end)
end

local function stopTabletAnim()
    local c = Config.Ipad or {}
    if prop and DoesEntityExist(prop) then
        DetachEntity(prop, true, false)
        DeleteEntity(prop)
    end
    prop = nil
    if c.AnimDict then StopAnimTask(PlayerPedId(), c.AnimDict, c.AnimName, 1.0) end
end

function Evora.openIpad(tab)
    if open then
        UI.send("ipad:tab", { tab = tab or "office" })
        return
    end
    open = true
    UI.send("ipad:open", { tab = tab or "office" })
    UI.focus("ipad", true, true)
    startTabletAnim()
end

function Evora.closeIpad()
    if not open then return end
    open = false
    UI.send("ipad:close", {})
    UI.focus("ipad", false)
    stopTabletAnim()
end

RegisterNetEvent("evora_police:ipad:open", function(tab)
    Evora.openIpad(tab)
end)

RegisterNetEvent("evora_police:ipad:push", function(kind, data)
    UI.send("ipad:push", { type = kind, data = data })
end)

AddEventHandler("evora_police:client:closed", function(layer)
    if layer == "ipad" and open then
        open = false
        stopTabletAnim()
    end
end)

-- Monitoring from the iPad closes the tablet first (spectate takes the camera).
AddEventHandler("evora_police:client:spectateStarting", function()
    Evora.closeIpad()
end)

do
    local c = Config.Ipad or {}
    if c.Command then
        RegisterCommand(c.Command, function()
            Citizen.CreateThread(function()
                local ok, err = Evora.rpc("ipad:bootstrap", {})
                if ok then Evora.openIpad("office") elseif err then UI.notify(err, "error") end
            end)
        end, false)
        if c.Key then RegisterKeyMapping(c.Command, "Evora_Police — القائمة العسكرية", "keyboard", c.Key) end
    end
end

AddEventHandler("onResourceStop", function(resource)
    if resource == GetCurrentResourceName() then stopTabletAnim() end
end)
