--[[
    Evora_Police — Vehicle impound (حجز المركبات)

    The officer types the plate manually and must stand next to the vehicle.
    Owner lookup and garage status go through Config.Integrations.VehicleGarage /
    Config.Integrations.VehicleImpound (config/integrations.lua).
]]

Config.Impound = {
    PlateMaxLength = 8,
    VehicleRadius = 8.0,       -- officer ↔ vehicle maximum distance (metres)
    AllowReimpound = false,    -- allow impounding a plate that already has an active impound
    DeleteVehicle = true,      -- remove the vehicle entity from the world after impounding
    DefaultFee = 2500,
    PaymentMethod = "full",    -- "wallet" | "bank" | "full"
    AllowCustomReason = true,  -- officer may type a reason (uses DefaultFee)
    NotifyOwner = true,        -- tell an online owner right away
    NotifyOnLogin = true,      -- remind the owner of impounded vehicles when they join
    InquiryLimit = 50,

    Reasons = {
        { id = "parking",   label = "وقوف مخالف",            fee = 1500 },
        { id = "abandoned", label = "مركبة مهجورة",          fee = 1000 },
        { id = "crime",     label = "استخدام في جريمة",      fee = 7500 },
        { id = "license",   label = "قيادة بدون رخصة",       fee = 3000 },
        { id = "reckless",  label = "قيادة متهورة",          fee = 5000 },
    },

    -- Unlimited impound centres: owners pay the fee here.
    Locations = {
        {
            id = "central",
            label = "حجز العاصمة",
            coords = vector3(409.25, -1623.08, 29.29),
            radius = 3.0,
            blip = { enabled = true, sprite = 524, color = 1, scale = 0.8, label = "حجز المركبات" },
            marker = { enabled = true, type = 36, color = { 139, 92, 246, 190 }, scale = { 0.9, 0.9, 0.9 }, offsetZ = 0.6, rotate = true, drawDistance = 20.0 },
        },
        {
            id = "sandy",
            label = "حجز ساندي شورز",
            coords = vector3(1737.53, 3710.02, 34.14),
            radius = 3.0,
            blip = { enabled = true, sprite = 524, color = 1, scale = 0.7, label = "حجز المركبات" },
            marker = { enabled = true, type = 36, color = { 139, 92, 246, 190 }, scale = { 0.9, 0.9, 0.9 }, offsetZ = 0.6, rotate = true, drawDistance = 20.0 },
        },
        {
            id = "paleto",
            label = "حجز بليتو",
            coords = vector3(-223.60, 6243.37, 31.49),
            radius = 3.0,
            blip = { enabled = true, sprite = 524, color = 1, scale = 0.7, label = "حجز المركبات" },
            marker = { enabled = true, type = 36, color = { 139, 92, 246, 190 }, scale = { 0.9, 0.9, 0.9 }, offsetZ = 0.6, rotate = true, drawDistance = 20.0 },
        },
    },
}
