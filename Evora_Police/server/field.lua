--[[
    Evora_Police — field options (خيارات الميدان)

    Every action: permission + duty + server-side proximity + optional F5/F6 confirmation
    (Config.Field.Actions[x].confirm) + optional "target must be cuffed".
]]

local Field = { last = {}, vehicleSessions = {} }
Evora.Field = Field

local DB, P, Gov, Logs, Officers, Confirm, Targets, RPC =
    Evora.DB, Evora.Players, Evora.Gov, Evora.Logs, Evora.Officers, Evora.Confirm, Evora.Targets, Evora.RPC
local I = Evora.Integrations

local ORDER = { "cuff", "seizeWeapons", "drag", "search", "vehicleSearch", "putInVehicle", "pullOutVehicle", "seizeContraband", "identity" }

local function actionCfg(name)
    return (Config.Field and Config.Field.Actions and Config.Field.Actions[name]) or {}
end

local function contrabandList()
    local list = {}
    for _, entry in ipairs(Config.Contraband or {}) do
        if type(entry) == "string" then
            list[#list + 1] = { item = entry }
        elseif type(entry) == "table" and entry.item then
            list[#list + 1] = { item = entry.item, label = entry.label }
        end
    end
    return list
end
Field.contrabandList = contrabandList

local function isContraband(item)
    for _, c in ipairs(contrabandList()) do
        if c.item == item then return true end
    end
    return false
end

-- Common gate for every field action. Returns officer id or nil (after notifying).
local function allowed(source, name)
    local user_id = P.getUserId(source)
    if not user_id then return nil end
    local a = actionCfg(name)
    if not Evora.feature("Field") or a.enabled == false then
        Evora.notify(source, "err_feature_disabled", nil, "error")
        return nil
    end
    local profile = Gov.getProfile(user_id, true)
    if not Gov.has(profile, a.permission or "field") then
        Evora.notify(source, "err_no_permission", nil, "error")
        return nil
    end
    if not Officers.dutyOk(user_id, "field") then
        Evora.notify(source, "err_not_on_duty", nil, "error")
        return nil
    end
    local now = GetGameTimer()
    if Field.last[user_id] and now - Field.last[user_id] < ((Config.Field and Config.Field.Cooldown) or 1500) then
        Evora.notify(source, "err_cooldown", nil, "error")
        return nil
    end
    Field.last[user_id] = now
    return user_id
end

-- Validates the target and runs the optional cuff requirement + confirmation.
local function prepareTarget(source, officerId, name, targetSrc, targetId)
    local ok, err = Targets.check(source, targetSrc, targetId)
    if not ok then Evora.notify(source, err, nil, "error") return false end
    if targetId == officerId then Evora.notify(source, "target_self", nil, "error") return false end
    local a = actionCfg(name)
    if a.requireCuffed and not I.Handcuff.isCuffed(targetSrc) then
        Evora.notify(source, "field_requires_cuffed", nil, "error")
        return false
    end
    if a.confirm then
        local responder = a.confirm == "self" and source or targetSrc
        Evora.notify(source, "confirm_waiting", { name = P.name(targetId) }, "info")
        local accepted, reason = Confirm.ask(responder, {
            title = L("field_" .. name),
            message = a.confirm == "self" and L("confirm_field_self", { action = L("field_" .. name), name = P.name(targetId), id = targetId })
                or L("confirm_field_target", { action = L("field_" .. name), officer = P.name(officerId), officer_id = officerId }),
            icon = name,
        })
        if not accepted then Evora.notify(source, Confirm.failMessage(reason, a.confirm == "self"), nil, "error") return false end
        -- The officer may have been demoted or clocked out during the wait.
        if not Gov.has(Gov.getProfile(officerId, true), a.permission or "field") then
            Evora.notify(source, "err_no_permission", nil, "error") return false
        end
        if not Officers.dutyOk(officerId, "field") then Evora.notify(source, "err_not_on_duty", nil, "error") return false end
        ok, err = Targets.check(source, targetSrc, targetId, Targets.radius() + 2.0)
        if not ok then Evora.notify(source, err, nil, "error") return false end
    end
    return true
end

local function playOfficerAnim(source, dict, anim, duration)
    TriggerClientEvent("evora_police:anim", source, dict, anim, duration or 1500)
end

---------------------------------------------------------------------------
-- Actions on a player
---------------------------------------------------------------------------
local handlers = {}

function handlers.cuff(source, officerId, targetSrc, targetId)
    local cuffed = I.Handcuff.toggle(targetSrc)
    if actionCfg("cuff").animation ~= false then playOfficerAnim(source, "mp_arresting", "a_uncuff", 2500) end
    Evora.notify(source, cuffed and "field_cuffed_officer" or "field_uncuffed_officer", { name = P.name(targetId) }, "success")
    Evora.notify(targetSrc, cuffed and "field_cuffed_target" or "field_uncuffed_target", nil, "info")
    Logs.add("field", cuffed and "cuff" or "uncuff", { actor = officerId, target = targetId })
end

function handlers.seizeWeapons(source, officerId, targetSrc, targetId)
    local weapons = I.Weapons.get(targetSrc)
    local names = {}
    for name, data in pairs(weapons) do names[#names + 1] = ("%s (%d)"):format(name, tonumber(data.ammo) or 0) end
    if #names == 0 then return Evora.notify(source, "field_no_weapons", nil, "info") end
    table.sort(names)
    I.Weapons.clear(targetSrc)
    if actionCfg("seizeWeapons").giveToOfficer then
        -- vRP keeps weapons client-side: only hand over well-formed names and a capped amount of ammo.
        local maxAmmo = actionCfg("seizeWeapons").maxAmmo or 250
        for name, data in pairs(weapons) do
            if name:match("^WEAPON_[%w_]+$") and #name <= 48 then
                I.Inventory.give(officerId, "wbody|" .. name, 1)
                local ammo = math.min(math.max(0, math.floor(tonumber(data.ammo) or 0)), maxAmmo)
                if ammo > 0 then I.Inventory.give(officerId, "wammo|" .. name, ammo) end
            end
        end
    end
    Evora.notify(source, "field_weapons_seized_officer", { count = #names }, "success")
    Evora.notify(targetSrc, "field_weapons_seized_target", nil, "warning")
    Logs.add("field", "seize_weapons", { actor = officerId, target = targetId, fields = { { L("log_field_weapons"), table.concat(names, "\n") } } })
end

function handlers.drag(source, officerId, targetSrc, targetId)
    I.Drag.toggle(source, targetSrc)
    Logs.add("field", "drag", { actor = officerId, target = targetId })
end

function handlers.search(source, officerId, targetSrc, targetId)
    local a = actionCfg("search")
    local items = I.Inventory.getItems(targetId, targetSrc)
    for _, it in ipairs(items) do it.contraband = isContraband(it.item) end
    local weapons = {}
    if a.showWeapons ~= false then
        for name, data in pairs(I.Weapons.get(targetSrc)) do weapons[#weapons + 1] = { name = name, ammo = tonumber(data.ammo) or 0 } end
        table.sort(weapons, function(x, y) return x.name < y.name end)
    end
    local money = a.showMoney ~= false and Evora.Framework.available and Evora.Framework.getMoney(targetId) or nil
    Evora.ui(source, "panel", {
        kind = "search", title = L("field_search"),
        data = { user_id = targetId, name = P.name(targetId), items = items, weapons = weapons, money = money },
    })
    Evora.notify(targetSrc, "field_searched_target", nil, "info")
    Logs.add("field", "search", { actor = officerId, target = targetId, fields = { { L("log_field_items"), #items, true }, { L("log_field_weapons"), #weapons, true } } })
end

function handlers.putInVehicle(source, officerId, targetSrc, targetId)
    I.Seats.putIn(targetSrc, source, actionCfg("putInVehicle").radius or 6.0)
    Logs.add("field", "put_in_vehicle", { actor = officerId, target = targetId })
end

function handlers.pullOutVehicle(source, officerId, targetSrc, targetId)
    I.Seats.pullOut(targetSrc, source)
    Logs.add("field", "pull_out_vehicle", { actor = officerId, target = targetId })
end

function handlers.seizeContraband(source, officerId, targetSrc, targetId)
    local seized = {}
    for _, c in ipairs(contrabandList()) do
        local amount = I.Inventory.getAmount(targetId, c.item)
        if amount > 0 and I.Inventory.remove(targetId, c.item, amount) then
            seized[#seized + 1] = { item = c.item, label = c.label or I.Inventory.label(c.item), amount = amount }
            if actionCfg("seizeContraband").giveToOfficer then I.Inventory.give(officerId, c.item, amount) end
        end
    end
    if #seized == 0 then return Evora.notify(source, "field_no_contraband", nil, "info") end
    local lines = {}
    for _, s in ipairs(seized) do lines[#lines + 1] = ("%s (%s) × %d"):format(s.label, s.item, s.amount) end
    Evora.notify(source, "field_contraband_seized_officer", { count = #seized }, "success")
    Evora.notify(targetSrc, "field_contraband_seized_target", nil, "warning")
    Logs.add("field", "seize_contraband", { actor = officerId, target = targetId, fields = { { L("log_field_items"), table.concat(lines, "\n") } } })
end

function handlers.identity(source, officerId, targetSrc, targetId)
    local profile = Gov.getProfile(targetId, true)
    local summary = Gov.summary(profile)
    TriggerClientEvent("evora_police:idcard:present", targetSrc)
    Evora.ui(source, "idcard", {
        name = P.name(targetId),
        user_id = targetId,
        avatar = I.ProfileImage.get(targetId),
        job = I.Job.get(targetId),
        rank = summary.military and summary.rank or nil,
        sector = summary.military and (summary.sectorLabel ~= "" and summary.sectorLabel or summary.ministryLabel) or nil,
        title = Config.IdCard and Config.IdCard.Title,
        country = Config.IdCard and Config.IdCard.Country,
        duration = Config.IdCard and Config.IdCard.Duration or 10,
    })
    Logs.add("field", "identity", { actor = officerId, target = targetId })
end

function Field.run(source, name, targetSrc, targetId)
    local officerId = allowed(source, name)
    if not officerId then return end
    if not prepareTarget(source, officerId, name, targetSrc, targetId) then return end
    local handler = handlers[name]
    if handler then handler(source, officerId, targetSrc, targetId) end
end

---------------------------------------------------------------------------
-- Vehicle search (تفتيش مركبة)
---------------------------------------------------------------------------
-- Nearest vehicle to the officer: { entity, netId, plate, model(hash) } using server-side entities.
function Field.nearestVehicle(source, radius)
    local origin = P.coords(source)
    if not origin then return nil end
    if P.oneSync() and GetAllVehicles then
        local best, bestDist
        for _, veh in ipairs(GetAllVehicles()) do
            if DoesEntityExist(veh) then
                local d = Utils.dist(origin, GetEntityCoords(veh))
                if d <= radius and (not bestDist or d < bestDist) then best, bestDist = veh, d end
            end
        end
        if not best then return nil end
        return {
            entity = best,
            netId = NetworkGetNetworkIdFromEntity(best),
            plate = Utils.normalizePlate(GetVehicleNumberPlateText(best) or ""),
            model = GetEntityModel(best),
            dist = bestDist,
        }
    end
    local v = Evora.clientRequest(source, "nearestVehicle", { radius = radius }, 4000)
    if type(v) ~= "table" or not v.plate then return nil end
    return { entity = nil, netId = tonumber(v.netId), plate = Utils.normalizePlate(v.plate), model = tonumber(v.model), dist = tonumber(v.dist) or radius }
end

function Field.vehicleSearch(source)
    local officerId = allowed(source, "vehicleSearch")
    if not officerId then return end
    local radius = actionCfg("vehicleSearch").radius or 5.0
    local veh = Field.nearestVehicle(source, radius)
    if not veh or veh.plate == "" then return Evora.notify(source, "field_no_vehicle", nil, "error") end
    local owner = I.Garage.findByPlate(veh.plate)
    if not owner then return Evora.notify(source, "field_vehicle_unowned", { plate = veh.plate }, "error") end
    local model = owner.model or I.Garage.modelFromHash(owner.owner, veh.model)
    local vehicle = { plate = veh.plate, owner = owner.owner, model = model }
    if not I.VehicleInventory.supported(vehicle) then return Evora.notify(source, "field_vehicle_inventory_unavailable", nil, "error") end
    local items = I.VehicleInventory.getItems(vehicle)
    local hasContraband = false
    for _, it in ipairs(items) do
        it.contraband = isContraband(it.item)
        if it.contraband then hasContraband = true end
    end
    local token = ("%d-%d"):format(officerId, GetGameTimer())
    Field.vehicleSessions[officerId] = { token = token, vehicle = vehicle, netId = veh.netId, expires = GetGameTimer() + 120000 }
    Evora.ui(source, "panel", {
        kind = "vehicle", title = L("field_vehicleSearch"),
        data = {
            plate = veh.plate, model = model or "", owner = { id = owner.owner, name = P.name(owner.owner) },
            items = items, token = token,
            canSeize = hasContraband and actionCfg("vehicleSearch").allowSeizeContraband ~= false,
        },
    })
    Logs.add("field", "vehicle_search", { actor = officerId, target = owner.owner, targetLabel = L("log_field_owner"),
        fields = { { L("field_plate"), veh.plate, true }, { L("field_model"), model or "-", true }, { L("log_field_items"), #items, true } } })
end

RPC.register("field:vehicleSeize", { feature = "Field", perm = "field", duty = "field", cooldown = 2000 }, function(ctx, data)
    local session = Field.vehicleSessions[ctx.user_id]
    Field.vehicleSessions[ctx.user_id] = nil
    if not session or session.token ~= data.token or GetGameTimer() > session.expires then return nil, L("err_confirm_expired") end
    if actionCfg("vehicleSearch").allowSeizeContraband == false then return nil, L("err_feature_disabled") end
    if not Gov.has(ctx.profile, actionCfg("vehicleSearch").permission or "field")
        or not Gov.has(ctx.profile, actionCfg("seizeContraband").permission or "field") then
        return nil, L("err_no_permission")
    end
    -- The officer must still be next to the same vehicle.
    local veh = Field.nearestVehicle(ctx.source, (actionCfg("vehicleSearch").radius or 5.0) + 2.0)
    if not veh or veh.plate ~= session.vehicle.plate then return nil, L("field_no_vehicle") end
    local seized = {}
    for _, it in ipairs(I.VehicleInventory.getItems(session.vehicle)) do
        if isContraband(it.item) and I.VehicleInventory.remove(session.vehicle, it.item, it.amount) then
            seized[#seized + 1] = ("%s (%s) × %d"):format(it.label, it.item, it.amount)
            if actionCfg("seizeContraband").giveToOfficer then I.Inventory.give(ctx.user_id, it.item, it.amount) end
        end
    end
    if #seized == 0 then return nil, L("field_no_contraband") end
    Logs.add("field", "seize_vehicle_contraband", {
        actor = ctx.user_id, target = session.vehicle.owner, targetLabel = L("log_field_owner"),
        fields = { { L("field_plate"), session.vehicle.plate, true }, { L("log_field_items"), table.concat(seized, "\n") } },
    })
    return { seized = #seized, items = I.VehicleInventory.getItems(session.vehicle) }
end)

---------------------------------------------------------------------------
-- Menu
---------------------------------------------------------------------------
function Field.menu(source, parent)
    local items = {}
    for _, name in ipairs(ORDER) do
        local a = actionCfg(name)
        if a.enabled ~= false then
            items[#items + 1] = {
                label = L("field_" .. name),
                description = L("field_desc_" .. name),
                action = function(src)
                    if name == "vehicleSearch" then return Field.vehicleSearch(src) end
                    if not allowed(src, name) then return end
                    Field.last[P.getUserId(src)] = nil -- the real action is rate limited after the pick
                    Targets.pick(src, L("field_" .. name), function(targetSrc, targetId)
                        Field.run(src, name, targetSrc, targetId)
                    end, function(s) return Field.menu(s, parent) end)
                end,
            }
        end
    end
    return { title = L("menu_field"), items = items, parent = parent }
end

Evora.on("playerDropped", function(user_id)
    Field.vehicleSessions[user_id] = nil
    Field.last[user_id] = nil
end)
