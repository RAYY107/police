--[[
    Evora_Police — clothing, handcuffs, drag, money, job and profile image adapters.
]]

local I = Evora.Integrations
local cfg = I.cfg
local F = Evora.Framework

local function adapterType(name, default)
    local t = cfg(name).type or default
    if t == "vrp" and not F.available then return "builtin" end
    return t
end

local function customFn(name, fn)
    local c = cfg(name)
    if c.type == "custom" and type(c.custom) == "table" and type(c.custom[fn]) == "function" then
        return c.custom[fn]
    end
    return nil
end

---------------------------------------------------------------------------
-- Clothing (vRP customization format: [component] = {drawable, texture, palette}, ["pN"] = {prop, texture})
---------------------------------------------------------------------------
local Clothing = {}
I.Clothing = Clothing

local FEMALE_MODEL = GetHashKey("mp_f_freemode_01")

function Clothing.get(source)
    local fn = customFn("Clothing", "get")
    if fn then
        local ok, c = pcall(fn, source)
        return ok and type(c) == "table" and c or nil
    end
    local custom
    if adapterType("Clothing", "vrp") == "vrp" then
        custom = F.client("getCustomization", source)
    else
        custom = Evora.clientRequest(source, "clothing:get")
    end
    if type(custom) ~= "table" then return nil end
    return custom
end

function Clothing.set(source, clothing)
    if type(clothing) ~= "table" then return end
    local fn = customFn("Clothing", "set")
    if fn then pcall(fn, source, clothing) return end
    if adapterType("Clothing", "vrp") == "vrp" then
        F.clientNoWait("setCustomization", source, clothing)
    else
        TriggerClientEvent("evora_police:clothing:set", source, clothing)
    end
end

-- JSON round-trips turn component keys into strings ("3"); convert them back to numbers.
function Clothing.normalize(custom)
    if type(custom) ~= "table" then return nil end
    local out = {}
    for k, v in pairs(custom) do
        local n = tonumber(k)
        if n and type(k) == "string" and k:match("^%d+$") then out[n] = v else out[k] = v end
    end
    return out
end

function Clothing.encode(custom)
    return json.encode(custom or {})
end

function Clothing.decode(raw)
    if type(raw) ~= "string" or raw == "" then return nil end
    local ok, data = pcall(json.decode, raw)
    if not ok or type(data) ~= "table" or next(data) == nil then return nil end
    return Clothing.normalize(data)
end

function Clothing.isFemale(custom)
    if type(custom) ~= "table" then return false end
    local model = tonumber(custom.modelhash) or (type(custom.model) == "string" and GetHashKey(custom.model)) or tonumber(custom.model)
    return model == FEMALE_MODEL
end

-- preset = { Male = { components = {...}, props = {...} }, Female = {...} }
-- Returns the clothing that was worn before (to restore later) or nil.
function Clothing.applyPreset(source, preset, current)
    current = current or Clothing.get(source)
    if type(current) ~= "table" then return nil end
    local variant = Clothing.isFemale(current) and (preset.Female or preset.female) or (preset.Male or preset.male)
    if type(variant) ~= "table" then return nil end
    local outfit = {}
    for k, v in pairs(current) do outfit[k] = v end
    for comp, v in pairs(variant.components or {}) do
        outfit[tonumber(comp)] = { tonumber(v[1]) or 0, tonumber(v[2]) or 0, 2 }
    end
    for prop, v in pairs(variant.props or {}) do
        outfit["p" .. tostring(prop)] = { tonumber(v[1]) or -1, tonumber(v[2]) or 0 }
    end
    Clothing.set(source, outfit)
    return current
end

---------------------------------------------------------------------------
-- Handcuffs
---------------------------------------------------------------------------
local Handcuff = {}
I.Handcuff = Handcuff

function Handcuff.isCuffed(source)
    local fn = customFn("Handcuff", "isCuffed")
    if fn then
        local ok, r = pcall(fn, source)
        return ok and r == true
    end
    if adapterType("Handcuff", "vrp") == "vrp" then
        return F.client("isHandcuffed", source) == true
    end
    return Evora.clientRequest(source, "cuff:get") == true
end

function Handcuff.set(source, state)
    local fn = customFn("Handcuff", "setCuffed")
    if fn then pcall(fn, source, state) return end
    if adapterType("Handcuff", "vrp") == "vrp" then
        F.clientNoWait("setHandcuffed", source, state == true)
    else
        TriggerClientEvent("evora_police:cuff:set", source, state == true)
    end
end

function Handcuff.toggle(source)
    local state = not Handcuff.isCuffed(source)
    Handcuff.set(source, state)
    return state
end

---------------------------------------------------------------------------
-- Drag
---------------------------------------------------------------------------
local Drag = {}
I.Drag = Drag

function Drag.toggle(officer, target)
    local c = cfg("Drag")
    local t = c.type or "builtin"
    if t == "custom" and type(c.custom) == "function" then
        local ok, err = pcall(c.custom, officer, target)
        if not ok then Evora.debug("integrations", "Drag.custom: %s", tostring(err)) end
    elseif t == "event" and type(c.event) == "string" and c.event ~= "" then
        local args = { officer }
        if type(c.args) == "function" then
            local ok, a = pcall(c.args, officer, target)
            if ok and type(a) == "table" then args = a end
        end
        if c.eventSide == "server" then
            TriggerEvent(c.event, table.unpack(args))
        else
            local receiver = c.receiver == "officer" and officer or target
            TriggerClientEvent(c.event, receiver, table.unpack(args))
        end
    else
        TriggerClientEvent("evora_police:drag", target, officer)
    end
end

---------------------------------------------------------------------------
-- Money
---------------------------------------------------------------------------
local Money = {}
I.Money = Money

function Money.pay(user_id, amount, method)
    local fn = customFn("Money", "pay")
    if fn then
        local ok, r = pcall(fn, user_id, amount, method)
        return ok and r == true
    end
    if not F.available then return false end
    return F.pay(user_id, amount, method)
end

function Money.give(user_id, amount)
    local fn = customFn("Money", "give")
    if fn then pcall(fn, user_id, amount) return end
    F.giveMoney(user_id, amount)
end

---------------------------------------------------------------------------
-- Job label
---------------------------------------------------------------------------
local Job = {}
I.Job = Job

-- vRP 0.5 keeps offline groups in the user datatable.
local function offlineGroups(user_id)
    local raw = Evora.DB.scalar("SELECT dvalue FROM vrp_user_data WHERE user_id = ? AND dkey = 'vRP:datatable'", { user_id })
    if type(raw) ~= "string" then return nil end
    local ok, data = pcall(json.decode, raw)
    if ok and type(data) == "table" and type(data.groups) == "table" then return data.groups end
    return nil
end
Job.offlineGroups = offlineGroups

function Job.get(user_id)
    local c = cfg("Job")
    local unemployed = c.unemployed or "—"
    if c.type == "custom" and type(c.custom) == "function" then
        local ok, label = pcall(c.custom, user_id, Evora.Players.getSource(user_id))
        if ok and type(label) == "string" and label ~= "" then return label end
        return unemployed
    end
    local gtype = (Config.Framework and Config.Framework.JobGroupType) or "job"
    local group
    if Evora.Players.isOnline(user_id) then
        group = F.getUserGroupByType(user_id, gtype)
    elseif F.groupsCfg then
        for g in pairs(offlineGroups(user_id) or {}) do
            local def = F.groupsCfg[g]
            if type(def) == "table" and type(def._config) == "table" and def._config.gtype == gtype then
                group = g
                break
            end
        end
    end
    if not group then return unemployed end
    local rank = Evora.Gov.ranks[group]
    if rank then return Evora.Gov.rankLabel(group) end
    return F.groupTitle(group) or group
end

---------------------------------------------------------------------------
-- Profile image
---------------------------------------------------------------------------
local ProfileImage = { cache = {} }
I.ProfileImage = ProfileImage

local function identifiers(source)
    local out = {}
    if not source then return out end
    for _, id in ipairs(GetPlayerIdentifiers(source) or {}) do
        local kind, value = id:match("^(%w+):(.+)$")
        if kind then out[kind] = value end
    end
    return out
end

local function httpGet(url, headers)
    local p = promise.new()
    local finished = false
    PerformHttpRequest(url, function(status, body)
        if finished then return end
        finished = true
        p:resolve({ status = status, body = body })
    end, "GET", "", headers or {})
    SetTimeout(8000, function()
        if finished then return end
        finished = true
        p:resolve({ status = 0 })
    end)
    return Citizen.Await(p)
end

local function fetchDiscord(discordId)
    local token = Config.Secrets and Config.Secrets.DiscordBotToken
    if not discordId or type(token) ~= "string" or token == "" then return nil end
    local r = httpGet("https://discord.com/api/v10/users/" .. discordId, { Authorization = "Bot " .. token })
    if r.status ~= 200 then return nil end
    local ok, data = pcall(json.decode, r.body or "")
    if not ok or type(data) ~= "table" or not data.avatar then return nil end
    local ext = tostring(data.avatar):sub(1, 2) == "a_" and "gif" or "png"
    return ("https://cdn.discordapp.com/avatars/%s/%s.%s?size=256"):format(discordId, data.avatar, ext)
end

local function fetchSteam(steamHex)
    local key = Config.Secrets and Config.Secrets.SteamApiKey
    if not steamHex or type(key) ~= "string" or key == "" then return nil end
    local steam64 = tonumber(steamHex, 16)
    if not steam64 then return nil end
    local url = ("https://api.steampowered.com/ISteamUser/GetPlayerSummaries/v0002/?key=%s&steamids=%s"):format(key, math.tointeger(steam64) or steam64)
    local r = httpGet(url)
    if r.status ~= 200 then return nil end
    local ok, data = pcall(json.decode, r.body or "")
    local players = ok and type(data) == "table" and data.response and data.response.players
    local first = type(players) == "table" and players[1]
    return first and first.avatarfull or nil
end

function ProfileImage.get(user_id)
    local c = cfg("ProfileImage")
    local t = c.type or "none"
    if t == "none" then return nil end
    local ttl = (tonumber(c.cacheMinutes) or 60) * 60
    local now = Evora.now()
    local cached = ProfileImage.cache[user_id]
    if cached and now - cached.at < ttl then return cached.url end

    local source = Evora.Players.getSource(user_id)
    local url
    if t == "custom" and type(c.custom) == "function" then
        local ok, r = pcall(c.custom, user_id, source)
        url = ok and type(r) == "string" and r or nil
    elseif source then
        local ids = identifiers(source)
        if t == "url" and type(c.url) == "string" then
            url = Utils.format(c.url, { user_id = user_id, discord = ids.discord or "", steam = ids.steam or "", license = ids.license or "" })
        elseif t == "discord" then
            url = fetchDiscord(ids.discord)
        elseif t == "steam" then
            url = fetchSteam(ids.steam)
        end
    end

    if not url then
        local row = Evora.DB.single("SELECT avatar, avatar_at FROM evora_police_players WHERE user_id = ?", { user_id })
        if row and row.avatar and row.avatar ~= "" then url = row.avatar end
    elseif source then
        Evora.DB.executeAsync("UPDATE evora_police_players SET avatar = ?, avatar_at = ? WHERE user_id = ?", { url, now, user_id })
    end
    ProfileImage.cache[user_id] = { url = url, at = now }
    return url
end

---------------------------------------------------------------------------
-- Start-up availability report
---------------------------------------------------------------------------
function I.checkAll()
    local frameworkUp = F.available
    local function needsVrp(name, default)
        local t = cfg(name).type or default
        if t == "vrp" or t == "vrp_chest" then
            I.report(name, frameworkUp, frameworkUp and "vRP" or "vRP not running")
        else
            I.report(name, true, t)
        end
    end

    local menu = cfg("BuilderMenu").type or "vrp"
    I.report("Builder Menu", menu ~= "vrp" or frameworkUp, menu)

    local notify = cfg("Notify")
    if notify.type == "client_export" then
        I.report("Notify", I.resourceUp(notify.resource), notify.resource)
    else
        I.report("Notify", notify.type ~= "vrp" or frameworkUp, notify.type or "vrp")
    end

    local radio = cfg("Radio")
    if radio.type == "client_export" then
        I.report("Radio", I.resourceUp(radio.resource), radio.resource)
    elseif radio.type == "event" then
        I.report("Radio", type(radio.event) == "string" and radio.event ~= "", radio.event)
    else
        I.report("Radio", true, radio.type or "none")
    end

    local garage = cfg("VehicleGarage")
    if garage.type == "export" then
        I.report("Vehicle garage", type(garage.export) == "table" and I.resourceUp(garage.export.resource), garage.export and garage.export.resource)
    elseif garage.type == "sql" or garage.type == nil then
        I.report("Vehicle garage", Evora.DB.ready and type(garage.sql) == "table" and type(garage.sql.ownerByPlate) == "string", "sql")
    else
        I.report("Vehicle garage", type(garage.custom) == "function", garage.type)
    end

    local vinv = cfg("VehicleInventory")
    if vinv.type == "custom" then
        I.report("Vehicle inventory", type(vinv.custom) == "table" and type(vinv.custom.getItems) == "function", "custom")
    else
        I.report("Vehicle inventory", frameworkUp, frameworkUp and "vRP chests" or "vRP not running")
    end

    needsVrp("Inventory", "vrp")
    needsVrp("Weapons", "vrp")
    needsVrp("Clothing", "vrp")
    needsVrp("Handcuff", "vrp")
    needsVrp("Seats", "vrp")
    needsVrp("Money", "vrp")

    local img = cfg("ProfileImage")
    if img.type == "discord" then
        I.report("Profile image", type(Config.Secrets) == "table" and (Config.Secrets.DiscordBotToken or "") ~= "", "discord bot token missing in config/server.lua")
    elseif img.type == "steam" then
        I.report("Profile image", type(Config.Secrets) == "table" and (Config.Secrets.SteamApiKey or "") ~= "", "steam api key missing in config/server.lua")
    end

    I.report("Chat", true, cfg("Chat").type or "chat")
end
