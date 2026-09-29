--[[
    Evora_Police — Field options (خيارات الميدان) and contraband (الممنوعات)

    Per action:
        enabled        show / hide the action
        permission     permission required (config/permissions.lua)
        confirm        false | "target" | "self"  (F5 قبول / F6 رفض)
        requireCuffed  the target must be handcuffed
]]

Config.Field = {
    Actions = {
        cuff            = { enabled = true, permission = "field", confirm = false, requireCuffed = false, animation = true },
        seizeWeapons    = { enabled = true, permission = "field", confirm = false, requireCuffed = true, giveToOfficer = false },
        drag            = { enabled = true, permission = "field", confirm = false, requireCuffed = true },
        search          = { enabled = true, permission = "field", confirm = false, requireCuffed = false, showMoney = true, showWeapons = true },
        vehicleSearch   = { enabled = true, permission = "field", confirm = false, radius = 5.0, allowSeizeContraband = true },
        putInVehicle    = { enabled = true, permission = "field", confirm = false, requireCuffed = true, radius = 6.0 },
        pullOutVehicle  = { enabled = true, permission = "field", confirm = false, requireCuffed = false },
        seizeContraband = { enabled = true, permission = "field", confirm = false, requireCuffed = true, giveToOfficer = false },
        identity        = { enabled = true, permission = "field", confirm = "target" },
    },
    Cooldown = 1500,   -- ms between two field actions of the same officer
}

-- Items confiscated by "استيلاء على الممنوعات". Plain item ids, or { item = "id", label = "name" }.
Config.Contraband = {
    "weed",
    "cocaine",
    "meth",
    "dirty_money",
    "lockpick",
}
