--[[
    Evora_Police — Jail (السجن)

    The remaining time is authoritative on the server; the on-screen timer only mirrors it.
    Every sentence requires the target's confirmation (F5 قبول / F6 رفض).
]]

Config.Jail = {
    Name = "السجن المركزي",

    Entry = vector3(1641.55, 2570.48, 45.56),  -- where prisoners are placed
    EntryHeading = 90.0,
    Exit = vector3(1847.91, 2585.95, 45.67),   -- where released prisoners are placed
    ExitHeading = 270.0,

    Center = vector3(1690.0, 2570.0, 45.56),   -- centre of the jail perimeter
    Radius = 150.0,                            -- perimeter radius (metres)
    ReturnLocation = nil,                      -- where escapees are returned (nil = Entry)

    CountOfflineTime = false,   -- false: time only runs while the prisoner is connected
    MinMinutes = 1,
    MaxMinutes = 300,
    ConfirmTimeout = 30,
    PersistInterval = 30,       -- seconds between database saves of the remaining time

    Reasons = {
        { id = "robbery",   label = "سرقة",               duration = 30, description = "سرقة ممتلكات عامة أو خاصة" },
        { id = "assault",   label = "اعتداء",             duration = 20, description = "الاعتداء على مواطن" },
        { id = "murder",    label = "قتل",                duration = 60, description = "القتل العمد" },
        { id = "drugs",     label = "تجارة ممنوعات",      duration = 45, description = "ترويج أو تجارة المواد الممنوعة" },
        { id = "weapons",   label = "حيازة أسلحة",        duration = 25, description = "حيازة أسلحة غير مرخصة" },
        { id = "resisting", label = "مقاومة رجال الأمن",  duration = 15, description = "مقاومة أو الهروب من رجال الأمن" },
    },

    -- Every prisoner is restrained. Already cuffed players stay cuffed.
    Handcuff = {
        Enabled = true,
        RemoveOnRelease = true,   -- uncuff when the sentence ends
        Enforce = true,           -- re-cuff prisoners who get uncuffed while jailed
        EnforceInterval = 15,     -- seconds
    },

    -- Jail clothing. Original clothing is saved in the database before it is replaced
    -- and restored on release, including after resource or server restarts.
    -- components: [componentId] = { drawable, texture } | props: [propId] = { drawable, texture } (-1 removes)
    Clothing = {
        Enabled = true,
        Male = {
            components = { [3] = { 0, 0 }, [4] = { 3, 7 }, [6] = { 12, 12 }, [8] = { 15, 0 }, [11] = { 146, 0 } },
            props = { [0] = { -1, 0 } },
        },
        Female = {
            components = { [3] = { 2, 0 }, [4] = { 3, 15 }, [6] = { 66, 5 }, [8] = { 3, 0 }, [11] = { 38, 3 } },
            props = { [0] = { -1, 0 } },
        },
    },

    -- Only players that are actually marked as jailed are ever affected.
    Escape = {
        Enabled = true,
        AddMinutes = 5,           -- added to the sentence on every escape attempt (0 = none)
        MaxAddedMinutes = 60,     -- cap of time added by escapes for one sentence
        CheckInterval = 2,        -- seconds
        Message = "وين رايح يا عسل؟\nإذا حاولت تهرب بتزيد المدة.",
    },

    Hud = {
        Enabled = true,
    },

    -- Jail tasks (time reduction). Rewards are validated on the server: the prisoner must be
    -- inside the task radius for the whole duration, once per cooldown.
    Tasks = {
        Enabled = true,
        MaxReductionPercent = 50, -- max share of the original sentence tasks can remove
        MinRemaining = 60,        -- tasks never bring the sentence below this (seconds)

        Types = {
            clean  = { label = "تنظيف",  scenario = "WORLD_HUMAN_JANITOR" },
            repair = { label = "إصلاح",  dict = "mini@repair", anim = "fixing_a_ped" },
            weld   = { label = "لحام",   scenario = "WORLD_HUMAN_WELDING" },
            garden = { label = "زراعة",  scenario = "WORLD_HUMAN_GARDENER_PLANT" },
        },

        -- Skill checks shown while the task runs
        Difficulties = {
            easy   = { checks = 1, speed = 1.0, zone = 0.24 },
            medium = { checks = 2, speed = 1.35, zone = 0.17 },
            hard   = { checks = 3, speed = 1.7, zone = 0.12 },
        },

        List = {
            { id = "yard_clean_1", label = "تنظيف الساحة",   coords = vector3(1625.20, 2568.90, 45.56), radius = 2.0, type = "clean",  difficulty = "easy",   duration = 20, reduction = 60,  cooldown = 120 },
            { id = "yard_clean_2", label = "تنظيف الممر",    coords = vector3(1650.30, 2545.20, 45.56), radius = 2.0, type = "clean",  difficulty = "easy",   duration = 20, reduction = 60,  cooldown = 120 },
            { id = "generator",    label = "إصلاح المولد",   coords = vector3(1662.00, 2590.40, 45.56), radius = 2.0, type = "repair", difficulty = "medium", duration = 30, reduction = 120, cooldown = 240 },
            { id = "fence_weld",   label = "لحام السياج",    coords = vector3(1610.40, 2585.10, 45.56), radius = 2.0, type = "weld",   difficulty = "hard",   duration = 40, reduction = 180, cooldown = 360 },
            { id = "garden",       label = "زراعة الحديقة",  coords = vector3(1637.80, 2596.70, 45.56), radius = 2.0, type = "garden", difficulty = "easy",   duration = 25, reduction = 75,  cooldown = 150 },
        },

        Marker = { type = 21, color = { 139, 92, 246, 170 }, scale = { 0.45, 0.45, 0.45 }, drawDistance = 20.0 },
        Blip = { enabled = true, sprite = 566, color = 27, scale = 0.6 },
    },
}
