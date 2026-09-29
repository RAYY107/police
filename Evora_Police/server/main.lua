--[[
    Evora_Police — start-up sequence, player lifecycle and exports.
]]

local P, Gov, DB, F = Evora.Players, Evora.Gov, Evora.DB, Evora.Framework

local dropped = {}

local function ready(user_id, source, restored)
    user_id, source = tonumber(user_id), tonumber(source)
    if not user_id or not source or not GetPlayerName(source) then return end
    dropped[source] = nil
    P.attach(user_id, source)
    P.remember(user_id, source)
    Evora.debug("groups", "player ready %d (source %d)%s", user_id, source, restored and " [restored]" or "")
    Evora.emit("playerReady", user_id, source, restored == true)
end

local function drop(user_id, source)
    user_id, source = tonumber(user_id), tonumber(source)
    if source then
        if dropped[source] then return end
        dropped[source] = true
    end
    if not user_id then return end
    Evora.emit("playerDropped", user_id, source)
    Evora.Confirm.cancelFor(source)
    Evora.Integrations.Popup.cancelFor(source)
    Evora.Spectate.onDropped(source)
    Evora.Menu.forget(source)
    Evora.RPC.forget(source)
    Gov.forget(user_id)
    P.detach(user_id, source)
    SetTimeout(10000, function() dropped[source] = nil end)
end

---------------------------------------------------------------------------
-- vRP lifecycle
---------------------------------------------------------------------------
AddEventHandler("vRP:playerJoin", function(user_id, source)
    if tonumber(user_id) and tonumber(source) then P.attach(user_id, source) end
end)

AddEventHandler("vRP:playerSpawn", function(user_id, source, first_spawn)
    if not Evora.ready then return end
    if first_spawn then
        ready(user_id, source, false)
    else
        Evora.emit("playerRespawn", tonumber(user_id), tonumber(source))
    end
end)

AddEventHandler("vRP:playerLeave", function(user_id, source)
    drop(user_id, source)
end)

AddEventHandler("playerDropped", function()
    local src = source
    drop(P.bySource[src], src)
end)

-- Group changes made anywhere (vRP admin menu, other scripts) refresh the profile.
local pendingRefresh = {}
local function refreshLater(user_id)
    user_id = tonumber(user_id)
    if not user_id or pendingRefresh[user_id] then return end
    pendingRefresh[user_id] = true
    SetTimeout(300, function()
        pendingRefresh[user_id] = nil
        if P.isOnline(user_id) then
            Evora.thread(function() Gov.getProfile(user_id, true) end)
        end
    end)
end
AddEventHandler("vRP:playerJoinGroup", function(user_id) refreshLater(user_id) end)
AddEventHandler("vRP:playerLeaveGroup", function(user_id) refreshLater(user_id) end)

-- Periodic safety net for group changes that raise no event.
Citizen.CreateThread(function()
    while true do
        Citizen.Wait(60000)
        if Evora.ready then
            for uid in pairs(P.byUser) do Gov.getProfile(uid, true) end
        end
    end
end)

---------------------------------------------------------------------------
-- Client session (client resource restarts ask for their state again)
---------------------------------------------------------------------------
Evora.RPC.register("session:init", {}, function(ctx)
    Evora.Officers.pushState(ctx.user_id)
    local jail = Evora.Jail.active[ctx.user_id]
    if jail and not jail.pendingRelease then
        TriggerClientEvent("evora_police:jail:start", ctx.source, Evora.Jail.clientState(jail))
    end
    local alerts = {}
    for _, a in pairs(Evora.Alert.active) do alerts[#alerts + 1] = Evora.Alert.public(a) end
    if #alerts > 0 then TriggerClientEvent("evora_police:alert:sync", ctx.source, alerts) end
    return { user_id = ctx.user_id }
end)

---------------------------------------------------------------------------
-- Start-up
---------------------------------------------------------------------------
Citizen.CreateThread(function()
    math.randomseed(os.time())
    Evora.print("Evora_Police v%s — Made By LR", Evora.version)
    F.init()
    DB.init()
    Gov.build()
    Gov.validateGroups()
    Evora.Integrations.checkAll()
    if DB.ready then
        Evora.Vacation.load()
        Evora.Jail.load()
        Evora.Impound.load()
    end
    if F.available then
        for uid, src in pairs(F.getUsers()) do
            if GetPlayerName(src) then P.attach(uid, src) end
        end
    end
    if DB.ready then Evora.Officers.recoverSessions() end
    Evora.PoliceMenu.register()
    Evora.ready = true
    for uid, src in pairs(P.byUser) do
        Evora.thread(ready, uid, src, true)
    end
    Evora.print("ready — %d ministries, %d sectors, %d ranks, %d players attached.",
        #Gov.ministryList, #Gov.sectorList, #Gov.rankList, Utils.count(P.byUser))
end)

---------------------------------------------------------------------------
-- Exports
---------------------------------------------------------------------------
exports("IsOnDuty", function(user_id) return Evora.Officers.isOnDuty(user_id) end)
exports("IsJailed", function(user_id) return Evora.Jail.isJailed(user_id) end)
exports("IsOnVacation", function(user_id) return Evora.Vacation.isOnVacation(user_id) end)
exports("GetOfficerProfile", function(user_id)
    local summary = Gov.summary(Gov.cached(user_id))
    summary.onDuty = Evora.Officers.isOnDuty(user_id)
    return summary
end)
exports("HasPermission", function(user_id, perm) return Gov.has(Gov.cached(user_id), perm) end)
