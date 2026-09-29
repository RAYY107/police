--[[
    Evora_Police — Universal vRP bridge

    vRP 0.5 exists with two incompatible calling conventions:
        legacy : vRP.getUserId({source})          vRPclient.fn(source, {args}, callback)
        modern : vRP.getUserId(source)            vRPclient.fn(source, ...) / vRPclient._fn(...)
    The convention is detected from vrp/lib/Proxy.lua (or forced with Config.Framework.CallStyle).

    Rules:
      * never call a vRP function that may not exist in legacy mode: the legacy proxy returns the
        previous call's values when a function is missing;
      * every callback / client call is awaited with a timeout so a dropped player never hangs a thread.
]]

local Framework = {
    available = false,
    style = nil,
    groupsCfg = nil,
}
Evora.Framework = Framework

local vRP, vRPclient
local legacy = false
local TIMEOUT = 6000

local function resourceName()
    return (Config.Framework and Config.Framework.Resource) or "vrp"
end

local function awaitCallback(starter, timeoutMs)
    local p = promise.new()
    local done = false
    starter(function(...)
        if done then return end
        done = true
        p:resolve(table.pack(...))
    end)
    SetTimeout(timeoutMs or TIMEOUT, function()
        if done then return end
        done = true
        p:resolve({ n = 0, timeout = true })
    end)
    local r = Citizen.Await(p)
    return table.unpack(r, 1, r.n or 0)
end

local function detectStyle()
    local forced = Config.Framework and Config.Framework.CallStyle
    if forced == "legacy" or forced == "modern" then return forced end
    local src = LoadResourceFile(resourceName(), "lib/Proxy.lua") or ""
    if src:find("proxy_rdata", 1, true) or src:find("function%s*%(%s*args%s*,%s*callback%s*%)") then
        return "legacy"
    end
    return "modern"
end

local function loadLibraries()
    local res = resourceName()
    local state = GetResourceState(res)
    if state ~= "started" and state ~= "starting" then
        return false, ("resource '%s' is %s"):format(res, tostring(state))
    end
    if type(module) ~= "function" then
        local code = LoadResourceFile(res, "lib/utils.lua")
        if not code then return false, "lib/utils.lua not found in " .. res end
        local chunk, err = load(code, "@" .. res .. "/lib/utils.lua")
        if not chunk then return false, err end
        local ok, loadErr = pcall(chunk)
        if not ok then return false, loadErr end
    end
    local okProxy, Proxy = pcall(module, res, "lib/Proxy")
    local okTunnel, Tunnel = pcall(module, res, "lib/Tunnel")
    if not okProxy or type(Proxy) ~= "table" then return false, "lib/Proxy unavailable" end
    if not okTunnel or type(Tunnel) ~= "table" then return false, "lib/Tunnel unavailable" end
    vRP = Proxy.getInterface("vRP")
    vRPclient = Tunnel.getInterface("vRP", Evora.resource)
    return true
end

function Framework.init()
    local ok, err = loadLibraries()
    if not ok then
        Framework.available = false
        Evora.error("vRP unavailable (%s). Police features are disabled until vRP is running.", tostring(err))
        return false
    end
    Framework.style = detectStyle()
    legacy = Framework.style == "legacy"
    Framework.available = true
    Framework.loadGroupsConfig()
    Evora.print("vRP bridge ready (%s calling convention).", Framework.style)
    return true
end

---------------------------------------------------------------------------
-- Low level calls
---------------------------------------------------------------------------
local function rawCall(fname, ...)
    local fn = vRP[fname]
    if legacy then return fn({ ... }) end
    return fn(...)
end

function Framework.call(fname, ...)
    if not Framework.available then return nil end
    local r = table.pack(pcall(rawCall, fname, ...))
    if not r[1] then
        Evora.debug("integrations", "vRP.%s failed: %s", fname, tostring(r[2]))
        return nil
    end
    return table.unpack(r, 2, r.n)
end

-- vRP functions that answer through a callback in the legacy convention.
function Framework.callAsync(fname, timeoutMs, ...)
    if not Framework.available then return nil end
    local args = table.pack(...)
    if legacy then
        return awaitCallback(function(done)
            local list = { table.unpack(args, 1, args.n) }
            list[args.n + 1] = function(...) done(...) end
            local ok, err = pcall(vRP[fname], list)
            if not ok then
                Evora.debug("integrations", "vRP.%s failed: %s", fname, tostring(err))
                done()
            end
        end, timeoutMs)
    end
    return awaitCallback(function(done)
        Citizen.CreateThread(function()
            local r = table.pack(pcall(vRP[fname], table.unpack(args, 1, args.n)))
            if r[1] then done(table.unpack(r, 2, r.n)) else done() end
        end)
    end, timeoutMs)
end

-- Client tunnel call that returns values (awaited with timeout).
function Framework.client(fname, source, ...)
    if not Framework.available or not source then return nil end
    local args = table.pack(...)
    if legacy then
        return awaitCallback(function(done)
            local ok = pcall(vRPclient[fname], source, { table.unpack(args, 1, args.n) }, function(...) done(...) end)
            if not ok then done() end
        end)
    end
    return awaitCallback(function(done)
        Citizen.CreateThread(function()
            local r = table.pack(pcall(vRPclient[fname], source, table.unpack(args, 1, args.n)))
            if r[1] then done(table.unpack(r, 2, r.n)) else done() end
        end)
    end)
end

-- Client tunnel call without waiting.
function Framework.clientNoWait(fname, source, ...)
    if not Framework.available or not source then return end
    if legacy then
        pcall(vRPclient[fname], source, { ... })
    else
        pcall(vRPclient["_" .. fname], source, ...)
    end
end

---------------------------------------------------------------------------
-- Users
---------------------------------------------------------------------------
function Framework.getUserId(source)
    local id = Framework.call("getUserId", source)
    return tonumber(id)
end

function Framework.getUserSource(user_id)
    local src = Framework.call("getUserSource", user_id)
    return tonumber(src)
end

function Framework.getUsers()
    local users = Framework.call("getUsers")
    local out = {}
    if type(users) == "table" then
        for uid, src in pairs(users) do
            local u, s = tonumber(uid), tonumber(src)
            if u and s then out[u] = s end
        end
    end
    return out
end

---------------------------------------------------------------------------
-- Groups
---------------------------------------------------------------------------
function Framework.getUserGroups(user_id)
    local groups = Framework.call("getUserGroups", user_id)
    local set = {}
    if type(groups) == "table" then
        for k, v in pairs(groups) do
            if type(k) == "string" and v then
                set[k] = true
            elseif type(v) == "string" then
                set[v] = true
            end
        end
    end
    return set
end

function Framework.hasGroup(user_id, group)
    return Framework.call("hasGroup", user_id, group) == true
end

function Framework.addUserGroup(user_id, group)
    Framework.call("addUserGroup", user_id, group)
    Evora.debug("groups", "addUserGroup(%s, %s)", tostring(user_id), tostring(group))
end

function Framework.removeUserGroup(user_id, group)
    Framework.call("removeUserGroup", user_id, group)
    Evora.debug("groups", "removeUserGroup(%s, %s)", tostring(user_id), tostring(group))
end

function Framework.getUserGroupByType(user_id, gtype)
    local g = Framework.call("getUserGroupByType", user_id, gtype)
    if type(g) == "string" and g ~= "" then return g end
    return nil
end

function Framework.loadGroupsConfig()
    Framework.groupsCfg = nil
    if not (Config.Framework and Config.Framework.ReadGroupsConfig) then return end
    if type(module) ~= "function" then return end
    local ok, cfg = pcall(module, resourceName(), "cfg/groups")
    if ok and type(cfg) == "table" and type(cfg.groups) == "table" then
        Framework.groupsCfg = cfg.groups
        Evora.debug("groups", "loaded %d groups from %s/cfg/groups.lua", Utils.count(cfg.groups), resourceName())
    else
        Evora.debug("groups", "could not read %s/cfg/groups.lua", resourceName())
    end
end

-- true / false when groups.lua was read, nil when unknown
function Framework.groupExists(group)
    if not Framework.groupsCfg then return nil end
    return Framework.groupsCfg[group] ~= nil
end

function Framework.groupTitle(group)
    local g = Framework.groupsCfg and Framework.groupsCfg[group]
    if type(g) == "table" and type(g._config) == "table" and type(g._config.title) == "string" then
        return g._config.title
    end
    return nil
end

---------------------------------------------------------------------------
-- Money
---------------------------------------------------------------------------
function Framework.getMoney(user_id)
    return tonumber(Framework.call("getMoney", user_id)) or 0
end

function Framework.getBankMoney(user_id)
    return tonumber(Framework.call("getBankMoney", user_id)) or 0
end

-- method: "wallet" | "bank" | "full". Only primitives that exist in every vRP 0.5 are used.
function Framework.pay(user_id, amount, method)
    amount = math.floor(tonumber(amount) or 0)
    if amount <= 0 then return true end
    method = method or "full"
    if method == "wallet" then
        return Framework.call("tryPayment", user_id, amount) == true
    end
    if method == "bank" then
        local bank = Framework.getBankMoney(user_id)
        if bank < amount then return false end
        Framework.call("setBankMoney", user_id, bank - amount)
        return true
    end
    local wallet = Framework.getMoney(user_id)
    if wallet >= amount then
        return Framework.call("tryPayment", user_id, amount) == true
    end
    local bank = Framework.getBankMoney(user_id)
    if wallet + bank < amount then return false end
    local fromBank = amount - wallet
    if wallet > 0 and Framework.call("tryPayment", user_id, wallet) ~= true then return false end
    Framework.call("setBankMoney", user_id, bank - fromBank)
    return true
end

function Framework.giveMoney(user_id, amount)
    Framework.call("giveMoney", user_id, math.floor(amount))
end

---------------------------------------------------------------------------
-- Inventory / server data
---------------------------------------------------------------------------
function Framework.getInventory(user_id)
    local data = Framework.call("getUserDataTable", user_id)
    if type(data) == "table" and type(data.inventory) == "table" then return data.inventory end
    return {}
end

function Framework.getItemName(item)
    local name = Framework.call("getItemName", item)
    if type(name) == "string" and name ~= "" then return name end
    return item
end

function Framework.getItemAmount(user_id, item)
    return tonumber(Framework.call("getInventoryItemAmount", user_id, item)) or 0
end

function Framework.tryGetItem(user_id, item, amount)
    return Framework.call("tryGetInventoryItem", user_id, item, amount, false) == true
end

function Framework.giveItem(user_id, item, amount)
    Framework.call("giveInventoryItem", user_id, item, amount, false)
    return true
end

function Framework.getSData(key)
    local value = Framework.callAsync("getSData", TIMEOUT, key)
    return value
end

function Framework.setSData(key, value)
    Framework.call("setSData", key, value)
end

---------------------------------------------------------------------------
-- Menus / prompts
---------------------------------------------------------------------------
function Framework.registerMenuBuilder(name, builder)
    Framework.call("registerMenuBuilder", name, builder)
end

function Framework.openMenu(source, menudata)
    Framework.call("openMenu", source, menudata)
end

function Framework.closeMenu(source)
    Framework.call("closeMenu", source)
end

function Framework.prompt(source, title, default, timeoutMs)
    if legacy then
        local _, value = Framework.callAsync("prompt", timeoutMs, source, title, default or "")
        return value
    end
    local value = Framework.callAsync("prompt", timeoutMs, source, title, default or "")
    return value
end
