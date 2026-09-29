--[[
    Evora_Police — Uniforms (الملابس)

    components: [componentId] = { drawable, texture }
        1 mask · 3 arms · 4 legs · 5 bag · 6 shoes · 7 accessory · 8 undershirt · 9 vest · 10 decals · 11 torso
    props: [propId] = { drawable, texture }  (-1 removes the prop)
        0 hat · 1 glasses · 2 ears · 6 watch · 7 bracelet
    Restrict presets with sectors = { ... } and/or ranks = { ... } like equipment kits.
]]

Config.Uniforms = {
    AllowRestore = true, -- "الملابس الأصلية": puts back the clothes worn before the first uniform

    Presets = {
        {
            id = "ps_patrol",
            label = "زي الأمن العام",
            sectors = { "Interior.PublicSecurity" },
            Male = {
                components = { [3] = { 41, 0 }, [4] = { 25, 0 }, [6] = { 25, 0 }, [8] = { 58, 0 }, [10] = { 0, 0 }, [11] = { 55, 0 } },
                props = { [0] = { 46, 0 } },
            },
            Female = {
                components = { [3] = { 44, 0 }, [4] = { 34, 0 }, [6] = { 27, 0 }, [8] = { 35, 0 }, [10] = { 0, 0 }, [11] = { 48, 0 } },
                props = { [0] = { 45, 0 } },
            },
        },
        {
            id = "traffic",
            label = "زي المرور",
            sectors = { "Interior.Traffic" },
            Male = {
                components = { [3] = { 41, 0 }, [4] = { 25, 0 }, [6] = { 25, 0 }, [8] = { 59, 1 }, [10] = { 0, 0 }, [11] = { 55, 0 } },
                props = { [0] = { 46, 0 } },
            },
            Female = {
                components = { [3] = { 44, 0 }, [4] = { 34, 0 }, [6] = { 27, 0 }, [8] = { 36, 1 }, [10] = { 0, 0 }, [11] = { 48, 0 } },
                props = { [0] = { 45, 0 } },
            },
        },
        {
            id = "command",
            label = "زي القيادة",
            ranks = { "ps_commander", "traffic_commander", "interior_minister", "interior_deputy", "prime_minister", "prime_deputy" },
            Male = {
                components = { [3] = { 4, 0 }, [4] = { 28, 0 }, [6] = { 10, 0 }, [8] = { 31, 0 }, [10] = { 0, 0 }, [11] = { 4, 0 } },
                props = { [0] = { -1, 0 } },
            },
            Female = {
                components = { [3] = { 3, 0 }, [4] = { 6, 0 }, [6] = { 29, 0 }, [8] = { 38, 0 }, [10] = { 0, 0 }, [11] = { 7, 0 } },
                props = { [0] = { -1, 0 } },
            },
        },
    },
}
