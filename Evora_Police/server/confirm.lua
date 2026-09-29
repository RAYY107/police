--[[
    Evora_Police — reusable confirmation service (F5 = قبول / F6 = رفض)

    Confirm.ask(responderSource, opts) blocks until the responder answers, the request expires,
    or the responder disconnects. The server accepts an answer only:
        * for an id it generated,
        * from the exact responder it was sent to,
        * once, and before expiry.
    Callers must re-validate their own state after the answer (distance, permissions, ...).
]]

local Confirm = { pending = {}, byResponder = {} }
Evora.Confirm = Confirm

local seq = 0

local function newId()
    seq = seq + 1
    return ("%x%06x%04x"):format(seq, math.random(0, 0xFFFFFF), GetGameTimer() % 0xFFFF)
end

-- Who confirms an action: "target" | "self" | false (Config.Confirm.Actions)
function Confirm.mode(action)
    local actions = Config.Confirm and Config.Confirm.Actions or {}
    local mode = actions[action]
    if mode == nil then return false end
    return mode
end

local function finish(id, accepted, reason)
    local entry = Confirm.pending[id]
    if not entry then return end
    Confirm.pending[id] = nil
    if Confirm.byResponder[entry.responder] == id then Confirm.byResponder[entry.responder] = nil end
    if GetPlayerName(entry.responder) then
        TriggerClientEvent("evora_police:confirm:hide", entry.responder, id)
    end
    entry.p:resolve({ accepted = accepted == true, reason = reason })
end

--[[ opts:
    title    = "..."                     card title
    message  = "..."                     main text
    details  = { { "label", "value" } }  key / value rows
    timeout  = seconds
    icon     = "jail" | "fine" | ...     UI icon hint
  returns accepted (boolean), reason ("accepted" | "rejected" | "timeout" | "busy" | "offline" | "dropped")
]]
function Confirm.ask(responder, opts)
    opts = opts or {}
    responder = tonumber(responder)
    if not responder or not GetPlayerName(responder) then return false, "offline" end
    if Confirm.byResponder[responder] then return false, "busy" end

    local id = newId()
    local timeout = tonumber(opts.timeout) or (Config.Confirm and Config.Confirm.DefaultTimeout) or 30
    local p = promise.new()
    Confirm.pending[id] = { id = id, responder = responder, p = p, expires = GetGameTimer() + timeout * 1000 }
    Confirm.byResponder[responder] = id

    local details = {}
    for _, row in ipairs(opts.details or {}) do
        details[#details + 1] = { tostring(row[1]), tostring(row[2]) }
    end
    TriggerClientEvent("evora_police:confirm:show", responder, id, {
        title = opts.title or L("confirm_title"),
        message = opts.message or "",
        details = details,
        timeout = timeout,
        icon = opts.icon,
        accept = (Config.Confirm and Config.Confirm.AcceptLabel) or "F5",
        reject = (Config.Confirm and Config.Confirm.RejectLabel) or "F6",
    })
    SetTimeout(timeout * 1000 + 250, function() finish(id, false, "timeout") end)

    local r = Citizen.Await(p)
    Evora.debug("rpc", "confirmation %s → %s", id, tostring(r.reason))
    return r.accepted, r.reason
end

-- Standard message for a failed confirmation.
function Confirm.failMessage(reason, targetIsSelf)
    if reason == "busy" then return L("confirm_busy") end
    if reason == "timeout" then return targetIsSelf and L("confirm_self_timeout") or L("confirm_timeout") end
    if reason == "offline" or reason == "dropped" then return L("err_target_offline") end
    return targetIsSelf and L("confirm_self_rejected") or L("confirm_rejected")
end

-- Asks the configured responder of an action. `mode` false skips the confirmation.
function Confirm.forAction(action, officerSrc, targetSrc, opts)
    local mode = Confirm.mode(action)
    if not mode then return true, "skipped" end
    local responder = mode == "self" and officerSrc or targetSrc
    return Confirm.ask(responder, opts)
end

function Confirm.cancelFor(src)
    for id, entry in pairs(Confirm.pending) do
        if entry.responder == src then finish(id, false, "dropped") end
    end
end

Evora.RPC.register("confirm:answer", {}, function(ctx, data)
    local id = type(data.id) == "string" and data.id or nil
    local entry = id and Confirm.pending[id]
    if not entry then return nil, L("err_confirm_expired") end
    if entry.responder ~= ctx.source then
        Evora.debug("rpc", "rejected confirmation answer for %s from source %d", id, ctx.source)
        return nil, L("err_invalid_request")
    end
    if GetGameTimer() > entry.expires then
        finish(id, false, "timeout")
        return nil, L("err_confirm_expired")
    end
    finish(id, data.accepted == true, data.accepted == true and "accepted" or "rejected")
    return true
end)
