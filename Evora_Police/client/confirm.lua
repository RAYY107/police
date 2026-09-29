--[[
    Evora_Police — confirmation card (F5 = قبول / F6 = رفض)

    The server decides; this only shows the card and sends the answer for the request id.
    Keys are read from game controls when the NUI has no focus, and from the browser (JS)
    when an NUI layer (e.g. the iPad) has focus. Requests are queued one at a time.
]]

local queue = {}
local current = nil

local function showNext()
    current = table.remove(queue, 1)
    if not current then
        UI.send("confirm:hide", {})
        return
    end
    local data = current.data
    UI.send("confirm:show", {
        id = current.id, title = data.title, message = data.message, details = data.details,
        timeout = data.timeout, accept = data.accept, reject = data.reject, icon = data.icon,
    })
    PlaySoundFrontend(-1, "Menu_Accept", "Phone_SoundSet_Default", true)
    local id = current.id
    Citizen.CreateThread(function()
        local acceptKey = Config.Confirm.AcceptKey or 166
        local rejectKey = Config.Confirm.RejectKey or 167
        while current and current.id == id do
            if not UI.hasFocus() then
                DisableControlAction(0, acceptKey, true)
                DisableControlAction(0, rejectKey, true)
                if IsDisabledControlJustReleased(0, acceptKey) then
                    Evora.answerConfirm(id, true)
                    break
                elseif IsDisabledControlJustReleased(0, rejectKey) then
                    Evora.answerConfirm(id, false)
                    break
                end
            end
            Citizen.Wait(0)
        end
    end)
end

function Evora.answerConfirm(id, accepted)
    if not current or current.id ~= id then return end
    PlaySoundFrontend(-1, accepted and "SELECT" or "BACK", "HUD_FRONTEND_DEFAULT_SOUNDSET", true)
    current = nil
    Citizen.CreateThread(function()
        local ok, err = Evora.rpc("confirm:answer", { id = id, accepted = accepted == true })
        if not ok and err and err ~= "timeout" then UI.notify(err, "error") end
    end)
    showNext()
end

RegisterNetEvent("evora_police:confirm:show", function(id, data)
    if type(id) ~= "string" or type(data) ~= "table" then return end
    queue[#queue + 1] = { id = id, data = data }
    if not current then showNext() end
end)

RegisterNetEvent("evora_police:confirm:hide", function(id)
    for i = #queue, 1, -1 do
        if queue[i].id == id then table.remove(queue, i) end
    end
    if current and current.id == id then
        current = nil
        showNext()
    end
end)

RegisterNUICallback("confirmAnswer", function(data, cb)
    if type(data) == "table" and type(data.id) == "string" then
        Evora.answerConfirm(data.id, data.accepted == true)
    end
    cb({ ok = true })
end)
