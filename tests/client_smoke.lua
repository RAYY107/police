--[[
    Client smoke test: loads every client script (manifest order) against mocked natives, then
    drives each server → client event, NUI callback, command and responder at least once.
    Fails on any Lua error and checks the key client-side behaviours.

        lua5.4 tests/client_smoke.lua
]]
package.path = "tests/?.lua;" .. package.path
local S = require("harness.scheduler")
local json = require("harness.json")
local FiveM = require("harness.fivem")
local vector3, joaat = FiveM.vector3, FiveM.joaat

local ROOT = "Evora_Police/"
local C = {
    handlers = {}, nui = {}, messages = {}, sent = {}, rpcs = {}, cres = {}, commands = {},
    controls = {}, entities = {}, seq = 1000, blips = 0, focus = { false, false },
    pos = vector3(0.0, 0.0, 30.0), rpcReplies = {},
}

---------------------------------------------------------------------------
-- Natives with meaningful results; every other native used by the scripts is a no-op.
---------------------------------------------------------------------------
local N = {}
local function yes() return true end
local function no() return false end
local function zero() return 0 end

local function consume(key)
    if C.controls[key] then
        C.controls[key] = nil
        return true
    end
    return false
end

local function addHandler(name, fn)
    C.handlers[name] = C.handlers[name] or {}
    table.insert(C.handlers[name], fn)
end

local function fire(name, ...)
    for _, fn in ipairs(C.handlers[name] or {}) do S.spawnNow(fn, ...) end
end

local function serverReceive(name, ...)
    C.sent[#C.sent + 1] = { name = name, args = table.pack(...) }
    if name == "evora_police:rpc" then
        local id, rpcName, payload = ...
        C.rpcs[#C.rpcs + 1] = { name = rpcName, payload = payload }
        local reply = C.rpcReplies[rpcName]
        local ok, data = true, {}
        if type(reply) == "function" then ok, data = reply(payload) elseif reply ~= nil then data = reply end
        S.setTimeout(30, function() fire("evora_police:rpc:res", id, ok, data) end)
    elseif name == "evora_police:cres" then
        local id, value = ...
        C.cres[id] = { value = value }
    end
end

N.PlayerPedId = function() return 1 end
N.PlayerId = function() return 0 end
N.GetPlayerPed = function(player) if player == 0 then return 1 elseif player == 1 then return 2 end return 0 end
N.GetActivePlayers = function() return { 0, 1 } end
N.GetPlayerServerId = function(player) return player == 0 and 1 or 2 end
N.GetPlayerFromServerId = function(src) if src == 1 then return 0 elseif src == 2 then return 1 end return -1 end
N.GetEntityCoords = function(e)
    if e == 1 then return C.pos end
    if e == 2 then return vector3(C.pos.x + 1.5, C.pos.y, C.pos.z) end
    local ent = C.entities[e]
    return ent and ent.coords or vector3(0.0, 0.0, 0.0)
end
N.GetEntityHeading = function() return 90.0 end
N.GetEntityForwardVector = function() return vector3(0.0, 1.0, 0.0) end
N.GetEntityModel = function(e) local ent = C.entities[e] return ent and ent.model or joaat("mp_m_freemode_01") end
N.GetEntityType = function(e)
    if e == 1 or e == 2 then return 1 end
    local ent = C.entities[e]
    return ent and ent.type or 0
end
N.DoesEntityExist = function(e) return e == 1 or e == 2 or C.entities[e] ~= nil end
N.GetGameTimer = function() return S.now end
N.GetHashKey = joaat
N.GetGamePool = function(pool)
    local out = {}
    for id, ent in pairs(C.entities) do
        if pool == "CVehicle" and ent.type == 2 then out[#out + 1] = id end
    end
    table.sort(out)
    return out
end
N.GetVehicleNumberPlateText = function(v) local ent = C.entities[v] return ent and ent.plate or "" end
N.CreateObject = function(hash, x, y, z)
    C.seq = C.seq + 1
    C.entities[C.seq] = { type = 3, model = hash, coords = vector3(x, y, z) }
    return C.seq
end
N.SetEntityCoords = function(e, x, y, z)
    if e == 1 then C.pos = vector3(x, y, z) elseif C.entities[e] then C.entities[e].coords = vector3(x, y, z) end
end
N.DeleteEntity = function(e) C.entities[e] = nil end
N.DeleteVehicle = function(e) C.entities[e] = nil end
N.NetworkGetNetworkIdFromEntity = function(e) return e end
N.NetworkGetEntityFromNetworkId = function(id) return id end
N.NetworkDoesNetworkIdExist = function(id) return C.entities[id] ~= nil end
N.NetworkGetEntityIsNetworked = yes
N.NetworkHasControlOfEntity = yes
N.NetworkIsPlayerActive = yes
N.HasModelLoaded = yes
N.HasAnimDictLoaded = yes
N.HasCollisionLoadedAroundEntity = yes
N.IsScreenFadedOut = yes
N.IsModelInCdimage = yes
N.IsControlJustReleased = function(_, key) return consume(key) end
N.IsDisabledControlJustReleased = function(_, key) return consume(key) end
N.IsDisabledControlPressed = no
N.GetResourceState = function() return "missing" end
N.GetCurrentResourceName = function() return "Evora_Police" end
N.AddBlipForCoord = function() C.blips = C.blips + 1 return C.blips end
N.AddBlipForRadius = N.AddBlipForCoord
N.DoesBlipExist = yes
N.IsPedInAnyVehicle = no
N.GetVehiclePedIsIn = zero
N.GetPedInVehicleSeat = zero
N.GetVehicleMaxNumberOfPassengers = function() return 3 end
N.IsVehicleSeatFree = yes
N.GetPedDrawableVariation = zero
N.GetPedTextureVariation = zero
N.GetPedPaletteVariation = zero
N.GetPedPropIndex = function() return -1 end
N.GetPedPropTextureIndex = function() return -1 end
N.HasPedGotWeapon = function(_, hash) return hash == joaat("WEAPON_PISTOL") end
N.GetAmmoInPedWeapon = function() return 30 end
N.IsEntityAttachedToEntity = no
N.IsEntityPlayingAnim = no
N.IsPedDeadOrDying = no
N.GetPedBoneIndex = zero
N.SendNUIMessage = function(msg) C.messages[#C.messages + 1] = msg end
N.SetNuiFocus = function(a, b) C.focus = { a, b } end
N.RegisterNUICallback = function(name, fn) C.nui[name] = fn end
N.RegisterNetEvent = function(name, fn) if fn then addHandler(name, fn) end end
N.AddEventHandler = addHandler
N.TriggerEvent = fire
N.TriggerServerEvent = serverReceive
N.RegisterCommand = function(name, fn) C.commands[name] = fn end

-- Globals the scripts read, found with luac; anything not implemented above becomes a no-op.
local OWN = {
    Evora = true, UI = true, Config = true, Utils = true, L = true, Locale = true, LocaleUI = true,
    Citizen = true, exports = true, promise = true, json = true, vector3 = true, vec3 = true,
}
local function scriptGlobals(files)
    local names = {}
    for _, f in ipairs(files) do
        local p = io.popen("luac5.4 -l -l -p " .. ROOT .. f .. " 2>/dev/null")
        for line in p:lines() do
            local name = line:match('[GS]ETTABUP.-_ENV "([%a_][%w_]*)"')
            if name then names[name] = true end
        end
        p:close()
    end
    return names
end

---------------------------------------------------------------------------
-- Environment
---------------------------------------------------------------------------
local function manifestLists()
    local src = assert(io.open(ROOT .. "fxmanifest.lua")):read("a")
    local function list(key)
        local block = src:match(key .. "%s*(%b{})")
        local out = {}
        for f in block:gmatch("'([^']+%.lua)'") do out[#out + 1] = f end
        return out
    end
    return list("shared_scripts"), list("client_scripts")
end

local shared, client = manifestLists()
for name in pairs(scriptGlobals(client)) do
    if not OWN[name] and _G[name] == nil and N[name] == nil and name:match("^%u") then
        N[name] = function() return nil end
    end
end
for k, v in pairs(N) do _G[k] = v end
_G.vector3, _G.vec3, _G.json = vector3, vector3, json
_G.promise = S.promise
_G.Citizen = {
    CreateThread = function(fn) S.spawn(fn) end,
    CreateThreadNow = function(fn) S.spawnNow(fn) end,
    -- Wait(0) = next frame (16 ms), so per-frame loops let virtual time move on.
    Wait = function(ms) return S.wait((ms and ms > 0) and ms or 16) end,
    Await = S.await, SetTimeout = S.setTimeout,
}
_G.SetTimeout = S.setTimeout
_G.exports = setmetatable({}, { __index = function() return setmetatable({}, { __index = function() return function() end end }) end })

for _, f in ipairs(shared) do dofile(ROOT .. f) end
for _, f in ipairs(client) do dofile(ROOT .. f) end

---------------------------------------------------------------------------
-- Tiny test DSL
---------------------------------------------------------------------------
local passed, failed = 0, 0
local function check(cond, label)
    if cond then passed = passed + 1 else failed = failed + 1 print("  \27[31m✗\27[0m " .. label) end
end
local function step(label, fn)
    local before = #S.errors
    local ok, err = pcall(fn)
    if not ok then failed = failed + 1 print("  \27[31m✗\27[0m " .. label .. ": " .. tostring(err)) return end
    if #S.errors > before then
        failed = failed + 1
        print("  \27[31m✗\27[0m " .. label .. " (thread error)\n" .. table.concat(S.errors, "\n", before + 1))
        return
    end
    print("  \27[32m✓\27[0m " .. label)
end
local function nui(name, data)
    local result
    S.spawnNow(function() C.nui[name](data, function(r) result = r end) end)
    S.advance(200)
    return result
end
local function press(key) C.controls[key] = true S.advance(50) end
local function lastMessage(action)
    for i = #C.messages, 1, -1 do
        if C.messages[i].action == action then return C.messages[i].data end
    end
end
local function lastRpc(name)
    for i = #C.rpcs, 1, -1 do
        if C.rpcs[i].name == name then return C.rpcs[i] end
    end
end
local function vehicle(plate, x, y, z)
    C.seq = C.seq + 1
    C.entities[C.seq] = { type = 2, model = joaat("sultan"), plate = plate, coords = vector3(x, y, z) }
    return C.seq
end

---------------------------------------------------------------------------
-- Scenario
---------------------------------------------------------------------------
print("\27[1mClient smoke test\27[0m")

step("session starts and asks the server for its state", function()
    S.advance(1000)
    check(lastRpc("session:init") ~= nil, "session:init sent")
    check(Evora.ready == true, "client marked ready")
end)

step("NUI ready sends init + state", function()
    local r = nui("ready", {})
    check(r and r.ok, "ready acknowledged")
    local init = lastMessage("init")
    check(init and init.locale and init.locale.tab_office ~= nil, "UI locale sent")
    fire("evora_police:state", { military = true, onDuty = true, vacation = false, jailed = false, permissions = { "ipad" } })
    S.advance(10)
    check(Evora.state.onDuty == true and lastMessage("state").military == true, "state forwarded")
end)

step("iPad opens with focus and closes from the NUI", function()
    fire("evora_police:ipad:open", "office")
    S.advance(3000)
    check(lastMessage("ipad:open").tab == "office", "ipad:open sent")
    check(C.focus[1] == true and C.focus[2] == true, "focus + cursor")
    nui("close", { layer = "ipad" })
    check(C.focus[1] == false, "focus released")
    fire("evora_police:ipad:push", "reports", {})
    S.advance(10)
    check(lastMessage("ipad:push").type == "reports", "push forwarded")
end)

step("NUI rpc bridge returns the server answer", function()
    C.rpcReplies["ipad:office"] = { finesIssued = 3 }
    local r = nui("rpc", { name = "ipad:office", payload = {} })
    check(r and r.ok == true and r.data.finesIssued == 3, "rpc answer relayed")
    local bad = nui("rpc", { name = 5 })
    check(bad and bad.ok == false, "invalid rpc rejected locally")
end)

step("broadcast, panel, id card and toast UI events", function()
    fire("evora_police:ui", "broadcast", { kind = "officers", title = "تعميم", message = "اختبار" })
    fire("evora_police:ui", "panel", { kind = "citizen", data = {} })
    fire("evora_police:ui", "idcard", { name = "Hossam", user_id = 17 })
    fire("evora_police:ui", "toast", { message = "ok" })
    fire("evora_police:ui", "unknown", {})
    S.advance(10)
    check(lastMessage("broadcast").message == "اختبار", "broadcast")
    check(lastMessage("panel:open").kind == "citizen" and C.focus[1] == true, "panel with focus")
    nui("close", { layer = "panel" })
    check(lastMessage("panel:close") ~= nil and C.focus[1] == false, "panel closed")
end)

step("F5 answers a confirmation, the queue shows the next one", function()
    fire("evora_police:confirm:show", "c1", { title = "مخالفة", message = "m", details = {}, timeout = 30 })
    fire("evora_police:confirm:show", "c2", { title = "سجن", message = "m", details = {}, timeout = 30 })
    S.advance(50)
    check(lastMessage("confirm:show").id == "c1", "first confirmation shown")
    press(Config.Confirm.AcceptKey)
    S.advance(100)
    local answer = lastRpc("confirm:answer")
    check(answer and answer.payload.id == "c1" and answer.payload.accepted == true, "F5 accepted c1")
    check(lastMessage("confirm:show").id == "c2", "second confirmation shown")
    fire("evora_police:confirm:hide", "c2")
    S.advance(50)
    check(lastMessage("confirm:hide") ~= nil, "hidden by the server")
    nui("confirmAnswer", { id = "nope", accepted = true })
end)

step("builtin dialog and menu round-trips", function()
    fire("evora_police:dialog:open", 7, "إبلاغ", { { key = "id", type = "number" } })
    S.advance(10)
    check(lastMessage("dialog:open").id == 7, "dialog opened")
    nui("dialogSubmit", { id = 7, values = { id = 17 } })
    check(lastRpc("dialog:submit").payload.values.id == 17, "dialog submitted")
    fire("evora_police:dialog:close", 7)
    nui("dialogCancel", { id = 8 })
    fire("evora_police:menu:open", 3, { title = "الشرطة", items = { { label = "a" } }, back = true })
    S.advance(10)
    check(lastMessage("menu:open").token == 3, "menu opened")
    nui("menuSelect", { token = 3, index = 1 })
    check(lastRpc("menu:select").payload.index == 1, "menu select sent")
    nui("menuBack", { token = 3 })
    nui("menuClose", {})
    fire("evora_police:menu:close")
    S.advance(10)
end)

step("jail HUD, perimeter report, task with skill check", function()
    local task = Config.Jail.Tasks.List[1]
    C.pos = vector3(Config.Jail.Center.x, Config.Jail.Center.y, Config.Jail.Center.z)
    fire("evora_police:jail:start", {
        name = "السجن", remaining = 600, total = 600, reason = "سرقة", center = Config.Jail.Center, radius = Config.Jail.Radius,
        escape = true, hud = true,
        tasks = { { id = task.id, label = task.label, coords = task.coords, radius = task.radius or 2.0, duration = 2 } },
    })
    S.advance(100)
    check(lastMessage("jail:show").remaining == 600, "HUD shown")
    fire("evora_police:jail:sync", 590)
    S.advance(10)
    check(lastMessage("jail:sync").remaining == 590, "HUD synced")
    C.pos = vector3(Config.Jail.Center.x + Config.Jail.Radius + 50.0, Config.Jail.Center.y, Config.Jail.Center.z)
    S.advance(1600)
    check(lastRpc("jail:escaped") ~= nil, "perimeter reported")
    C.pos = vector3(task.coords.x, task.coords.y, task.coords.z)
    C.rpcReplies["jail:taskStart"] = { id = task.id, label = task.label, duration = 2, anim = {}, difficulty = { checks = 1, speed = 1, zone = 0.2 } }
    C.rpcReplies["jail:taskComplete"] = { reduced = 30, remaining = 560 }
    S.advance(800) -- the loop sleeps 750 ms while far from every task
    press(38)
    S.advance(1500)
    check(lastMessage("skillcheck:start") ~= nil, "skill check shown")
    nui("skillcheck", { success = true })
    S.advance(2000)
    local done = lastRpc("jail:taskComplete")
    check(done and done.payload.success == true, "task completed")
    check(Evora.jailTask.active == false, "task released")
    -- A NUI that never answers a skill check cannot lock the player in the task.
    C.rpcs = {}
    press(38)
    S.advance(12500)
    check(lastRpc("jail:taskComplete") and lastRpc("jail:taskComplete").payload.success == false, "unanswered skill check fails")
    fire("evora_police:jail:escape", "ممنوع", 60)
    fire("evora_police:jail:end")
    S.advance(1000)
    check(lastMessage("jail:hide") ~= nil, "HUD hidden")
end)

step("security alert affects late entrants only", function()
    local zone = { id = 1, label = "وسط المدينة", coords = { x = 0.0, y = 0.0, z = 0.0 }, radius = 100.0,
        mapZone = { enabled = true }, vehicle = { enabled = true, maxSpeed = 40 }, player = { enabled = true },
        exemptOfficers = false, exemptionEndsOnExit = true, interval = 400 }
    C.pos = vector3(10.0, 0.0, 0.0)
    fire("evora_police:alert:start", zone, true)
    S.advance(900)
    local status = lastMessage("alert:status")
    check(status == nil or status.active == false, "occupant at activation is exempt")
    C.pos = vector3(500.0, 0.0, 0.0)
    S.advance(900)
    C.pos = vector3(10.0, 0.0, 0.0)
    S.advance(900)
    check(lastMessage("alert:status").active == true, "re-entry after leaving is affected")
    fire("evora_police:alert:stop", 1)
    S.advance(900)
    check(lastMessage("alert:status").active == false, "released on stop")
    fire("evora_police:alert:sync", { zone })
    S.advance(900)
    check(lastMessage("alert:status").active == true, "late joiner inside is affected")
    fire("evora_police:alert:stop", 1)
    S.advance(900)
end)

step("spectate follows the target and stops with BACKSPACE", function()
    fire("evora_police:spectate:start", { target = 2, id = 17, name = "Hossam", kind = "officer", coords = { x = 5.0, y = 5.0, z = 30.0 } })
    S.advance(1500)
    check(lastMessage("spectate:show") and lastMessage("spectate:show").id == 17, "spectate bar shown")
    fire("evora_police:spectate:coords", { x = 6.0, y = 6.0, z = 30.0 })
    press(Config.Spectate.StopKey or 194)
    S.advance(1500)
    check(lastRpc("spectate:stop") ~= nil, "stop sent to the server")
    check(lastMessage("spectate:hide") ~= nil, "bar hidden")
    fire("evora_police:spectate:start", { target = 2, id = 17, name = "Hossam", kind = "prisoner" })
    S.advance(1500)
    fire("evora_police:spectate:stop", "revoked")
    S.advance(1500)
    nui("spectateStop", {})
end)

step("barricade placement and model-guarded deletion", function()
    C.rpcReplies["barricade:place"] = { netId = 77 }
    local o = Config.Barricades[1]
    fire("evora_police:barricade:place", 1, o.model, o.label, 2.2, false)
    S.advance(100)
    press(38)
    S.advance(200)
    local placed = lastRpc("barricade:place")
    check(placed and placed.payload.index == 1 and placed.payload.netId ~= nil, "placement sent with net id")
    local barricade = placed.payload.netId
    local car = vehicle("ABC 123", 0.0, 3.0, 30.0)
    fire("evora_police:barricade:delete", car)
    S.advance(10)
    check(C.entities[car] ~= nil, "a vehicle behind a forged net id is never deleted")
    fire("evora_police:barricade:delete", barricade)
    S.advance(10)
    check(C.entities[barricade] == nil, "the barricade prop is deleted")
    C.entities[car] = nil
end)

step("impound deletion only hits the impounded plate", function()
    local car = vehicle("P 123ABC", 0.0, 3.0, 30.0)
    fire("evora_police:vehicle:delete", car, { "OTHER1" })
    S.advance(300)
    check(C.entities[car] ~= nil, "wrong plate kept")
    fire("evora_police:vehicle:delete", car, { "P 123ABC", "123ABC" })
    S.advance(300)
    check(C.entities[car] == nil, "impounded vehicle deleted")
end)

step("wanted quick-open key opens the iPad on the wanted tab", function()
    fire("evora_police:wanted:alert", { id = 9, name = "Hossam", user_id = 17, reason = "سطو", quickOpen = { enabled = true, key = 47, seconds = 10 } })
    S.advance(100)
    press(47)
    S.advance(100)
    check(lastMessage("ipad:open") and lastMessage("ipad:open").tab == "wanted", "wanted tab opened")
    nui("close", { layer = "ipad" })
end)

step("server requests are answered by the responders", function()
    vehicle("XYZ 999", 0.0, 2.0, 30.0)
    C.pos = vector3(0.0, 0.0, 30.0)
    local asks = {
        { 1, "coords" }, { 2, "nearbyPlayers", { radius = 4.0 } }, { 3, "nearestVehicle", { radius = 5.0 } },
        { 4, "vehicleByPlate", { plates = { "XYZ 999" }, radius = 8.0 } }, { 5, "weapons:get" }, { 6, "clothing:get" },
        { 7, "cuff:get" }, { 8, "unknown" },
    }
    for _, a in ipairs(asks) do fire("evora_police:creq", a[1], a[2], a[3]) end
    S.advance(10)
    check(C.cres[1] and C.cres[1].value.z == 30.0, "coords")
    check(C.cres[2] and #C.cres[2].value == 1 and C.cres[2].value[1].source == 2, "nearby players")
    check(C.cres[3] and C.cres[3].value.plate == "XYZ 999", "nearest vehicle")
    check(C.cres[4] and C.cres[4].value.plate == "XYZ 999", "vehicle by plate")
    check(C.cres[5] and C.cres[5].value.WEAPON_PISTOL.ammo == 30, "weapons")
    check(C.cres[6] and C.cres[6].value[11] ~= nil and C.cres[6].value.p0 ~= nil, "clothing")
    check(C.cres[7] and C.cres[7].value == false, "cuffs")
    check(C.cres[8] and C.cres[8].value == nil, "unknown responder answers nil")
end)

step("builtin integrations: notify, cuffs, drag, seats, clothing, weapons, id card", function()
    fire("evora_police:notify", "مرحبا", "info", 5)
    fire("evora_police:radio", "A-12")
    fire("evora_police:cuff:set", true)
    S.advance(100)
    fire("evora_police:cuff:set", false)
    fire("evora_police:drag", 2)
    S.advance(600)
    fire("evora_police:drag", 2)
    fire("evora_police:seat:putIn", 6.0)
    fire("evora_police:seat:pullOut")
    fire("evora_police:clothing:set", { [11] = { 5, 0, 2 }, p0 = { -1, 0 }, p1 = { 3, 1 }, modelhash = 1 })
    fire("evora_police:weapons:clear")
    fire("evora_police:weapons:give", { WEAPON_PISTOL = { ammo = 50 } })
    fire("evora_police:idcard:present")
    fire("evora_police:teleport", 1.0, 2.0, 3.0, 90.0)
    fire("evora_police:waypoint", 1.0, 2.0)
    fire("evora_police:anim", "mp_arresting", "a_uncuff", 1000)
    fire("evora_police:armour", 100)
    S.advance(2000)
    check(lastMessage("toast").message == "مرحبا", "builtin notification rendered by the NUI")
    check(C.pos.x == 1.0 and C.pos.y == 2.0, "teleported")
end)

step("payment point shows a hint and opens the fines panel", function()
    local point = Config.Fines.PaymentPoints[1]
    C.rpcReplies["fines:open"] = { list = {}, total = 0, count = 0 }
    C.pos = vector3(point.coords.x, point.coords.y, point.coords.z)
    S.advance(1600)
    check(lastMessage("hint") and lastMessage("hint").key == "E", "hint shown")
    press(38)
    S.advance(200)
    check(lastRpc("fines:open") ~= nil, "fines:open requested")
    check(lastMessage("panel:open").kind == "finePay", "payment panel opened")
    nui("panelAction", { action = "finesPay", all = true })
    check(lastRpc("fines:pay").payload.all == true, "pay all sent")
    nui("panelAction", { action = "vehicleSeize", token = "t" })
    nui("panelAction", { action = "bogus" })
    C.pos = vector3(0.0, 0.0, 30.0)
    S.advance(1600)
    check(lastMessage("hint:hide") ~= nil, "hint hidden when leaving")
end)

step("commands and resource stop", function()
    for name, fn in pairs(C.commands) do S.spawnNow(fn, 0, {}, name) end
    S.advance(500)
    fire("onResourceStop", "Evora_Police")
    S.advance(100)
    check(C.focus[1] == false, "focus released on stop")
end)

if #S.errors > 0 then
    failed = failed + 1
    print(table.concat(S.errors, "\n"))
end
print(("\n%d checks passed, %d failed"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
