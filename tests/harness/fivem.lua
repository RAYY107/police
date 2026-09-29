-- FiveM server natives mock. Installs globals; state lives in the harness table H.
local S = require("harness.scheduler")
local json = require("harness.json")

local M = {}

local function joaat(s)
    s = tostring(s):lower()
    local h = 0
    for i = 1, #s do
        h = (h + s:byte(i)) & 0xFFFFFFFF
        h = (h + ((h << 10) & 0xFFFFFFFF)) & 0xFFFFFFFF
        h = (h ~ (h >> 6)) & 0xFFFFFFFF
    end
    h = (h + ((h << 3) & 0xFFFFFFFF)) & 0xFFFFFFFF
    h = (h ~ (h >> 11)) & 0xFFFFFFFF
    h = (h + ((h << 15) & 0xFFFFFFFF)) & 0xFFFFFFFF
    if h >= 0x80000000 then h = h - 0x100000000 end
    return h
end
M.joaat = joaat

local vecmt = {}
vecmt.__index = function(t, k)
    if k == 1 then return rawget(t, "x") elseif k == 2 then return rawget(t, "y") elseif k == 3 then return rawget(t, "z") end
end
vecmt.__sub = function(a, b) return setmetatable({ x = a.x - b.x, y = a.y - b.y, z = a.z - b.z }, vecmt) end
vecmt.__len = function(a) return math.sqrt(a.x * a.x + a.y * a.y + a.z * a.z) end
local function vector3(x, y, z) return setmetatable({ x = x + 0.0, y = y + 0.0, z = z + 0.0 }, vecmt) end
M.vector3 = vector3

function M.install(H)
    H.handlers = {}
    H.netEvents = {}
    H.sent = {}          -- recorded TriggerClientEvent calls
    H.players = {}       -- [source] = { name, ped, bucket, identifiers }
    H.entities = {}      -- [id] = { kind, coords, model, plate, heading, frozen }
    H.entitySeq = 100
    H.convars = { onesync = "on" }
    H.resources = { oxmysql = "started", vrp = "started", chat = "started" }
    H.files = {}
    H.http = {}
    H.ownExports = {}
    H.resourceExports = {}
    H.statebags = {}
    H.clientResponders = {}

    _G.vector3 = vector3
    _G.vec3 = vector3
    _G.json = json
    _G.promise = S.promise
    _G.Citizen = {
        CreateThread = function(fn) S.spawn(fn) end,
        CreateThreadNow = function(fn) S.spawnNow(fn) end,
        Wait = S.wait,
        Await = S.await,
        SetTimeout = S.setTimeout,
    }
    _G.SetTimeout = S.setTimeout
    _G.GetGameTimer = function() return S.now end
    _G.IsDuplicityVersion = function() return true end
    os.time = function(t) if t then return H.realOsTime(t) end return S.time() end

    -- Events ---------------------------------------------------------------
    local function addHandler(name, fn)
        H.handlers[name] = H.handlers[name] or {}
        table.insert(H.handlers[name], fn)
        return { name = name, fn = fn }
    end
    _G.AddEventHandler = addHandler
    _G.RegisterNetEvent = function(name, fn)
        H.netEvents[name] = true
        if fn then return addHandler(name, fn) end
    end
    _G.RegisterServerEvent = _G.RegisterNetEvent
    _G.TriggerEvent = function(name, ...)
        local args = table.pack(...)
        for _, fn in ipairs(H.handlers[name] or {}) do
            S.spawnNow(function()
                _G.source = nil
                fn(table.unpack(args, 1, args.n))
            end)
        end
    end
    -- A network event coming from a client.
    function H.fromClient(src, name, ...)
        if not H.netEvents[name] then return false end
        local args = table.pack(...)
        for _, fn in ipairs(H.handlers[name] or {}) do
            S.spawnNow(function()
                _G.source = src
                fn(table.unpack(args, 1, args.n))
            end)
        end
        return true
    end
    _G.TriggerClientEvent = function(name, target, ...)
        local entry = { name = name, target = target, args = table.pack(...), at = S.now }
        H.sent[#H.sent + 1] = entry
        if name == "evora_police:teleport" and H.simulateTeleport ~= false and target ~= -1 then
            local x, y, z = ...
            local p = H.players[target]
            if p and H.entities[p.ped] then H.entities[p.ped].coords = vector3(x, y, z) end
        end
        if name == "evora_police:creq" then
            local id, reqName, reqArgs = ...
            local responder = H.clientResponders[reqName]
            if responder and target ~= -1 then
                S.setTimeout(0, function()
                    H.fromClient(target, "evora_police:cres", id, responder(target, reqArgs))
                end)
            end
        end
    end

    -- Players ----------------------------------------------------------------
    _G.GetPlayerName = function(src)
        local p = H.players[tonumber(src)]
        return p and p.name or nil
    end
    _G.GetPlayers = function()
        local list = {}
        for src in pairs(H.players) do list[#list + 1] = tostring(src) end
        return list
    end
    _G.GetPlayerPed = function(src)
        local p = H.players[tonumber(src)]
        return p and p.ped or 0
    end
    _G.GetPlayerIdentifiers = function(src)
        local p = H.players[tonumber(src)]
        return p and p.identifiers or {}
    end
    _G.GetPlayerRoutingBucket = function(src)
        local p = H.players[tonumber(src)]
        return p and p.bucket or 0
    end
    _G.SetPlayerRoutingBucket = function(src, bucket)
        local p = H.players[tonumber(src)]
        if p then p.bucket = bucket end
    end
    _G.Player = function(src)
        H.statebags[src] = H.statebags[src] or {}
        local bag = H.statebags[src]
        return { state = setmetatable({ set = function(_, k, v) bag[k] = v end }, { __index = bag }) }
    end

    -- Entities -----------------------------------------------------------------
    function H.newEntity(kind, coords, extra)
        H.entitySeq = H.entitySeq + 1
        local e = { kind = kind, coords = vector3(coords.x, coords.y, coords.z), heading = 0.0 }
        for k, v in pairs(extra or {}) do e[k] = v end
        H.entities[H.entitySeq] = e
        return H.entitySeq
    end
    _G.DoesEntityExist = function(e) return H.entities[e] ~= nil end
    _G.GetEntityCoords = function(e)
        local ent = H.entities[e]
        if not ent then return vector3(0, 0, 0) end
        return vector3(ent.coords.x, ent.coords.y, ent.coords.z)
    end
    _G.SetEntityCoords = function(e, x, y, z)
        local ent = H.entities[e]
        if ent then ent.coords = vector3(x, y, z) end
    end
    _G.GetEntityModel = function(e) local ent = H.entities[e] return ent and ent.model or 0 end
    _G.GetAllVehicles = function()
        local list = {}
        for id, ent in pairs(H.entities) do
            if ent.kind == "vehicle" then list[#list + 1] = id end
        end
        table.sort(list)
        return list
    end
    _G.GetVehicleNumberPlateText = function(e)
        local ent = H.entities[e]
        return ent and ent.plate or ""
    end
    _G.DeleteEntity = function(e) H.entities[e] = nil end
    _G.NetworkGetNetworkIdFromEntity = function(e) return e + 5000 end
    _G.NetworkGetEntityFromNetworkId = function(id) return id - 5000 end
    _G.CreateObjectNoOffset = function(hash, x, y, z)
        return H.newEntity("object", { x = x, y = y, z = z }, { model = hash })
    end
    _G.SetEntityHeading = function(e, h) local ent = H.entities[e] if ent then ent.heading = h end end
    _G.FreezeEntityPosition = function(e, f) local ent = H.entities[e] if ent then ent.frozen = f end end
    _G.GetHashKey = joaat

    -- Resources / misc -------------------------------------------------------
    _G.GetConvar = function(name, default) local v = H.convars[name] if v == nil then return default end return v end
    _G.GetResourceState = function(name) return H.resources[name] or "missing" end
    _G.GetCurrentResourceName = function() return "Evora_Police" end
    _G.LoadResourceFile = function(res, path) return H.files[res .. "/" .. path] end
    _G.PerformHttpRequest = function(url, cb, method, body, headers)
        H.http[#H.http + 1] = { url = url, method = method, body = body, headers = headers }
        S.setTimeout(0, function() cb(204, "", {}) end)
    end
    _G.exports = setmetatable({}, {
        __call = function(_, name, fn) H.ownExports[name] = fn end,
        __index = function(_, resource) return H.resourceExports[resource] end,
    })
end

-- Helpers for assertions -------------------------------------------------------
function M.helpers(H)
    function H.clientEvents(src, name)
        local list = {}
        for _, e in ipairs(H.sent) do
            if (e.target == src or e.target == -1) and (not name or e.name == name) then list[#list + 1] = e end
        end
        return list
    end
    function H.lastClientEvent(src, name)
        local list = H.clientEvents(src, name)
        return list[#list]
    end
    function H.clearEvents() H.sent = {} end
    function H.uiEvents(src, action)
        local list = {}
        for _, e in ipairs(H.clientEvents(src, "evora_police:ui")) do
            if e.args[1] == action then list[#list + 1] = e.args[2] end
        end
        return list
    end
end

return M
