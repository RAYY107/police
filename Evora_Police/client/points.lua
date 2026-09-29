--[[
    Evora_Police — interaction points: fine payment points (red arrow) and impound centres.
    Far away: one distance check every 750 ms. Near: markers each frame and an E hint.
]]

local points = {}
local blips = {}

local function blip(coords, b)
    if not b or b.enabled == false then return end
    local handle = AddBlipForCoord(coords.x, coords.y, coords.z)
    SetBlipSprite(handle, b.sprite or 1)
    SetBlipColour(handle, b.color or 0)
    SetBlipScale(handle, b.scale or 0.8)
    SetBlipAsShortRange(handle, true)
    BeginTextCommandSetBlipName("STRING")
    AddTextComponentSubstringPlayerName(b.label or "")
    EndTextCommandSetBlipName(handle)
    blips[#blips + 1] = handle
end

local function build()
    points = {}
    if Evora.feature("Fines") then
        for _, p in ipairs(Config.Fines.PaymentPoints or {}) do
            points[#points + 1] = { kind = "fines", coords = p.coords, radius = p.radius or 1.5, marker = p.marker, hint = LocaleUI.hint_pay_fines }
            blip(p.coords, p.blip)
        end
    end
    if Evora.feature("Impound") then
        for _, loc in ipairs(Config.Impound.Locations or {}) do
            points[#points + 1] = { kind = "impound", coords = loc.coords, radius = loc.radius or 3.0, marker = loc.marker, hint = loc.label or LocaleUI.hint_impound }
            blip(loc.coords, loc.blip)
        end
    end
end

local function drawMarker(p)
    local m = p.marker
    if not m or m.enabled == false then return end
    local col = m.color or { 220, 38, 38, 200 }
    local sc = m.scale or { 0.35, 0.35, 0.35 }
    local rot = m.rotation or { 0.0, 0.0, 0.0 }
    DrawMarker(m.type or 2, p.coords.x, p.coords.y, p.coords.z + (m.offsetZ or 0.0), 0.0, 0.0, 0.0,
        rot[1], rot[2], rot[3], sc[1], sc[2], sc[3], col[1], col[2], col[3], col[4],
        m.bob == true, m.faceCamera ~= false, 2, m.rotate == true, nil, nil, false)
end

local function interact(p)
    Citizen.CreateThread(function()
        if p.kind == "fines" then
            local ok, data = Evora.rpc("fines:open", {})
            if not ok then return UI.notify(data, "error") end
            UI.send("panel:open", { kind = "finePay", title = LocaleUI.fines_title, data = data })
        else
            local ok, data = Evora.rpc("impound:open", {})
            if not ok then return UI.notify(data, "error") end
            UI.send("panel:open", { kind = "impoundPay", title = data.location or LocaleUI.hint_impound, data = data })
        end
        UI.focus("panel", true, true)
    end)
end

Citizen.CreateThread(function()
    build()
    while true do
        local sleep = 750
        if #points > 0 then
            local pos = GetEntityCoords(PlayerPedId())
            local inside = nil
            for _, p in ipairs(points) do
                local d = Utils.dist(pos, p.coords)
                local drawDistance = (p.marker and p.marker.drawDistance) or 15.0
                if d < drawDistance then
                    sleep = 0
                    drawMarker(p)
                    if d <= p.radius then inside = p end
                end
            end
            if inside and not UI.hasFocus() then
                UI.hint("E", inside.hint, "points")
                if IsControlJustReleased(0, 38) then interact(inside) end
            else
                UI.hideHint("points")
            end
        end
        Citizen.Wait(sleep)
    end
end)

AddEventHandler("onResourceStop", function(resource)
    if resource ~= GetCurrentResourceName() then return end
    for _, b in ipairs(blips) do if DoesBlipExist(b) then RemoveBlip(b) end end
end)
