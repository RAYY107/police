--[[
    Evora_Police — server bootstrap: namespace, console output, internal event bus.
]]

Evora = Evora or {}
Evora.version = "1.0.0"
Evora.resource = GetCurrentResourceName()
Evora.ready = false

local function fmt(msg, ...)
    if select("#", ...) > 0 then
        local ok, out = pcall(string.format, msg, ...)
        if ok then return out end
    end
    return tostring(msg)
end

function Evora.print(msg, ...)
    print("^5[Evora_Police]^7 " .. fmt(msg, ...))
end

function Evora.warn(msg, ...)
    print("^3[Evora_Police]^7 " .. fmt(msg, ...))
end

function Evora.error(msg, ...)
    print("^1[Evora_Police]^7 " .. fmt(msg, ...))
end

-- Categories: permissions, groups, sectors, ministries, integrations, database, jail, impound, spectate, rpc
function Evora.debug(category, msg, ...)
    if not Config.Debug then return end
    print(("^6[Evora_Police:%s]^7 %s"):format(category, fmt(msg, ...)))
end

function Evora.now()
    return os.time()
end

function Evora.feature(name)
    local f = Config.Features and Config.Features[name]
    return f ~= nil and f.enabled ~= false
end

-- Runs fn in a new thread and reports errors with a traceback instead of failing silently.
function Evora.thread(fn, ...)
    local args = table.pack(...)
    Citizen.CreateThread(function()
        local ok, err = xpcall(fn, debug.traceback, table.unpack(args, 1, args.n))
        if not ok then Evora.error("thread error: %s", tostring(err)) end
    end)
end

---------------------------------------------------------------------------
-- Internal event bus (module to module)
---------------------------------------------------------------------------
local listeners = {}

function Evora.on(name, fn)
    listeners[name] = listeners[name] or {}
    table.insert(listeners[name], fn)
end

function Evora.emit(name, ...)
    local list = listeners[name]
    if not list then return end
    for i = 1, #list do
        local ok, err = xpcall(list[i], debug.traceback, ...)
        if not ok then Evora.error("listener '%s' failed: %s", name, tostring(err)) end
    end
end

---------------------------------------------------------------------------
-- Server → client helpers
---------------------------------------------------------------------------
function Evora.toClient(src, event, ...)
    if src then TriggerClientEvent("evora_police:" .. event, src, ...) end
end

function Evora.ui(src, action, data)
    if src then TriggerClientEvent("evora_police:ui", src, action, data or {}) end
end

-- Server → client request with a response (client-side facts only, e.g. own clothing).
local creq = { id = 0, pending = {} }

function Evora.clientRequest(src, name, args, timeoutMs)
    creq.id = creq.id + 1
    local id = creq.id
    local p = promise.new()
    creq.pending[id] = { src = src, p = p }
    TriggerClientEvent("evora_police:creq", src, id, name, args or {})
    SetTimeout(timeoutMs or 5000, function()
        local entry = creq.pending[id]
        if entry then
            creq.pending[id] = nil
            entry.p:resolve({ ok = false })
        end
    end)
    local r = Citizen.Await(p)
    if not r.ok then return nil end
    return r.value
end

RegisterNetEvent("evora_police:cres", function(id, value)
    local src = source
    local entry = creq.pending[id]
    if not entry or entry.src ~= src then return end -- only the asked client may answer
    creq.pending[id] = nil
    entry.p:resolve({ ok = true, value = value })
end)
