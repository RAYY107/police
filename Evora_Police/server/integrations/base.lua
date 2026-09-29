--[[
    Evora_Police — integration registry, notifications, popups, chat and radio.
]]

local I = { status = {} }
Evora.Integrations = I

local function cfg(name)
    return (Config.Integrations and Config.Integrations[name]) or {}
end
I.cfg = cfg

local function resourceUp(name)
    return type(name) == "string" and name ~= "" and GetResourceState(name) == "started"
end
I.resourceUp = resourceUp

-- Records availability once and prints the standard console message when missing.
function I.report(name, available, detail)
    I.status[name] = { available = available, detail = detail }
    if not available then
        Evora.warn("%s integration unavailable.%s", name, detail and (" (" .. detail .. ")") or "")
    else
        Evora.debug("integrations", "%s → %s", name, detail or "ok")
    end
end

function I.available(name)
    local s = I.status[name]
    return s == nil or s.available
end

---------------------------------------------------------------------------
-- Notify
---------------------------------------------------------------------------
local Notify = {}
I.Notify = Notify

function Notify.send(src, message, kind, duration)
    if not src or not message or message == "" then return end
    kind = kind or "info"
    duration = duration or 6
    local c = cfg("Notify")
    local t = c.type or "vrp"
    if t == "vrp" and Evora.Framework.available then
        Evora.Framework.clientNoWait("notify", src, (message:gsub("\n", " ~n~ ")))
    elseif t == "event" and type(c.event) == "string" then
        local ok, args = pcall(c.format, message, kind, duration)
        if not ok or type(args) ~= "table" then args = { message } end
        TriggerClientEvent(c.event, src, table.unpack(args))
    elseif t == "custom" and type(c.custom) == "function" then
        local ok, err = pcall(c.custom, src, message, kind, duration)
        if not ok then Evora.debug("integrations", "Notify.custom: %s", tostring(err)) end
    else
        -- "client_export" and "builtin" are handled by client/integrations.lua
        TriggerClientEvent("evora_police:notify", src, message, kind, duration)
    end
end

-- Evora.notify(src, "locale_key", vars, kind) or a plain text
function Evora.notify(src, key, vars, kind, duration)
    local text = (Locale and Locale[key]) and L(key, vars) or tostring(key)
    Notify.send(src, text, kind, duration)
end

---------------------------------------------------------------------------
-- Popup / input
--   fields = { { key = "id", label = "...", type = "number"|"text"|"textarea", required = true, max = 250, min = 1 } }
---------------------------------------------------------------------------
local Popup = { pending = {}, seq = 0 }
I.Popup = Popup

local function validate(values, fields)
    if type(values) ~= "table" then return nil end
    local out = {}
    for _, f in ipairs(fields) do
        local raw = values[f.key]
        if f.type == "number" then
            local n = Utils.toInt(raw)
            if n == nil then
                if f.required ~= false then return nil end
            else
                if (f.min and n < f.min) or (f.max and n > f.max) then return nil end
                out[f.key] = n
            end
        else
            local s = Utils.sanitize(type(raw) == "string" and raw or (raw ~= nil and tostring(raw) or ""), f.max or 250, f.type == "textarea")
            if s == "" and f.required ~= false then return nil end
            out[f.key] = s
        end
    end
    return out
end
Popup.validate = validate

local function builtin(src, title, fields, timeout)
    Popup.seq = Popup.seq + 1
    local id = Popup.seq
    local p = promise.new()
    Popup.pending[id] = { src = src, p = p }
    local clientFields = {}
    for i, f in ipairs(fields) do
        clientFields[i] = { key = f.key, label = f.label, type = f.type or "text", max = f.max, min = f.min, placeholder = f.placeholder, default = f.default }
    end
    TriggerClientEvent("evora_police:dialog:open", src, id, title, clientFields)
    SetTimeout(timeout * 1000, function()
        local entry = Popup.pending[id]
        if entry then
            Popup.pending[id] = nil
            TriggerClientEvent("evora_police:dialog:close", src, id)
            entry.p:resolve({})
        end
    end)
    local r = Citizen.Await(p)
    if not r.values then return nil end
    return validate(r.values, fields)
end

-- Blocks until the player answers. Returns validated values or nil (cancel / invalid / timeout).
function Popup.input(src, title, fields)
    local c = cfg("Popup")
    local t = c.type or "vrp"
    local timeout = tonumber(c.timeout) or 120
    if t == "custom" and type(c.custom) == "function" then
        local ok, values = pcall(c.custom, src, title, fields)
        if not ok then
            Evora.debug("integrations", "Popup.custom: %s", tostring(values))
            return nil
        end
        return validate(values, fields)
    end
    if t == "vrp" and Evora.Framework.available then
        local values = {}
        for _, f in ipairs(fields) do
            local label = f.label
            if #fields == 1 and title and title ~= f.label then label = title .. " — " .. f.label end
            local v = Evora.Framework.prompt(src, label, f.default and tostring(f.default) or "", timeout * 1000)
            if v == nil then return nil end
            v = Utils.trim(tostring(v))
            if v == "" and f.required ~= false then return nil end
            values[f.key] = v
        end
        return validate(values, fields)
    end
    return builtin(src, title, fields, timeout)
end

function Popup.cancelFor(src)
    for id, entry in pairs(Popup.pending) do
        if entry.src == src then
            Popup.pending[id] = nil
            entry.p:resolve({})
        end
    end
end

Evora.RPC.register("dialog:submit", {}, function(ctx, data)
    local id = Utils.toInt(data.id)
    local entry = id and Popup.pending[id]
    if not entry or entry.src ~= ctx.source then return nil, L("err_invalid_request") end
    Popup.pending[id] = nil
    entry.p:resolve({ values = type(data.values) == "table" and data.values or {} })
    return true
end)

Evora.RPC.register("dialog:cancel", {}, function(ctx, data)
    local id = Utils.toInt(data.id)
    local entry = id and Popup.pending[id]
    if entry and entry.src == ctx.source then
        Popup.pending[id] = nil
        entry.p:resolve({})
    end
    return true
end)

---------------------------------------------------------------------------
-- Chat announcements
---------------------------------------------------------------------------
local Chat = {}
I.Chat = Chat

-- targets: -1 (everyone) or a list of sources
function Chat.send(targets, title, message, color)
    local c = cfg("Chat")
    if c.type == "custom" and type(c.custom) == "function" then
        local list = targets
        if targets == -1 then
            list = {}
            for _, p in ipairs(Evora.Players.online()) do list[#list + 1] = p.source end
        end
        local ok, err = pcall(c.custom, list, title, message, color)
        if not ok then Evora.debug("integrations", "Chat.custom: %s", tostring(err)) end
        return
    end
    local payload = { color = color or { 139, 92, 246 }, multiline = true, args = { title or "Evora", message } }
    if targets == -1 then
        TriggerClientEvent("chat:addMessage", -1, payload)
    else
        for _, src in ipairs(targets or {}) do
            TriggerClientEvent("chat:addMessage", src, payload)
        end
    end
end

-- key: Config.Chat entry (Fine, Jail, JailRelease, JailServed)
function Chat.announce(key, vars, involved)
    local entry = Config.Chat and Config.Chat[key]
    if not entry or not entry.enabled then return end
    local message = Utils.format(entry.template, vars)
    local targets = -1
    if entry.audience == "officers" then
        targets = Evora.Officers.militarySources()
        for _, src in ipairs(involved or {}) do targets[#targets + 1] = src end
    elseif entry.audience == "involved" then
        targets = involved or {}
    end
    Chat.send(targets, entry.title, message, entry.color)
end

---------------------------------------------------------------------------
-- Radio (military code)
---------------------------------------------------------------------------
local Radio = {}
I.Radio = Radio

local function radioArgs(c, code, officer)
    if type(c.format) == "function" then
        local ok, args = pcall(c.format, code, officer)
        if ok and type(args) == "table" then return args end
    end
    return { code }
end

function Radio.setCode(src, code, officer)
    if not src then return end
    local c = cfg("Radio")
    local t = c.type or "none"
    if t == "none" then return end
    if t == "statebag" then
        local p = Player(src)
        if p and p.state then p.state:set(c.stateKey or "callsign", code, true) end
    elseif t == "event" and type(c.event) == "string" then
        local args = radioArgs(c, code, officer)
        if c.eventSide == "server" then
            TriggerEvent(c.event, src, table.unpack(args))
        else
            TriggerClientEvent(c.event, src, table.unpack(args))
        end
    elseif t == "client_export" then
        TriggerClientEvent("evora_police:radio", src, code)
    elseif t == "custom" and type(c.custom) == "function" then
        local ok, err = pcall(c.custom, src, code, officer)
        if not ok then Evora.debug("integrations", "Radio.custom: %s", tostring(err)) end
    end
end

function Radio.dutyChanged(src, onDuty, officer)
    local c = cfg("Radio")
    if type(c.onDutyChange) == "function" then
        local ok, err = pcall(c.onDutyChange, src, onDuty, officer)
        if not ok then Evora.debug("integrations", "Radio.onDutyChange: %s", tostring(err)) end
    end
end
