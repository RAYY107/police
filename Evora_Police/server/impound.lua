--[[
    Evora_Police — vehicle impound (حجز المركبات)

    Flow: plate typed by the officer → the vehicle must be next to the officer (server-side
    entity check with OneSync) → owner from the garage adapter → reason / fee → F5/F6 → record.
    Active impounds are cached in memory so garage exports answer without database waits.
]]

local Impound = { cache = {} } -- [plate] = record (status impounded)
Evora.Impound = Impound

local DB, P, Gov, Logs, Officers, Confirm, RPC = Evora.DB, Evora.Players, Evora.Gov, Evora.Logs, Evora.Officers, Evora.Confirm, Evora.RPC
local I = Evora.Integrations

local function cfg() return Config.Impound or {} end

local function plateVariants(plate)
    plate = Utils.normalizePlate(plate)
    local list = { plate }
    local prefix = Utils.normalizePlate((Config.Integrations.VehicleGarage or {}).platePrefix or "")
    if prefix ~= "" then
        if plate:sub(1, #prefix) == prefix then
            list[#list + 1] = Utils.trim(plate:sub(#prefix + 1))
        else
            list[#list + 1] = prefix .. " " .. plate
        end
    end
    return list
end

function Impound.find(plate)
    for _, p in ipairs(plateVariants(plate)) do
        if Impound.cache[p] then return Impound.cache[p] end
    end
    return nil
end

function Impound.location(id)
    for _, loc in ipairs(cfg().Locations or {}) do
        if loc.id == id then return loc end
    end
    return nil
end

function Impound.nearestLocation(coords)
    local best, bestDist
    for _, loc in ipairs(cfg().Locations or {}) do
        local d = coords and Utils.dist(coords, loc.coords) or 0
        if not bestDist or d < bestDist then best, bestDist = loc, d end
    end
    return best
end

local function record(r)
    local loc = Impound.location(r.location_id)
    return {
        id = tonumber(r.id), plate = r.plate, model = r.model,
        owner = { id = tonumber(r.owner_id), name = r.owner_name },
        officer = { id = tonumber(r.officer_id), name = r.officer_name },
        location = loc and loc.label or r.location_id, locationId = r.location_id,
        reason = r.reason, fee = tonumber(r.fee), status = r.status,
        createdAt = tonumber(r.created_at), releasedAt = tonumber(r.released_at), releaseType = r.release_type,
    }
end

function Impound.load()
    Impound.cache = {}
    for _, r in ipairs(DB.query("SELECT * FROM evora_police_impounds WHERE status = 'impounded'")) do
        Impound.cache[r.plate] = r
    end
    Evora.debug("impound", "%d active impounds cached", Utils.count(Impound.cache))
end

local function gate(source, perm)
    local user_id = P.getUserId(source)
    if not user_id then return nil end
    local profile = Gov.getProfile(user_id, true)
    if not Evora.feature("Impound") or not Gov.has(profile, perm) then
        Evora.notify(source, "err_no_permission", nil, "error")
        return nil
    end
    if not Officers.dutyOk(user_id, perm == "impoundInquiry" and "inquiries" or "impound") then
        Evora.notify(source, "err_not_on_duty", nil, "error")
        return nil
    end
    return user_id
end

-- Finds a vehicle with this plate within `radius` of the officer (server-side when possible).
function Impound.vehicleNear(source, plate, radius)
    local origin = P.coords(source)
    if not origin then return nil end
    local variants = Utils.toSet(plateVariants(plate))
    if P.oneSync() and GetAllVehicles then
        for _, veh in ipairs(GetAllVehicles()) do
            if DoesEntityExist(veh) and variants[Utils.normalizePlate(GetVehicleNumberPlateText(veh) or "")] then
                local d = Utils.dist(origin, GetEntityCoords(veh))
                if d <= radius then
                    return { entity = veh, netId = NetworkGetNetworkIdFromEntity(veh), model = GetEntityModel(veh), dist = d }
                end
            end
        end
        return nil
    end
    local v = Evora.clientRequest(source, "vehicleByPlate", { plate = plate, radius = radius }, 4000)
    if type(v) ~= "table" or not v.netId then return nil end
    return { entity = nil, netId = tonumber(v.netId), model = tonumber(v.model), dist = tonumber(v.dist) or radius }
end

local function deleteVehicle(source, veh)
    if not cfg().DeleteVehicle or not veh then return end
    if veh.entity and DoesEntityExist(veh.entity) then
        DeleteEntity(veh.entity)
    elseif veh.netId then
        TriggerClientEvent("evora_police:vehicle:delete", source, veh.netId)
    end
end

---------------------------------------------------------------------------
-- Impounding
---------------------------------------------------------------------------
function Impound.execute(source, context, reasonLabel, fee)
    local officerId = gate(source, "impound")
    if not officerId then return end
    local officerCoords = P.coords(source)
    local loc = Impound.nearestLocation(officerCoords)
    if not loc then return Evora.notify(source, "impound_no_locations", nil, "error") end
    local ownerName = P.name(context.owner)
    local accepted, reason = Confirm.forAction("impound", source, P.getSource(context.owner), {
        title = L("confirm_impound_title"),
        message = L("confirm_impound_msg", { plate = context.plate }),
        details = {
            { L("field_plate"), context.plate },
            { L("field_owner"), ("%s | ID: %d"):format(ownerName, context.owner) },
            { L("field_model"), context.model ~= "" and context.model or "-" },
            { L("field_reason"), reasonLabel },
            { L("field_fee"), "$" .. Utils.money(fee) },
            { L("field_location"), loc.label },
        },
        icon = "impound",
    })
    if not accepted then return Evora.notify(source, Confirm.failMessage(reason, Confirm.mode("impound") == "self"), nil, "error") end

    officerId = gate(source, "impound")
    if not officerId then return end
    local veh = Impound.vehicleNear(source, context.plate, (cfg().VehicleRadius or 8.0) + 2.0)
    if not veh then return Evora.notify(source, "impound_vehicle_far", nil, "error") end
    if Impound.find(context.plate) and not cfg().AllowReimpound then return Evora.notify(source, "impound_already", nil, "error") end

    local now = Evora.now()
    local row = {
        plate = context.plate, model = context.model or "", owner_id = context.owner, owner_name = ownerName,
        officer_id = officerId, officer_name = P.name(officerId), location_id = loc.id, reason = reasonLabel,
        fee = fee, status = "impounded", created_at = now,
    }
    row.id = DB.insert(
        "INSERT INTO evora_police_impounds (plate, model, owner_id, owner_name, officer_id, officer_name, location_id, reason, fee, status, created_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 'impounded', ?)",
        { row.plate, row.model, row.owner_id, row.owner_name, row.officer_id, row.officer_name, row.location_id, row.reason, row.fee, now }
    )
    if not row.id then return Evora.notify(source, "err_internal", nil, "error") end
    Impound.cache[row.plate] = row
    Officers.increment(officerId, "impounds_issued", 1)
    I.ImpoundHooks.onImpound(row)
    deleteVehicle(source, veh)

    Evora.notify(source, "impound_done_officer", { plate = row.plate, location = loc.label }, "success")
    local ownerSrc = P.getSource(row.owner_id)
    if ownerSrc and cfg().NotifyOwner then
        Evora.notify(ownerSrc, "impound_owner_notice", { plate = row.plate, location = loc.label, fee = Utils.money(fee), reason = reasonLabel }, "warning", 12)
    end
    Logs.add("impound", "impound", {
        actor = officerId, target = row.owner_id, targetLabel = L("log_field_owner"),
        fields = {
            { L("field_plate"), row.plate, true }, { L("field_model"), row.model ~= "" and row.model or "-", true },
            { L("field_reason"), reasonLabel, true }, { L("field_fee"), "$" .. Utils.money(fee), true },
            { L("field_location"), loc.label, true }, { L("log_field_impound"), "#" .. row.id, true },
        },
    })
end

-- "حجز مركبة": plate → proximity → owner → reason menu.
function Impound.flow(source, parent)
    local officerId = gate(source, "impound")
    if not officerId then return end
    local values = I.Popup.input(source, L("impound_title"), {
        { key = "plate", label = L("field_plate"), type = "text", max = cfg().PlateMaxLength or 8 },
    })
    if not values then return Evora.notify(source, "action_cancelled", nil, "info") end
    local plate = Utils.normalizePlate(values.plate)
    if plate == "" then return Evora.notify(source, "impound_bad_plate", nil, "error") end
    local veh = Impound.vehicleNear(source, plate, cfg().VehicleRadius or 8.0)
    if not veh then return Evora.notify(source, "impound_vehicle_far", nil, "error") end
    local owner = I.Garage.findByPlate(plate)
    if not owner then return Evora.notify(source, "impound_no_owner", { plate = plate }, "error") end
    if Impound.find(plate) and not cfg().AllowReimpound then return Evora.notify(source, "impound_already", nil, "error") end
    local context = { plate = plate, owner = owner.owner, model = owner.model or I.Garage.modelFromHash(owner.owner, veh.model) or "" }

    local items = {}
    for _, r in ipairs(cfg().Reasons or {}) do
        items[#items + 1] = {
            label = ("%s — $%s"):format(r.label, Utils.money(r.fee or cfg().DefaultFee or 0)),
            action = function(src) Impound.execute(src, context, r.label, math.floor(tonumber(r.fee) or cfg().DefaultFee or 0)) end,
        }
    end
    if cfg().AllowCustomReason then
        items[#items + 1] = {
            label = L("impound_custom_reason"),
            description = L("impound_custom_reason_desc", { fee = Utils.money(cfg().DefaultFee or 0) }),
            action = function(src)
                local v = I.Popup.input(src, L("impound_custom_reason"), { { key = "reason", label = L("field_reason"), type = "text", max = 120 } })
                if not v then return Evora.notify(src, "action_cancelled", nil, "info") end
                Impound.execute(src, context, v.reason, math.floor(cfg().DefaultFee or 0))
            end,
        }
    end
    Evora.Menu.open(source, {
        title = L("impound_reason_title"),
        subtitle = ("%s • %s | ID: %d"):format(plate, P.name(owner.owner), owner.owner),
        items = items,
        parent = parent,
    })
end

---------------------------------------------------------------------------
-- Inquiry / release (police)
---------------------------------------------------------------------------
function Impound.listFor(owner_id)
    local list = {}
    for _, r in ipairs(DB.query("SELECT * FROM evora_police_impounds WHERE owner_id = ? ORDER BY (status = 'impounded') DESC, id DESC LIMIT " .. (cfg().InquiryLimit or 50), { owner_id })) do
        list[#list + 1] = record(r)
    end
    return list
end

function Impound.inquiryFlow(source)
    local officerId = gate(source, "impoundInquiry")
    if not officerId then return end
    local values = I.Popup.input(source, L("impound_inquiry_title"), { { key = "id", label = L("field_owner_id"), type = "number", min = 1 } })
    if not values then return Evora.notify(source, "action_cancelled", nil, "info") end
    if not P.exists(values.id) then return Evora.notify(source, "err_unknown_id", nil, "error") end
    Evora.ui(source, "panel", { kind = "impound", title = L("impound_inquiry_title"), data = {
        user_id = values.id, name = P.name(values.id), list = Impound.listFor(values.id),
    } })
    Logs.add("impound", "impound_inquiry", { actor = officerId, target = values.id })
end

function Impound.release(id, releaseType, byId)
    local r = DB.single("SELECT * FROM evora_police_impounds WHERE id = ? AND status = 'impounded'", { id })
    if not r then return nil end
    local changed = DB.execute(
        "UPDATE evora_police_impounds SET status = 'released', released_at = ?, release_type = ?, released_by_id = ?, released_by_name = ? WHERE id = ? AND status = 'impounded'",
        { Evora.now(), releaseType, byId or 0, (byId and byId > 0) and P.name(byId) or "", id }
    )
    if changed < 1 then return nil end
    Impound.cache[r.plate] = nil
    I.ImpoundHooks.onRelease(r)
    return r
end

function Impound.releaseFlow(source, parent)
    local officerId = gate(source, "impoundRelease")
    if not officerId then return end
    local values = I.Popup.input(source, L("impound_release_title"), { { key = "id", label = L("field_owner_id"), type = "number", min = 1 } })
    if not values then return Evora.notify(source, "action_cancelled", nil, "info") end
    local items = {}
    for _, rec in ipairs(Impound.listFor(values.id)) do
        if rec.status == "impounded" then
            items[#items + 1] = {
                label = ("%s — %s"):format(rec.plate, rec.model ~= "" and rec.model or "-"),
                description = ("%s • $%s • %s"):format(rec.reason, Utils.money(rec.fee), rec.location),
                action = function(src)
                    local accepted, reason = Confirm.forAction("impoundRelease", src, P.getSource(values.id), {
                        title = L("confirm_impound_release_title"),
                        message = L("confirm_impound_release_msg", { plate = rec.plate }),
                        details = { { L("field_owner"), ("%s | ID: %d"):format(rec.owner.name, rec.owner.id) }, { L("field_reason"), rec.reason } },
                        icon = "impound",
                    })
                    if not accepted then return Evora.notify(src, Confirm.failMessage(reason, true), nil, "error") end
                    local byId = gate(src, "impoundRelease")
                    if not byId then return end
                    local r = Impound.release(rec.id, "police", byId)
                    if not r then return Evora.notify(src, "impound_not_found", nil, "error") end
                    Evora.notify(src, "impound_released_officer", { plate = r.plate }, "success")
                    local ownerSrc = P.getSource(tonumber(r.owner_id))
                    if ownerSrc then Evora.notify(ownerSrc, "impound_released_owner", { plate = r.plate }, "success") end
                    Logs.add("impound", "impound_release", { actor = byId, target = tonumber(r.owner_id), targetLabel = L("log_field_owner"),
                        fields = { { L("field_plate"), r.plate, true }, { L("log_field_impound"), "#" .. r.id, true } } })
                end,
            }
        end
    end
    if #items == 0 then return Evora.notify(source, "impound_none_for_owner", nil, "info") end
    Evora.Menu.open(source, { title = L("impound_release_title"), subtitle = ("%s | ID: %d"):format(P.name(values.id), values.id), items = items, parent = parent })
end

function Impound.menu(source, parent)
    local user_id = P.getUserId(source)
    local profile = Gov.getProfile(user_id, true)
    local items = {}
    if Gov.has(profile, "impound") then
        items[#items + 1] = { label = L("impound_action"), description = L("impound_action_desc"), action = function(src) Impound.flow(src, function(s) return Impound.menu(s, parent) end) end }
    end
    if Gov.has(profile, "impoundInquiry") then
        items[#items + 1] = { label = L("impound_inquiry_title"), description = L("impound_inquiry_desc"), action = function(src) Impound.inquiryFlow(src) end }
    end
    if Gov.has(profile, "impoundRelease") then
        items[#items + 1] = { label = L("impound_release_title"), description = L("impound_release_desc"), action = function(src) Impound.releaseFlow(src, function(s) return Impound.menu(s, parent) end) end }
    end
    return { title = L("menu_impound"), items = items, parent = parent }
end

---------------------------------------------------------------------------
-- Owners: payment at impound centres
---------------------------------------------------------------------------
function Impound.nearCentre(source)
    local coords = P.coords(source)
    if not coords then return nil end
    for _, loc in ipairs(cfg().Locations or {}) do
        if Utils.dist(coords, loc.coords) <= (loc.radius or 3.0) + 2.0 then return loc end
    end
    return nil
end

function Impound.ownerView(user_id)
    local list = {}
    for _, rec in ipairs(Impound.listFor(user_id)) do
        if rec.status == "impounded" then list[#list + 1] = rec end
    end
    return { list = list }
end

RPC.register("impound:pay", { feature = "Impound", cooldown = 2000 }, function(ctx, data)
    local loc = Impound.nearCentre(ctx.source)
    if not loc then return nil, L("impound_centre_far") end
    local id = RPC.int(data.id, 1)
    local r = id and DB.single("SELECT * FROM evora_police_impounds WHERE id = ? AND owner_id = ? AND status = 'impounded'", { id, ctx.user_id })
    if not r then return nil, L("impound_not_found") end
    local fee = tonumber(r.fee) or 0
    if not I.Money.pay(ctx.user_id, fee, cfg().PaymentMethod) then return nil, L("impound_no_money", { fee = Utils.money(fee) }) end
    if not Impound.release(id, "paid", ctx.user_id) then
        I.Money.give(ctx.user_id, fee) -- refund: somebody released it meanwhile
        return nil, L("impound_not_found")
    end
    Evora.notify(ctx.source, "impound_paid", { plate = r.plate, fee = Utils.money(fee) }, "success", 10)
    Logs.add("impound", "impound_paid", { actor = ctx.user_id, fields = {
        { L("field_plate"), r.plate, true }, { L("field_fee"), "$" .. Utils.money(fee), true }, { L("field_location"), loc.label, true },
    } })
    return Impound.ownerView(ctx.user_id)
end)

Evora.on("playerReady", function(user_id, source)
    if not cfg().NotifyOnLogin then return end
    local count = 0
    for _, r in pairs(Impound.cache) do
        if tonumber(r.owner_id) == user_id then count = count + 1 end
    end
    if count > 0 then Evora.notify(source, "impound_login_notice", { count = count }, "warning", 12) end
end)

---------------------------------------------------------------------------
-- Garage exports (the existing garage calls these)
---------------------------------------------------------------------------
exports("IsVehicleImpounded", function(plate)
    return Impound.find(plate or "") ~= nil
end)

-- ownerId + plate or model. Returns nil or { impounded, plate, location, fee, reason, message }
exports("GetImpoundStatus", function(ownerId, plateOrModel)
    ownerId = tonumber(ownerId)
    local needle = type(plateOrModel) == "string" and plateOrModel or ""
    local variants = Utils.toSet(plateVariants(needle))
    for plate, r in pairs(Impound.cache) do
        if tonumber(r.owner_id) == ownerId and (variants[plate] or (r.model ~= "" and r.model:lower() == needle:lower())) then
            local loc = Impound.location(r.location_id)
            return {
                impounded = true, plate = plate, location = loc and loc.label or r.location_id,
                fee = tonumber(r.fee), reason = r.reason, message = L("impound_garage_message"),
            }
        end
    end
    return nil
end)

exports("GetImpoundedVehicles", function(ownerId)
    ownerId = tonumber(ownerId)
    local list = {}
    for plate, r in pairs(Impound.cache) do
        if tonumber(r.owner_id) == ownerId then
            list[#list + 1] = { plate = plate, model = r.model, fee = tonumber(r.fee), reason = r.reason, location = r.location_id }
        end
    end
    return list
end)

RPC.register("impound:open", { feature = "Impound", cooldown = 1000 }, function(ctx)
    local loc = Impound.nearCentre(ctx.source)
    if not loc then return nil, L("impound_centre_far") end
    local view = Impound.ownerView(ctx.user_id)
    view.location = loc.label
    return view
end)
