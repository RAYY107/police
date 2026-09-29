--[[
    Evora_Police — client UI glue: broadcasts, toasts, panels, ID card, dialogs, builtin menu,
    key hints, progress / skill checks and the wanted quick-open.
]]

---------------------------------------------------------------------------
-- Generic server → UI events
---------------------------------------------------------------------------
local handlers = {}

function handlers.broadcast(data)
    UI.send("broadcast", data)
    local sound = data.sound or (Config.Broadcast and Config.Broadcast.Sound)
    if sound and sound.enabled then PlaySoundFrontend(-1, sound.name, sound.set, true) end
end

function handlers.panel(data)
    UI.send("panel:open", data)
    UI.focus("panel", true, true)
end

function handlers.idcard(data)
    UI.send("idcard:show", data)
    PlaySoundFrontend(-1, "SELECT", "HUD_FRONTEND_DEFAULT_SOUNDSET", true)
end

function handlers.toast(data)
    UI.send("toast", data)
end

RegisterNetEvent("evora_police:ui", function(action, data)
    local fn = handlers[action]
    if fn then fn(data or {}) end
end)

---------------------------------------------------------------------------
-- Builtin popup (Config.Integrations.Popup.type = "builtin")
---------------------------------------------------------------------------
RegisterNetEvent("evora_police:dialog:open", function(id, title, fields)
    UI.send("dialog:open", { id = id, title = title, fields = fields })
    UI.focus("dialog", true, true)
end)

RegisterNetEvent("evora_police:dialog:close", function(id)
    UI.send("dialog:close", { id = id })
    UI.focus("dialog", false)
end)

RegisterNUICallback("dialogSubmit", function(data, cb)
    UI.focus("dialog", false)
    Citizen.CreateThread(function()
        Evora.rpc("dialog:submit", { id = data.id, values = data.values })
    end)
    cb({ ok = true })
end)

RegisterNUICallback("dialogCancel", function(data, cb)
    UI.focus("dialog", false)
    Citizen.CreateThread(function() Evora.rpc("dialog:cancel", { id = data.id }) end)
    cb({ ok = true })
end)

---------------------------------------------------------------------------
-- Builtin menu (Config.Integrations.BuilderMenu.type = "builtin")
---------------------------------------------------------------------------
RegisterNetEvent("evora_police:menu:open", function(token, menu)
    UI.send("menu:open", { token = token, title = menu.title, subtitle = menu.subtitle, items = menu.items, back = menu.back })
    UI.focus("menu", true, true)
end)

RegisterNetEvent("evora_police:menu:close", function()
    UI.send("menu:close", {})
    UI.focus("menu", false)
end)

RegisterNUICallback("menuSelect", function(data, cb)
    UI.focus("menu", false)
    Citizen.CreateThread(function() Evora.rpc("menu:select", { token = data.token, index = data.index }) end)
    cb({ ok = true })
end)

RegisterNUICallback("menuBack", function(data, cb)
    UI.focus("menu", false)
    Citizen.CreateThread(function() Evora.rpc("menu:back", { token = data.token }) end)
    cb({ ok = true })
end)

RegisterNUICallback("menuClose", function(data, cb)
    UI.focus("menu", false)
    Citizen.CreateThread(function() Evora.rpc("menu:close", {}) end)
    cb({ ok = true })
end)

do
    local menuCfg = Config.Integrations and Config.Integrations.BuilderMenu or {}
    if menuCfg.type == "builtin" and menuCfg.builtin and menuCfg.builtin.command then
        RegisterCommand(menuCfg.builtin.command, function()
            Citizen.CreateThread(function()
                local ok, err = Evora.rpc("menu:main", {})
                if not ok and err then UI.notify(err, "error") end
            end)
        end, false)
        if menuCfg.builtin.key then
            RegisterKeyMapping(menuCfg.builtin.command, "Evora_Police", "keyboard", menuCfg.builtin.key)
        end
    end
end

---------------------------------------------------------------------------
-- Panels (inquiries, search results, payments)
---------------------------------------------------------------------------
RegisterNUICallback("panelAction", function(data, cb)
    Citizen.CreateThread(function()
        local action = type(data) == "table" and data.action or ""
        local ok, result
        if action == "finesPay" then
            ok, result = Evora.rpc("fines:pay", { ids = data.ids, all = data.all == true })
        elseif action == "impoundPay" then
            ok, result = Evora.rpc("impound:pay", { id = data.id })
        elseif action == "vehicleSeize" then
            ok, result = Evora.rpc("field:vehicleSeize", { token = data.token })
        else
            ok, result = false, "invalid"
        end
        cb({ ok = ok, data = result })
    end)
end)

AddEventHandler("evora_police:client:closed", function(layer)
    if layer == "panel" then UI.send("panel:close", {}) end
end)

---------------------------------------------------------------------------
-- Key hints (Arabic text rendered by the NUI, never by GTA text natives)
---------------------------------------------------------------------------
local hintOwner, hintId = nil, nil

-- owner: "points" | "jail" | "barricade" ... a hint can only be hidden by its owner.
function UI.hint(key, text, owner)
    owner = owner or "default"
    local id = key .. text
    if hintOwner == owner and hintId == id then return end
    hintOwner, hintId = owner, id
    if Config.UI.Hints ~= false then UI.send("hint", { key = key, text = text }) end
end

function UI.hideHint(owner)
    owner = owner or "default"
    if hintOwner ~= owner then return end
    hintOwner, hintId = nil, nil
    UI.send("hint:hide", {})
end

---------------------------------------------------------------------------
-- Progress bar + skill checks (jail tasks)
---------------------------------------------------------------------------
local skill = nil

function UI.skillCheck(difficulty)
    local p = promise.new()
    skill = p
    UI.send("skillcheck:start", {
        checks = difficulty.checks or 1, speed = difficulty.speed or 1.0, zone = difficulty.zone or 0.2, key = "E",
    })
    UI.focus("skillcheck", true, false)
    -- The NUI gives up after 6 s; this only covers a NUI that never answers.
    SetTimeout(10000, function()
        if skill == p then
            skill = nil
            p:resolve({ success = false })
        end
    end)
    local r = Citizen.Await(p)
    UI.focus("skillcheck", false)
    return r.success == true
end

RegisterNUICallback("skillcheck", function(data, cb)
    if skill then
        local p = skill
        skill = nil
        p:resolve({ success = data and data.success == true })
    end
    cb({ ok = true })
end)

function UI.progress(label, seconds)
    UI.send("progress:start", { label = label, duration = seconds })
end

function UI.stopProgress()
    UI.send("progress:stop", {})
end

---------------------------------------------------------------------------
-- Wanted alert with quick open (click-free: press the configured key)
---------------------------------------------------------------------------
local quickUntil = 0

RegisterNetEvent("evora_police:wanted:alert", function(alert)
    UI.send("wanted:alert", alert)
    local q = alert and alert.quickOpen
    if not q or not q.enabled then return end
    local wasActive = GetGameTimer() < quickUntil
    quickUntil = GetGameTimer() + (q.seconds or 10) * 1000
    if wasActive then return end
    Citizen.CreateThread(function()
        while GetGameTimer() < quickUntil do
            if IsControlJustReleased(0, q.key or 47) and not UI.hasFocus() then
                quickUntil = 0
                UI.send("wanted:alertHide", {})
                Evora.openIpad("wanted")
                break
            end
            Citizen.Wait(0)
        end
        UI.send("wanted:alertHide", {})
    end)
end)
