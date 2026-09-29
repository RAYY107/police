--[[
    Evora_Police — RPC dispatcher

    The ONLY inbound network entry point. Every client request goes through here:
        1. source → vRP user id (server side)
        2. rate limit (token bucket + per-action cooldown)
        3. feature flag
        4. military / permission / duty checks (fresh vRP groups)
        5. handler(ctx, payload) → result | nil, "error"
]]

local RPC = { handlers = {} }
Evora.RPC = RPC

local buckets = {}
local cooldowns = {}
local BUCKET_CAPACITY = 20
local BUCKET_REFILL = 8 -- tokens per second

--[[ opts:
    feature  = "Fines"               Config.Features key that must be enabled
    military = true                  caller must hold a configured rank (or be on vacation with allowVacation)
    perm     = "fines" | {"a","b"}   caller needs one of these permissions
    duty     = "fines"               key of Config.Duty.RequireDutyFor
    cooldown = 1500                  ms between two calls of this action by the same player
    allowVacation = true             officers on vacation pass the military check
]]
function RPC.register(name, opts, handler)
    RPC.handlers[name] = { opts = opts or {}, fn = handler }
end

local function takeToken(src)
    local now = GetGameTimer()
    local b = buckets[src]
    if not b then
        b = { tokens = BUCKET_CAPACITY, at = now }
        buckets[src] = b
    end
    local elapsed = (now - b.at) / 1000
    b.tokens = math.min(BUCKET_CAPACITY, b.tokens + elapsed * BUCKET_REFILL)
    b.at = now
    if b.tokens < 1 then return false end
    b.tokens = b.tokens - 1
    return true
end

local function onCooldown(src, name, ms)
    if not ms or ms <= 0 then return false end
    local now = GetGameTimer()
    cooldowns[src] = cooldowns[src] or {}
    local last = cooldowns[src][name]
    if last and now - last < ms then return true end
    cooldowns[src][name] = now
    return false
end

function RPC.forget(src)
    buckets[src] = nil
    cooldowns[src] = nil
end

-- Builds the request context and runs the generic checks.
function RPC.context(src, opts)
    if not Evora.Framework.available then return nil, L("err_unavailable") end
    local user_id = Evora.Players.getUserId(src)
    if not user_id then return nil, L("err_not_loaded") end
    local ctx = {
        source = src,
        user_id = user_id,
        name = Evora.Players.name(user_id),
    }
    if opts.feature and not Evora.feature(opts.feature) then
        return nil, L("err_feature_disabled")
    end
    if opts.military or opts.perm or opts.duty then
        local profile = Evora.Gov.getProfile(user_id, true)
        ctx.profile = profile
        if not profile.isMilitary then
            if not (opts.allowVacation and Evora.Vacation and Evora.Vacation.isOnVacation(user_id)) then
                return nil, L("err_not_military")
            end
        end
        if opts.perm and not Evora.Gov.hasAny(profile, opts.perm) then
            Evora.debug("permissions", "user %d denied '%s'", user_id, type(opts.perm) == "table" and table.concat(opts.perm, ",") or opts.perm)
            return nil, L("err_no_permission")
        end
        if opts.duty and not Evora.Officers.dutyOk(user_id, opts.duty) then
            return nil, L("err_not_on_duty")
        end
    end
    return ctx
end

RegisterNetEvent("evora_police:rpc", function(reqId, name, payload)
    local src = source
    if type(reqId) ~= "number" or type(name) ~= "string" or #name > 64 then return end

    local function reply(ok, data)
        TriggerClientEvent("evora_police:rpc:res", src, reqId, ok, data)
    end

    local handler = RPC.handlers[name]
    if not handler then return reply(false, L("err_unknown_action")) end
    if not takeToken(src) then return reply(false, L("err_rate_limit")) end
    if onCooldown(src, name, handler.opts.cooldown) then return reply(false, L("err_cooldown")) end
    if type(payload) ~= "table" then payload = {} end

    local ctx, err = RPC.context(src, handler.opts)
    if not ctx then return reply(false, err) end

    local ok, result, message = xpcall(handler.fn, debug.traceback, ctx, payload)
    if not ok then
        Evora.error("action '%s' failed: %s", name, tostring(result))
        return reply(false, L("err_internal"))
    end
    if result == nil then return reply(false, message or L("err_internal")) end
    reply(true, result)
end)

---------------------------------------------------------------------------
-- Payload validation helpers
---------------------------------------------------------------------------
function RPC.int(value, min, max)
    local n = Utils.toInt(value)
    if not n then return nil end
    if min and n < min then return nil end
    if max and n > max then return nil end
    return n
end

function RPC.text(value, maxLen, keepNewLines)
    if type(value) ~= "string" then return nil end
    local s = Utils.sanitize(value, maxLen, keepNewLines)
    if s == "" then return nil end
    return s
end

function RPC.oneOf(value, list)
    for _, v in ipairs(list) do
        if v == value then return value end
    end
    return nil
end
