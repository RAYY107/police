--[[
    Evora_Police — Equipment (أخذ العتاد)

    Kits can be restricted with:
        sectors = { "Interior.PublicSecurity" }   sector ids from config/government.lua
        ranks   = { "ps_commander" }              groups from groups.lua
    Weapons are given through Config.Integrations.Weapons, items through Config.Integrations.Inventory.
]]

Config.Equipment = {
    Cooldown = 120,          -- seconds between two kits for the same officer
    ReturnEnabled = true,    -- "تسليم العتاد"
    ReturnMode = "kit",      -- "kit": removes only weapons handed out by the kits below | "all": removes every weapon

    Kits = {
        {
            id = "patrol",
            label = "عتاد الدورية",
            weapons = {
                { name = "WEAPON_COMBATPISTOL", ammo = 120 },
                { name = "WEAPON_STUNGUN", ammo = 0 },
                { name = "WEAPON_NIGHTSTICK", ammo = 0 },
                { name = "WEAPON_FLASHLIGHT", ammo = 0 },
            },
            armour = 100,
            items = {},
        },
        {
            id = "tactical",
            label = "العتاد التكتيكي",
            ranks = { "ps_commander", "ps_deputy", "interior_minister", "interior_deputy" },
            weapons = {
                { name = "WEAPON_CARBINERIFLE", ammo = 250 },
                { name = "WEAPON_PUMPSHOTGUN", ammo = 60 },
                { name = "WEAPON_COMBATPISTOL", ammo = 120 },
            },
            armour = 100,
            items = {},
        },
        {
            id = "traffic",
            label = "عتاد المرور",
            sectors = { "Interior.Traffic" },
            weapons = {
                { name = "WEAPON_PISTOL", ammo = 90 },
                { name = "WEAPON_FLASHLIGHT", ammo = 0 },
            },
            armour = 50,
            items = {},
        },
    },
}
