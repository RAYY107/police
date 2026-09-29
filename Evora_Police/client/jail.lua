--[[
    Evora_Police — jail client: HUD timer (display only), perimeter report, task points.
    The remaining time is authoritative on the server; this only mirrors it.
]]

local jail = nil
local blips = {}
Evora.jailTask = { active = false }

local function clearBlips()
    for _, b in ipairs(blips) do
        if DoesBlipExist(b) then RemoveBlip(b) end
    end
    blips = {}
end

local function taskBlips(tasks)
    clearBlips()
    local bcfg = Config.Jail.Tasks and Config.Jail.Tasks.Blip
    if not bcfg or not bcfg.enabled then return end
    for _, t in ipairs(tasks or {}) do
        local b = AddBlipForCoord(t.coords.x, t.coords.y, t.coords.z)
        SetBlipSprite(b, bcfg.sprite or 566)
        SetBlipColour(b, bcfg.color or 27)
        SetBlipScale(b, bcfg.scale or 0.6)
        SetBlipAsShortRange(b, true)
        BeginTextCommandSetBlipName("STRING")
        AddTextComponentSubstringPlayerName(t.label)
        EndTextCommandSetBlipName(b)
        blips[#blips + 1] = b
    end
end

local function playTaskAnim(anim)
    local ped = PlayerPedId()
    if anim.scenario then
        TaskStartScenarioInPlace(ped, anim.scenario, 0, true)
    elseif anim.dict and anim.name and Evora.loadDict(anim.dict) then
        TaskPlayAnim(ped, anim.dict, anim.name, 8.0, -8.0, -1, 1, 0, false, false, false)
    end
end

local function runTask(task)
    if Evora.jailTask.active then return end
    Evora.jailTask.active = true
    UI.hideHint("jail")
    local ok, info = Evora.rpc("jail:taskStart", { id = task.id })
    if not ok then
        UI.notify(info, "error")
        Evora.jailTask.active = false
        return
    end
    playTaskAnim(info.anim or {})
    UI.progress(info.label, info.duration)
    local checks = (info.difficulty and info.difficulty.checks) or 1
    local startedAt = GetGameTimer()
    local duration = (info.duration or 10) * 1000
    local success = true
    local nextCheck = 1
    while GetGameTimer() - startedAt < duration do
        local ped = PlayerPedId()
        if Utils.dist(GetEntityCoords(ped), task.coords) > (task.radius or 2.0) + 0.75 or IsPedDeadOrDying(ped, true) then
            success = false
            break
        end
        local progress = (GetGameTimer() - startedAt) / duration
        if nextCheck <= checks and progress >= nextCheck / (checks + 1) then
            nextCheck = nextCheck + 1
            if not UI.skillCheck(info.difficulty or {}) then
                success = false
                break
            end
        end
        Citizen.Wait(100)
    end
    UI.stopProgress()
    ClearPedTasks(PlayerPedId())
    if success then
        local ok2, res = Evora.rpc("jail:taskComplete", { id = task.id, success = true })
        if not ok2 then
            UI.notify(res, "error")
        elseif res.capped then
            UI.notify(LocaleUI.jail_task_capped, "info")
        elseif (res.reduced or 0) > 0 then
            UI.notify(Utils.format(LocaleUI.jail_task_reduced, { time = Utils.mmss(res.reduced) }), "success")
        end
    else
        Evora.rpc("jail:taskComplete", { id = task.id, success = false })
        UI.notify(LocaleUI.jail_task_failed, "error")
    end
    Evora.jailTask.active = false
end

-- Perimeter report (useful without OneSync; the server re-validates) + task interaction.
local function loop()
    Citizen.CreateThread(function()
        local lastReport = 0
        while jail do
            local sleep = 750
            local ped = PlayerPedId()
            local pos = GetEntityCoords(ped)
            if jail.escape and jail.center and Utils.dist2d(pos, jail.center) > (jail.radius or 150) then
                if GetGameTimer() - lastReport > 3000 then
                    lastReport = GetGameTimer()
                    Citizen.CreateThread(function() Evora.rpc("jail:escaped", {}) end)
                end
            end
            local near = nil
            for _, t in ipairs(jail.tasks or {}) do
                local d = Utils.dist(pos, t.coords)
                if d < 20.0 then
                    sleep = 0
                    local m = Config.Jail.Tasks.Marker or {}
                    local col = m.color or { 139, 92, 246, 170 }
                    local sc = m.scale or { 0.45, 0.45, 0.45 }
                    DrawMarker(m.type or 21, t.coords.x, t.coords.y, t.coords.z + 0.2, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
                        sc[1], sc[2], sc[3], col[1], col[2], col[3], col[4], true, true, 2, false, nil, nil, false)
                    if d <= (t.radius or 2.0) then near = t end
                end
            end
            if near and not Evora.jailTask.active then
                UI.hint("E", Utils.format(LocaleUI.jail_task_hint, { task = near.label }), "jail")
                if IsControlJustReleased(0, 38) then
                    local task = near
                    Citizen.CreateThread(function() runTask(task) end)
                end
            elseif not Evora.jailTask.active then
                UI.hideHint("jail")
            end
            Citizen.Wait(sleep)
        end
        UI.hideHint("jail")
    end)
end

RegisterNetEvent("evora_police:jail:start", function(state)
    if type(state) ~= "table" then return end
    local wasJailed = jail ~= nil
    jail = state
    if state.hud ~= false then UI.send("jail:show", state) end
    taskBlips(state.tasks)
    if not wasJailed then loop() end
end)

RegisterNetEvent("evora_police:jail:sync", function(remaining)
    if not jail then return end
    jail.remaining = remaining
    UI.send("jail:sync", { remaining = remaining })
end)

RegisterNetEvent("evora_police:jail:escape", function(message, added)
    UI.send("jail:escape", { message = message, added = added })
    PlaySoundFrontend(-1, "CHECKPOINT_MISSED", "HUD_MINI_GAME_SOUNDSET", true)
end)

RegisterNetEvent("evora_police:jail:end", function()
    jail = nil
    clearBlips()
    UI.send("jail:hide", {})
    UI.hideHint("jail")
end)

AddEventHandler("onResourceStop", function(resource)
    if resource == GetCurrentResourceName() then clearBlips() end
end)
