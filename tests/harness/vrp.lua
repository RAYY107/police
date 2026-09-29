-- vRP 0.5 mock supporting both the legacy (table args + callbacks) and modern (varargs) conventions.
local S = require("harness.scheduler")

local M = {}

local function copy(t)
    if type(t) ~= "table" then return t end
    local o = {}
    for k, v in pairs(t) do o[k] = copy(v) end
    return o
end

function M.install(H, style)
    local V = {
        style = style or "legacy",
        users = {},          -- [uid] = { source, groups, inventory, wallet, bank, weapons, custom, cuffed }
        sources = {},        -- [src] = uid
        sdata = {},
        items = { weed = "حشيش", cocaine = "كوكايين", meth = "ميث", water = "ماء", bandage = "ضماد", dirty_money = "أموال قذرة", lockpick = "مفك" },
        builders = {},
        menus = {},          -- [src] = last opened menudata
        prompts = {},        -- [src] = queue of answers (nil entry = cancel)
        calls = {},          -- recorded client tunnel calls
        groupsCfg = {},
    }
    H.vrp = V

    local function user(uid) return V.users[tonumber(uid)] end

    local function gtypeOf(g)
        local def = V.groupsCfg[g]
        return def and def._config and def._config.gtype or nil
    end

    local impl = {}
    function impl.getUserId(src) return V.sources[tonumber(src)] end
    function impl.getUserSource(uid) local u = user(uid) return u and u.source or nil end
    function impl.getUsers()
        local t = {}
        for uid, u in pairs(V.users) do if u.source then t[uid] = u.source end end
        return t
    end
    function impl.getUserGroups(uid) local u = user(uid) return u and copy(u.groups) or {} end
    function impl.hasGroup(uid, g) local u = user(uid) return u ~= nil and u.groups[g] == true end
    function impl.addUserGroup(uid, g)
        local u = user(uid)
        if not u then return end
        local gtype = gtypeOf(g)
        if gtype then
            for og in pairs(copy(u.groups)) do
                if og ~= g and gtypeOf(og) == gtype then
                    u.groups[og] = nil
                    TriggerEvent("vRP:playerLeaveGroup", uid, og, gtype)
                end
            end
        end
        if not u.groups[g] then
            u.groups[g] = true
            TriggerEvent("vRP:playerJoinGroup", uid, g, gtype)
        end
    end
    function impl.removeUserGroup(uid, g)
        local u = user(uid)
        if u and u.groups[g] then
            u.groups[g] = nil
            TriggerEvent("vRP:playerLeaveGroup", uid, g, gtypeOf(g))
        end
    end
    function impl.getUserGroupByType(uid, gtype)
        local u = user(uid)
        if not u then return nil end
        for g in pairs(u.groups) do if gtypeOf(g) == gtype then return g end end
        return nil
    end
    function impl.hasPermission() return false end
    function impl.getMoney(uid) local u = user(uid) return u and u.wallet or 0 end
    function impl.tryPayment(uid, amount)
        local u = user(uid)
        if u and u.wallet >= amount then u.wallet = u.wallet - amount return true end
        return false
    end
    function impl.giveMoney(uid, amount) local u = user(uid) if u then u.wallet = u.wallet + amount end end
    function impl.getBankMoney(uid) local u = user(uid) return u and u.bank or 0 end
    function impl.setBankMoney(uid, v) local u = user(uid) if u then u.bank = v end end
    function impl.getUserDataTable(uid)
        local u = user(uid)
        if not u then return nil end
        local inv = {}
        for k, v in pairs(u.inventory) do inv[k] = { amount = v } end
        return { inventory = inv, groups = copy(u.groups) }
    end
    function impl.getInventoryItemAmount(uid, item) local u = user(uid) return u and u.inventory[item] or 0 end
    function impl.tryGetInventoryItem(uid, item, amount)
        local u = user(uid)
        if u and (u.inventory[item] or 0) >= amount then
            u.inventory[item] = u.inventory[item] - amount
            if u.inventory[item] <= 0 then u.inventory[item] = nil end
            return true
        end
        return false
    end
    function impl.giveInventoryItem(uid, item, amount)
        local u = user(uid)
        if u then u.inventory[item] = (u.inventory[item] or 0) + amount end
    end
    function impl.getItemName(item) return V.items[item] or item end
    function impl.getSData(key, cb)
        local v = V.sdata[key] or ""
        if type(cb) == "function" then cb(v) return end
        return v
    end
    function impl.setSData(key, value) V.sdata[key] = value end
    function impl.registerMenuBuilder(name, fn)
        V.builders[name] = V.builders[name] or {}
        table.insert(V.builders[name], fn)
    end
    function impl.openMenu(src, menudata) V.menus[tonumber(src)] = menudata end
    function impl.closeMenu(src) V.menus[tonumber(src)] = nil end
    function impl.prompt(src, title, default, cb)
        local queue = V.prompts[tonumber(src)] or {}
        local answer = table.remove(queue, 1)
        V.lastPrompt = { src = src, title = title }
        if type(cb) == "function" then cb(src, answer) return end
        return answer
    end
    function impl.request(src, text, time, cb)
        if type(cb) == "function" then cb(src, true) return end
        return true
    end
    V.impl = impl

    local client = {}
    function client.notify(src, msg) V.calls[#V.calls + 1] = { fn = "notify", src = src, args = { msg } } end
    function client.getWeapons(src) local u = user(V.sources[src]) return u and copy(u.weapons) or {} end
    function client.giveWeapons(src, weapons, clear)
        local u = user(V.sources[src])
        if not u then return end
        if clear then u.weapons = {} end
        for k, v in pairs(weapons or {}) do u.weapons[k] = copy(v) end
    end
    function client.getCustomization(src) local u = user(V.sources[src]) return u and copy(u.custom) or nil end
    function client.setCustomization(src, custom) local u = user(V.sources[src]) if u then u.custom = copy(custom) end end
    function client.isHandcuffed(src) local u = user(V.sources[src]) return u ~= nil and u.cuffed == true end
    function client.setHandcuffed(src, flag) local u = user(V.sources[src]) if u then u.cuffed = flag == true end end
    function client.toggleHandcuff(src) local u = user(V.sources[src]) if u then u.cuffed = not u.cuffed end end
    function client.putInNearestVehicleAsPassenger(src, radius) V.calls[#V.calls + 1] = { fn = "putIn", src = src } return true end
    function client.ejectVehicle(src) V.calls[#V.calls + 1] = { fn = "eject", src = src } end
    V.client = client

    -- Fake Proxy / Tunnel libraries -------------------------------------------------
    local Proxy = {}
    function Proxy.getInterface(name)
        return setmetatable({}, { __index = function(_, fname)
            if V.style == "legacy" then
                return function(args)
                    local fn = impl[fname]
                    if not fn then return nil end
                    return fn(table.unpack(args or {}, 1, #(args or {}) + 1))
                end
            end
            return function(...)
                local fn = impl[fname]
                if not fn then return nil end
                return fn(...)
            end
        end })
    end

    local Tunnel = {}
    function Tunnel.getInterface(name, id)
        return setmetatable({}, { __index = function(_, fname)
            if V.style == "legacy" then
                return function(src, args, cb)
                    local fn = client[fname]
                    local r = table.pack(fn and fn(src, table.unpack(args or {})) or nil)
                    if type(cb) == "function" then S.setTimeout(0, function() cb(table.unpack(r, 1, r.n)) end) end
                end
            end
            local noWait = fname:sub(1, 1) == "_"
            local real = noWait and fname:sub(2) or fname
            return function(src, ...)
                local fn = client[real]
                if noWait then if fn then fn(src, ...) end return end
                return fn and fn(src, ...) or nil
            end
        end })
    end

    _G.module = function(rsc, path)
        if path == nil then path, rsc = rsc, "vrp" end
        if path == "lib/Proxy" then return Proxy end
        if path == "lib/Tunnel" then return Tunnel end
        if path == "cfg/groups" then return { groups = V.groupsCfg } end
        error("unknown module " .. tostring(path))
    end

    H.files["vrp/lib/Proxy.lua"] = V.style == "legacy"
        and "local proxy_rdata = {} local function proxy_callback(rvalues) proxy_rdata = rvalues end local fcall = function(args,callback) end"
        or "local fcall = function(...) TriggerEvent(iname..':proxy',fname,args,identifier,rid) end -- proxy_res"
    return V
end

return M
