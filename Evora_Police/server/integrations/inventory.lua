--[[
    Evora_Police — inventory, weapons and vehicle inventory adapters.
]]

local I = Evora.Integrations
local cfg = I.cfg
local F = Evora.Framework

---------------------------------------------------------------------------
-- Player inventory
---------------------------------------------------------------------------
local Inventory = {}
I.Inventory = Inventory

local function custom(name)
    local c = cfg("Inventory")
    if c.type == "custom" and type(c.custom) == "table" and type(c.custom[name]) == "function" then
        return c.custom[name]
    end
    return nil
end

-- → { { item = "id", label = "name", amount = n }, ... }
function Inventory.getItems(user_id, source)
    local fn = custom("getItems")
    if fn then
        local ok, items = pcall(fn, user_id, source)
        return ok and type(items) == "table" and items or {}
    end
    if not F.available then return {} end
    local list = {}
    for idname, entry in pairs(F.getInventory(user_id)) do
        local amount = type(entry) == "table" and tonumber(entry.amount) or tonumber(entry) or 0
        if amount > 0 then
            list[#list + 1] = { item = idname, label = F.getItemName(idname), amount = amount }
        end
    end
    table.sort(list, function(a, b) return tostring(a.label) < tostring(b.label) end)
    return list
end

function Inventory.getAmount(user_id, item)
    local fn = custom("getAmount")
    if fn then
        local ok, n = pcall(fn, user_id, item)
        return ok and tonumber(n) or 0
    end
    return F.getItemAmount(user_id, item)
end

function Inventory.remove(user_id, item, amount)
    local fn = custom("remove")
    if fn then
        local ok, r = pcall(fn, user_id, item, amount)
        return ok and r == true
    end
    return F.tryGetItem(user_id, item, amount)
end

function Inventory.give(user_id, item, amount)
    local fn = custom("give")
    if fn then
        local ok, r = pcall(fn, user_id, item, amount)
        return ok and r ~= false
    end
    return F.giveItem(user_id, item, amount)
end

function Inventory.label(item)
    if F.available and cfg("Inventory").type ~= "custom" then return F.getItemName(item) end
    return item
end

---------------------------------------------------------------------------
-- Weapons
---------------------------------------------------------------------------
local Weapons = {}
I.Weapons = Weapons

local function weaponsCustom(name)
    local c = cfg("Weapons")
    if c.type == "custom" and type(c.custom) == "table" and type(c.custom[name]) == "function" then
        return c.custom[name]
    end
    return nil
end

local function wtype()
    local t = cfg("Weapons").type or "vrp"
    if t == "vrp" and not F.available then return "builtin" end
    return t
end

-- → { WEAPON_NAME = { ammo = n } }
function Weapons.get(source)
    local fn = weaponsCustom("get")
    if fn then
        local ok, w = pcall(fn, source)
        return ok and type(w) == "table" and w or {}
    end
    local weapons
    if wtype() == "vrp" then
        weapons = F.client("getWeapons", source)
    else
        weapons = Evora.clientRequest(source, "weapons:get")
    end
    local out = {}
    if type(weapons) == "table" then
        for name, data in pairs(weapons) do
            if type(name) == "string" then
                out[name:upper()] = { ammo = type(data) == "table" and tonumber(data.ammo) or 0 }
            end
        end
    end
    return out
end

function Weapons.clear(source)
    local fn = weaponsCustom("clear")
    if fn then pcall(fn, source) return end
    if wtype() == "vrp" then
        F.clientNoWait("giveWeapons", source, {}, true)
    else
        TriggerClientEvent("evora_police:weapons:clear", source)
    end
end

-- weapons: { WEAPON_NAME = { ammo = n } }
function Weapons.give(source, weapons)
    local fn = weaponsCustom("give")
    if fn then pcall(fn, source, weapons) return end
    if wtype() == "vrp" then
        F.clientNoWait("giveWeapons", source, weapons, false)
    else
        TriggerClientEvent("evora_police:weapons:give", source, weapons)
    end
end

---------------------------------------------------------------------------
-- Vehicle inventory (trunks)
--   vehicle = { plate = "ABC123", owner = user_id, model = "adder" }
---------------------------------------------------------------------------
local VehicleInventory = {}
I.VehicleInventory = VehicleInventory

local function chestKey(vehicle)
    local c = cfg("VehicleInventory")
    return Utils.format(c.key or "chest:u{owner}veh_{model}", {
        owner = vehicle.owner, model = vehicle.model or "", plate = vehicle.plate or "",
    })
end

local function readChest(key)
    local raw = F.getSData(key)
    if type(raw) == "table" then return raw end
    if type(raw) ~= "string" or raw == "" then return {} end
    local ok, data = pcall(json.decode, raw)
    if ok and type(data) == "table" then return data end
    return {}
end

function VehicleInventory.supported(vehicle)
    local c = cfg("VehicleInventory")
    if c.type == "custom" then return type(c.custom) == "table" and type(c.custom.getItems) == "function" end
    return F.available and vehicle and vehicle.owner and vehicle.model ~= nil and vehicle.model ~= ""
end

function VehicleInventory.getItems(vehicle)
    local c = cfg("VehicleInventory")
    if c.type == "custom" then
        local ok, items = pcall(c.custom.getItems, vehicle)
        return ok and type(items) == "table" and items or {}
    end
    if not VehicleInventory.supported(vehicle) then return {} end
    local list = {}
    for idname, entry in pairs(readChest(chestKey(vehicle))) do
        local amount = type(entry) == "table" and tonumber(entry.amount) or tonumber(entry) or 0
        if amount > 0 then
            list[#list + 1] = { item = idname, label = F.getItemName(idname), amount = amount }
        end
    end
    table.sort(list, function(a, b) return tostring(a.label) < tostring(b.label) end)
    return list
end

function VehicleInventory.remove(vehicle, item, amount)
    local c = cfg("VehicleInventory")
    if c.type == "custom" then
        if type(c.custom.remove) ~= "function" then return false end
        local ok, r = pcall(c.custom.remove, vehicle, item, amount)
        return ok and r == true
    end
    if not VehicleInventory.supported(vehicle) then return false end
    local key = chestKey(vehicle)
    local items = readChest(key)
    local entry = items[item]
    local current = type(entry) == "table" and tonumber(entry.amount) or tonumber(entry) or 0
    if current < amount then return false end
    if current - amount <= 0 then
        items[item] = nil
    elseif type(entry) == "table" then
        entry.amount = current - amount
    else
        items[item] = { amount = current - amount }
    end
    F.setSData(key, json.encode(items))
    return true
end
