--[[
    Evora_Police — security equipment (أخذ العتاد) and uniforms (الملابس)
]]

local Equipment = { last = {}, civilian = {} }
Evora.Equipment = Equipment

local P, Gov, Logs, Officers = Evora.Players, Evora.Gov, Evora.Logs, Evora.Officers
local I = Evora.Integrations

-- Sector / rank restrictions shared by kits and uniform presets.
local function allowedFor(profile, entry)
    if type(entry.sectors) == "table" and #entry.sectors > 0 then
        local ok = false
        for _, g in ipairs(profile.grants) do
            for _, s in ipairs(entry.sectors) do
                if g.sector == s or (g.level ~= "sector" and Gov.coversSector(g, s)) then ok = true end
            end
        end
        if not ok then return false end
    end
    if type(entry.ranks) == "table" and #entry.ranks > 0 then
        local set = Utils.toSet(entry.ranks)
        local ok = false
        for _, g in ipairs(profile.grants) do
            if set[g.group] then ok = true end
        end
        if not ok then return false end
    end
    return true
end
Equipment.allowedFor = allowedFor

local function gate(source, perm, dutyKey)
    local user_id = P.getUserId(source)
    if not user_id then return nil end
    local profile = Gov.getProfile(user_id, true)
    if not Evora.feature("SecurityTools") or not Gov.has(profile, perm) then
        Evora.notify(source, "err_no_permission", nil, "error")
        return nil
    end
    if not Officers.dutyOk(user_id, dutyKey) then
        Evora.notify(source, "err_not_on_duty", nil, "error")
        return nil
    end
    return user_id, profile
end

function Equipment.takeKit(source, kitId)
    local user_id, profile = gate(source, "equipment", "equipment")
    if not user_id then return end
    local kit
    for _, k in ipairs((Config.Equipment and Config.Equipment.Kits) or {}) do
        if k.id == kitId then kit = k end
    end
    if not kit or not allowedFor(profile, kit) then return Evora.notify(source, "err_no_permission", nil, "error") end
    local now = Evora.now()
    local cooldown = (Config.Equipment and Config.Equipment.Cooldown) or 120
    if Equipment.last[user_id] and now - Equipment.last[user_id] < cooldown then
        return Evora.notify(source, "equipment_cooldown", { seconds = cooldown - (now - Equipment.last[user_id]) }, "error")
    end
    Equipment.last[user_id] = now
    local weapons = {}
    for _, w in ipairs(kit.weapons or {}) do weapons[w.name:upper()] = { ammo = tonumber(w.ammo) or 0 } end
    if next(weapons) then I.Weapons.give(source, weapons) end
    for _, it in ipairs(kit.items or {}) do I.Inventory.give(user_id, it.item, tonumber(it.amount) or 1) end
    if (tonumber(kit.armour) or 0) > 0 then TriggerClientEvent("evora_police:armour", source, tonumber(kit.armour)) end
    Evora.notify(source, "equipment_taken", { kit = kit.label }, "success")
    Logs.add("field", "equipment_take", { actor = user_id, fields = { { L("field_kit"), kit.label } } })
end

function Equipment.returnAll(source)
    local user_id = gate(source, "equipment", "equipment")
    if not user_id then return end
    I.Weapons.clear(source)
    TriggerClientEvent("evora_police:armour", source, 0)
    Evora.notify(source, "equipment_returned", nil, "info")
    Logs.add("field", "equipment_return", { actor = user_id })
end

function Equipment.kitsMenu(source, parent)
    local user_id, profile = gate(source, "equipment", "equipment")
    if not user_id then return nil end
    local items = {}
    for _, kit in ipairs((Config.Equipment and Config.Equipment.Kits) or {}) do
        if allowedFor(profile, kit) then
            local names = {}
            for _, w in ipairs(kit.weapons or {}) do names[#names + 1] = w.name:gsub("^WEAPON_", "") end
            items[#items + 1] = {
                label = kit.label,
                description = table.concat(names, " • "),
                action = function(src) Equipment.takeKit(src, kit.id) end,
            }
        end
    end
    if Config.Equipment and Config.Equipment.ReturnEnabled ~= false then
        items[#items + 1] = { label = L("equipment_return"), description = L("equipment_return_desc"), action = function(src) Equipment.returnAll(src) end }
    end
    return { title = L("menu_equipment"), items = items, parent = parent }
end

---------------------------------------------------------------------------
-- Uniforms
---------------------------------------------------------------------------
function Equipment.applyUniform(source, presetId)
    local user_id, profile = gate(source, "uniforms", "uniforms")
    if not user_id then return end
    local preset
    for _, p in ipairs((Config.Uniforms and Config.Uniforms.Presets) or {}) do
        if p.id == presetId then preset = p end
    end
    if not preset or not allowedFor(profile, preset) then return Evora.notify(source, "err_no_permission", nil, "error") end
    local previous = I.Clothing.applyPreset(source, preset, nil)
    if not previous then return Evora.notify(source, "clothing_unavailable", nil, "error") end
    if not Equipment.civilian[user_id] then Equipment.civilian[user_id] = previous end
    Evora.notify(source, "uniform_applied", { uniform = preset.label }, "success")
end

function Equipment.restoreClothes(source)
    local user_id = gate(source, "uniforms", "uniforms")
    if not user_id then return end
    local saved = Equipment.civilian[user_id]
    if not saved then return Evora.notify(source, "uniform_no_saved", nil, "error") end
    I.Clothing.set(source, saved)
    Equipment.civilian[user_id] = nil
    Evora.notify(source, "uniform_restored", nil, "success")
end

function Equipment.uniformsMenu(source, parent)
    local user_id, profile = gate(source, "uniforms", "uniforms")
    if not user_id then return nil end
    local items = {}
    for _, preset in ipairs((Config.Uniforms and Config.Uniforms.Presets) or {}) do
        if allowedFor(profile, preset) then
            items[#items + 1] = { label = preset.label, action = function(src) Equipment.applyUniform(src, preset.id) end }
        end
    end
    if Config.Uniforms and Config.Uniforms.AllowRestore then
        items[#items + 1] = { label = L("uniform_restore"), description = L("uniform_restore_desc"), action = function(src) Equipment.restoreClothes(src) end }
    end
    return { title = L("menu_uniforms"), items = items, parent = parent }
end

Evora.on("playerDropped", function(user_id)
    Equipment.civilian[user_id] = nil
end)
