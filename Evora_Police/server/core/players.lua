--[[
    Evora_Police — online players, FiveM name cache and server-side positions.

    Identity rule: names are FiveM names (GetPlayerName), ids are vRP user ids.
]]

local Players = {
    byUser = {},     -- [user_id] = source
    bySource = {},   -- [source] = user_id
    names = {},      -- [user_id] = last known FiveM name
}
Evora.Players = Players

local oneSync = nil

function Players.oneSync()
    if oneSync == nil then
        local setting = Config.OneSync
        if setting == true or setting == false then
            oneSync = setting
        else
            local mode = GetConvar("onesync", "off")
            local legacyFlag = GetConvar("onesync_enabled", "false")
            oneSync = (mode ~= "off" and mode ~= "") or legacyFlag == "true" or legacyFlag == "1"
        end
    end
    return oneSync
end

function Players.attach(user_id, source)
    user_id, source = tonumber(user_id), tonumber(source)
    if not user_id or not source then return end
    local previous = Players.byUser[user_id]
    if previous and previous ~= source then Players.bySource[previous] = nil end
    local previousUser = Players.bySource[source]
    if previousUser and previousUser ~= user_id then Players.byUser[previousUser] = nil end
    Players.byUser[user_id] = source
    Players.bySource[source] = user_id
    local name = GetPlayerName(source)
    if name then Players.names[user_id] = Utils.safeName(name) end
end

function Players.detach(user_id, source)
    user_id, source = tonumber(user_id), tonumber(source)
    if user_id and (source == nil or Players.byUser[user_id] == source) then Players.byUser[user_id] = nil end
    if source and (user_id == nil or Players.bySource[source] == user_id) then Players.bySource[source] = nil end
end

function Players.getUserId(source)
    source = tonumber(source)
    if not source then return nil end
    local uid = Players.bySource[source]
    if uid then return uid end
    uid = Evora.Framework.getUserId(source)
    if uid then Players.attach(uid, source) end
    return uid
end

-- Online source of a vRP user id (nil when offline).
function Players.getSource(user_id)
    user_id = tonumber(user_id)
    if not user_id then return nil end
    local src = Players.byUser[user_id]
    if src then
        if GetPlayerName(src) then return src end
        Players.detach(user_id, src)
    end
    return nil
end

function Players.isOnline(user_id)
    return Players.getSource(user_id) ~= nil
end

-- FiveM name of a vRP user id (online name, then cache, then database).
function Players.name(user_id)
    user_id = tonumber(user_id)
    if not user_id then return L("unknown_player") end
    local src = Players.byUser[user_id]
    if src then
        local live = GetPlayerName(src)
        if live then
            live = Utils.safeName(live)
            Players.names[user_id] = live
            return live
        end
    end
    local cached = Players.names[user_id]
    if cached then return cached end
    local row = Evora.DB.single("SELECT name FROM evora_police_players WHERE user_id = ?", { user_id })
    if row and row.name and row.name ~= "" then
        Players.names[user_id] = row.name
        return row.name
    end
    return L("unknown_player")
end

function Players.remember(user_id, source)
    local name = Utils.safeName(GetPlayerName(source) or "")
    Players.names[user_id] = name
    local now = Evora.now()
    Evora.DB.execute(
        "INSERT INTO evora_police_players (user_id, name, last_seen) VALUES (?, ?, ?) ON DUPLICATE KEY UPDATE name = ?, last_seen = ?",
        { user_id, name, now, name, now }
    )
end

-- A vRP id that was seen by Evora_Police (online now or stored before).
function Players.exists(user_id)
    user_id = tonumber(user_id)
    if not user_id or user_id < 1 then return false end
    if Players.isOnline(user_id) then return true end
    if Players.names[user_id] then return true end
    local n = Evora.DB.scalar("SELECT COUNT(*) AS c FROM evora_police_players WHERE user_id = ?", { user_id })
    return (tonumber(n) or 0) > 0
end

function Players.online()
    local list = {}
    for uid, src in pairs(Players.byUser) do
        list[#list + 1] = { user_id = uid, source = src }
    end
    return list
end

---------------------------------------------------------------------------
-- Positions
---------------------------------------------------------------------------
function Players.coords(source)
    if not source then return nil end
    if Players.oneSync() then
        local ped = GetPlayerPed(source)
        if not ped or ped == 0 then return nil end
        return Utils.vec(GetEntityCoords(ped))
    end
    local value = Evora.clientRequest(source, "coords", nil, 4000)
    return value and Utils.vec(value) or nil
end

local function bucket(source)
    if GetPlayerRoutingBucket then return GetPlayerRoutingBucket(source) or 0 end
    return 0
end

function Players.distance(a, b)
    if bucket(a) ~= bucket(b) then return math.huge end
    local ca, cb = Players.coords(a), Players.coords(b)
    if not ca or not cb then return math.huge end
    return Utils.dist(ca, cb)
end

-- Players around `source` within radius, closest first: { source, user_id, name, dist }
function Players.nearby(source, radius)
    local out = {}
    local origin = Players.coords(source)
    if not origin then return out end
    local myBucket = bucket(source)
    if Players.oneSync() then
        for uid, src in pairs(Players.byUser) do
            if src ~= source and bucket(src) == myBucket then
                local c = Players.coords(src)
                local d = c and Utils.dist(origin, c) or math.huge
                if d <= radius then
                    out[#out + 1] = { source = src, user_id = uid, name = Players.name(uid), dist = d }
                end
            end
        end
    else
        local list = Evora.clientRequest(source, "nearbyPlayers", { radius = radius }, 4000) or {}
        for _, entry in ipairs(list) do
            local src = tonumber(type(entry) == "table" and entry.source)
            local uid = src and Players.bySource[src]
            if uid and src ~= source then
                local d = tonumber(entry.dist) or radius
                if d <= radius then
                    out[#out + 1] = { source = src, user_id = uid, name = Players.name(uid), dist = d }
                end
            end
        end
    end
    table.sort(out, function(a, b) return a.dist < b.dist end)
    return out
end

function Players.teleport(source, coords, heading)
    if not source or not coords then return end
    TriggerClientEvent("evora_police:teleport", source, coords.x, coords.y, coords.z, heading)
end
