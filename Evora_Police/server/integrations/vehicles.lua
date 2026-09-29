--[[
    Evora_Police — garage lookup, garage impound hooks and vehicle seats.
    Evora never replaces the garage: it only reads owners and notifies the garage.
]]

local I = Evora.Integrations
local cfg = I.cfg
local F = Evora.Framework

---------------------------------------------------------------------------
-- Garage (owner by plate)
---------------------------------------------------------------------------
local Garage = {}
I.Garage = Garage

local function stripPrefix(plate)
    local prefix = Utils.normalizePlate(cfg("VehicleGarage").platePrefix or "")
    if prefix ~= "" and plate:sub(1, #prefix) == prefix then
        return Utils.trim(plate:sub(#prefix + 1))
    end
    return plate
end

-- → { owner = user_id, model = "adder" | nil } | nil
function Garage.findByPlate(plate)
    plate = Utils.normalizePlate(plate)
    if plate == "" then return nil end
    local c = cfg("VehicleGarage")
    local t = c.type or "sql"
    local result
    if t == "custom" and type(c.custom) == "function" then
        local ok, r = pcall(c.custom, plate)
        result = ok and r or nil
    elseif t == "export" and type(c.export) == "table" and I.resourceUp(c.export.resource) then
        local res = exports[c.export.resource]
        local ok, r = pcall(function() return res[c.export.fn](res, plate) end)
        result = ok and r or nil
    elseif t == "sql" and type(c.sql) == "table" and type(c.sql.ownerByPlate) == "string" then
        local candidates = { stripPrefix(plate) }
        if candidates[1] ~= plate then candidates[2] = plate end
        for _, candidate in ipairs(candidates) do
            local row = Evora.DB.single(c.sql.ownerByPlate, { candidate })
            if row then
                result = { owner = tonumber(row.user_id or row.owner or row.owner_id), model = row.model or row.vehicle }
                break
            end
        end
    end
    if type(result) ~= "table" then return nil end
    local owner = tonumber(result.owner or result.user_id)
    if not owner then return nil end
    return { owner = owner, model = type(result.model) == "string" and result.model or nil }
end

function Garage.ownerVehicles(owner)
    local c = cfg("VehicleGarage")
    if (c.type or "sql") ~= "sql" or type(c.sql) ~= "table" or type(c.sql.ownerVehicles) ~= "string" then return {} end
    local list = {}
    for _, row in ipairs(Evora.DB.query(c.sql.ownerVehicles, { owner })) do
        local model = row.model or row.vehicle
        if type(model) == "string" then list[#list + 1] = model end
    end
    return list
end

-- Finds the spawn name of an owned vehicle from its model hash.
function Garage.modelFromHash(owner, hash)
    if not hash then return nil end
    for _, model in ipairs(Garage.ownerVehicles(owner)) do
        if GetHashKey(model) == hash then return model end
    end
    return nil
end

---------------------------------------------------------------------------
-- Impound hooks (tell the garage a vehicle is impounded / released)
---------------------------------------------------------------------------
local ImpoundHooks = {}
I.ImpoundHooks = ImpoundHooks

local function hook(kind, record)
    local c = cfg("VehicleImpound")
    local t = c.type or "evora"
    if t == "sql" and type(c.sql) == "table" and type(c.sql[kind]) == "string" and c.sql[kind] ~= "" then
        local sql, params = Evora.DB.named(c.sql[kind], {
            owner = record.owner_id, model = record.model or "", plate = record.plate, id = record.id,
        })
        Evora.DB.execute(sql, params)
    elseif t == "custom" and type(c.custom) == "table" and type(c.custom[kind]) == "function" then
        local ok, err = pcall(c.custom[kind], record)
        if not ok then Evora.debug("impound", "VehicleImpound.%s: %s", kind, tostring(err)) end
    end
end

function ImpoundHooks.onImpound(record) hook("onImpound", record) end
function ImpoundHooks.onRelease(record) hook("onRelease", record) end

---------------------------------------------------------------------------
-- Seats (put in / pull out)
---------------------------------------------------------------------------
local Seats = {}
I.Seats = Seats

local function seatsType()
    local t = cfg("Seats").type or "vrp"
    if t == "vrp" and not F.available then return "builtin" end
    return t
end

function Seats.putIn(target, officer, radius)
    local c = cfg("Seats")
    local t = seatsType()
    if t == "custom" and type(c.custom) == "table" and type(c.custom.putIn) == "function" then
        pcall(c.custom.putIn, target, officer)
    elseif t == "vrp" then
        F.clientNoWait("putInNearestVehicleAsPassenger", target, radius or 6.0)
    else
        TriggerClientEvent("evora_police:seat:putIn", target, radius or 6.0)
    end
end

function Seats.pullOut(target, officer)
    local c = cfg("Seats")
    local t = seatsType()
    if t == "custom" and type(c.custom) == "table" and type(c.custom.pullOut) == "function" then
        pcall(c.custom.pullOut, target, officer)
    elseif t == "vrp" then
        F.clientNoWait("ejectVehicle", target)
    else
        TriggerClientEvent("evora_police:seat:pullOut", target)
    end
end
