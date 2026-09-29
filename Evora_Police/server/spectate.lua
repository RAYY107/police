--[[
    Evora_Police — reusable spectate service (officer monitoring + prisoner monitoring)

    Permission is validated by the caller before Spectate.start. The server keeps the session,
    moves the admin into the target's routing bucket, streams the target position when needed
    and ends the session if either player leaves.
]]

local Spectate = { sessions = {} }
Evora.Spectate = Spectate

local P = Evora.Players

local function bucketOf(src)
    return GetPlayerRoutingBucket and (GetPlayerRoutingBucket(src) or 0) or 0
end

function Spectate.isSpectating(src)
    return Spectate.sessions[src] ~= nil
end

-- kind: "officer" | "prisoner"
function Spectate.start(adminSrc, targetSrc, kind)
    if not adminSrc or not targetSrc then return nil, L("err_target_offline") end
    if adminSrc == targetSrc then return nil, L("err_spectate_self") end
    if not GetPlayerName(targetSrc) then return nil, L("err_target_offline") end
    if Spectate.sessions[adminSrc] then Spectate.stop(adminSrc, "switch", true) end

    local targetId = P.bySource[targetSrc]
    local adminBucket = bucketOf(adminSrc)
    local targetBucket = bucketOf(targetSrc)
    if adminBucket ~= targetBucket and SetPlayerRoutingBucket then
        SetPlayerRoutingBucket(adminSrc, targetBucket)
    end

    Spectate.sessions[adminSrc] = {
        target = targetSrc, targetId = targetId, kind = kind, bucket = adminBucket, startedAt = Evora.now(),
    }
    TriggerClientEvent("evora_police:spectate:start", adminSrc, {
        target = targetSrc,
        name = P.name(targetId),
        id = targetId,
        kind = kind,
        coords = P.coords(targetSrc),
    })
    Evora.debug("spectate", "%d → %d (%s)", adminSrc, targetSrc, tostring(kind))

    local adminId = P.bySource[adminSrc]
    Evora.Logs.add(kind == "prisoner" and "jail" or "affairs", kind == "prisoner" and "jail_monitor" or "officer_monitor", {
        actor = adminId, target = targetId,
    })
    return true
end

-- silent: do not tell the client (used when switching targets)
function Spectate.stop(adminSrc, reason, silent)
    local session = Spectate.sessions[adminSrc]
    if not session then return false end
    Spectate.sessions[adminSrc] = nil
    if GetPlayerName(adminSrc) then
        if SetPlayerRoutingBucket and bucketOf(adminSrc) ~= session.bucket then
            SetPlayerRoutingBucket(adminSrc, session.bucket)
        end
        if not silent then
            TriggerClientEvent("evora_police:spectate:stop", adminSrc, reason or "manual")
        end
    end
    Evora.debug("spectate", "%d stopped (%s)", adminSrc, tostring(reason))
    return true
end

function Spectate.onDropped(src)
    if Spectate.sessions[src] then Spectate.sessions[src] = nil end
    for adminSrc, session in pairs(Spectate.sessions) do
        if session.target == src then Spectate.stop(adminSrc, "target_left") end
    end
end

Evora.RPC.register("spectate:stop", {}, function(ctx)
    Spectate.stop(ctx.source, "manual")
    return true
end)

-- Stream the target position so the admin camera can follow targets outside streaming range.
Citizen.CreateThread(function()
    while true do
        local interval = 1000
        if next(Spectate.sessions) then
            for adminSrc, session in pairs(Spectate.sessions) do
                if not GetPlayerName(session.target) then
                    Spectate.stop(adminSrc, "target_left")
                else
                    local coords = P.oneSync() and P.coords(session.target) or nil
                    if coords then TriggerClientEvent("evora_police:spectate:coords", adminSrc, coords) end
                end
            end
        else
            interval = 2000
        end
        Citizen.Wait(interval)
    end
end)
