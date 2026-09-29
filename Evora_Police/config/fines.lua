--[[
    Evora_Police — Fines (المخالفات)

    Each fine: id (unique inside its category), label, amount, description, enabled.
    A fine is only recorded after the target accepts it with F5 (see Config.Confirm).
    Unpaid fines are paid at a payment point below (or charged immediately with AutoCharge).
]]

Config.Fines = {
    PaymentMethod = "full",   -- "wallet" | "bank" | "full" (wallet first, then bank)
    AutoCharge = false,       -- try to charge the fine as soon as it is accepted
    ConfirmTimeout = 30,      -- seconds the target has to answer
    Cooldown = 5,             -- seconds between two fines issued by the same officer
    InquiryLimit = 50,        -- max fines returned by استعلام عن مخالفات

    Categories = {
        {
            id = "criminal",
            label = "مخالفات جنائية",
            enabled = true,
            fines = {
                { id = "theft", label = "سرقة", amount = 5000, description = "سرقة ممتلكات عامة أو خاصة", enabled = true },
                { id = "assault", label = "اعتداء", amount = 7500, description = "الاعتداء الجسدي على مواطن", enabled = true },
                { id = "weapon", label = "حيازة سلاح بدون ترخيص", amount = 10000, description = "حمل سلاح غير مرخص", enabled = true },
                { id = "drugs", label = "حيازة ممنوعات", amount = 8000, description = "حيازة مواد ممنوعة", enabled = true },
                { id = "resisting", label = "مقاومة رجال الأمن", amount = 6000, description = "عدم الامتثال لأوامر رجال الأمن", enabled = true },
            },
        },
        {
            id = "traffic",
            label = "مخالفات مرورية",
            enabled = true,
            fines = {
                { id = "speeding", label = "تجاوز السرعة", amount = 1500, description = "تجاوز السرعة المحددة", enabled = true },
                { id = "red_light", label = "قطع الإشارة", amount = 3000, description = "تجاوز الإشارة الحمراء", enabled = true },
                { id = "reckless", label = "قيادة متهورة", amount = 2500, description = "القيادة بطريقة تعرض الآخرين للخطر", enabled = true },
                { id = "no_license", label = "القيادة بدون رخصة", amount = 2000, description = "قيادة مركبة بدون رخصة سارية", enabled = true },
                { id = "parking", label = "وقوف خاطئ", amount = 500, description = "الوقوف في مكان ممنوع", enabled = true },
            },
        },
        {
            id = "general",
            label = "مخالفات عامة",
            enabled = true,
            fines = {
                { id = "disturbance", label = "إزعاج عام", amount = 800, description = "إثارة الإزعاج في الأماكن العامة", enabled = true },
                { id = "insult", label = "السب والشتم", amount = 1000, description = "التلفظ بألفاظ خادشة", enabled = true },
                { id = "littering", label = "رمي النفايات", amount = 300, description = "رمي النفايات في الطريق العام", enabled = true },
            },
        },
    },

    -- Payment points (red arrow marker + optional blip)
    PaymentPoints = {
        {
            id = "mrpd",
            label = "سداد المخالفات",
            coords = vector3(441.24, -978.93, 30.69),
            radius = 1.5,
            marker = {
                enabled = true,
                type = 2,                   -- chevron, flipped to point down (red arrow)
                color = { 220, 38, 38, 210 },
                scale = { 0.35, 0.35, 0.35 },
                rotation = { 0.0, 180.0, 0.0 },
                offsetZ = 0.35,
                bob = true,
                rotate = true,
                drawDistance = 15.0,
            },
            blip = { enabled = true, sprite = 525, color = 1, scale = 0.8, label = "سداد المخالفات" },
        },
    },
}
