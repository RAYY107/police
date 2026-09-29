--[[
    Evora_Police — Integrations (Universal vRP adapters)

    Evora_Police never replaces your server systems. Each block below selects how Evora talks
    to an existing resource. Every integration has a "custom" type that accepts plain Lua
    functions, so any server can be connected without touching Evora_Police code.

    Server-side functions (custom = ...) run on the server. Functions named `format` run on
    the side that performs the call. If an integration is unavailable the console prints
    "[Evora_Police] <name> integration unavailable." and the feature degrades gracefully.
]]

Config.Integrations = {

    -------------------------------------------------------------------------
    -- Builder Menu: "الشرطة" and "إبلاغ عن مجرم" are added to the existing main menu.
    -------------------------------------------------------------------------
    BuilderMenu = {
        type = "vrp",                  -- "vrp" (vRP.registerMenuBuilder) | "builtin" (Evora NUI menu)
        menu = "main",                 -- vRP menu builder name to extend
        headerColor = "rgba(124, 58, 237, 0.80)",
        ordering = "invisible",        -- vRP sorts menu entries alphabetically:
                                       -- "invisible" keeps Evora's order with zero-width prefixes,
                                       -- "numbers" prefixes "1. 2. ...", "none" lets vRP sort.
        builtin = { command = "evora", key = "F7" }, -- used by type "builtin"
    },

    -------------------------------------------------------------------------
    -- Notifications
    -------------------------------------------------------------------------
    Notify = {
        type = "vrp",                  -- "vrp" | "event" | "client_export" | "builtin" | "custom"
        -- "event": TriggerClientEvent(event, source, table.unpack(format(...)))
        event = "mythic_notify:client:SendAlert",
        -- "client_export": exports[resource]:fn(table.unpack(format(...))) on the client
        resource = "mythic_notify",
        fn = "SendAlert",
        -- kind: "success" | "error" | "info" | "warning", duration in seconds
        format = function(message, kind, duration)
            return { { type = kind, text = message, length = duration * 1000 } }
        end,
        custom = function(source, message, kind, duration) end,
    },

    -------------------------------------------------------------------------
    -- Popups / input
    -------------------------------------------------------------------------
    Popup = {
        type = "vrp",                  -- "vrp" (vRP.prompt, one field at a time) | "builtin" | "custom"
        timeout = 120,                 -- seconds
        -- custom: must block (it runs in a thread) and return { [field.key] = "value" } or nil
        custom = function(source, title, fields) return nil end,
    },

    -------------------------------------------------------------------------
    -- Radio: the military code (الكود العسكري) is pushed to your existing radio.
    -------------------------------------------------------------------------
    Radio = {
        type = "none",                 -- "none" | "statebag" | "event" | "client_export" | "custom"
        stateKey = "callsign",         -- "statebag": Player(source).state[stateKey] = code
        event = "radio:setCallsign",   -- "event"
        eventSide = "client",          -- "client" → TriggerClientEvent(event, source, ...) | "server" → TriggerEvent
        resource = "",                 -- "client_export"
        fn = "",
        format = function(code, officer) return { code } end,
        custom = function(source, code, officer) end,
        -- Optional: called when the officer clocks in / out
        onDutyChange = nil,            -- function(source, onDuty, officer) end
    },

    -------------------------------------------------------------------------
    -- Player inventory (search, contraband, equipment items)
    -------------------------------------------------------------------------
    Inventory = {
        type = "vrp",                  -- "vrp" | "custom"
        custom = {
            getItems = function(user_id, source) return {} end,            -- { { item = "id", label = "name", amount = 1 } }
            getAmount = function(user_id, item) return 0 end,
            remove = function(user_id, item, amount) return false end,
            give = function(user_id, item, amount) return false end,
        },
    },

    -------------------------------------------------------------------------
    -- Weapons (seizure, equipment)
    -------------------------------------------------------------------------
    Weapons = {
        type = "vrp",                  -- "vrp" (getWeapons / giveWeapons) | "builtin" (natives) | "custom"
        custom = {
            get = function(source) return {} end,                          -- { WEAPON_PISTOL = { ammo = 50 } }
            clear = function(source) end,
            give = function(source, weapons) end,
        },
    },

    -------------------------------------------------------------------------
    -- Vehicle inventory (تفتيش مركبة)
    -------------------------------------------------------------------------
    VehicleInventory = {
        type = "vrp_chest",            -- "vrp_chest" | "custom"
        key = "chest:u{owner}veh_{model}", -- vRP server data key of vehicle trunks
        custom = {
            getItems = function(vehicle) return {} end,    -- vehicle = { plate, owner, model }
            remove = function(vehicle, item, amount) return false end,
        },
    },

    -------------------------------------------------------------------------
    -- Vehicle garage (owner lookup by plate). Evora never replaces your garage.
    -------------------------------------------------------------------------
    VehicleGarage = {
        type = "sql",                  -- "sql" | "export" | "custom"
        platePrefix = "P ",            -- removed before lookups (vRP 0.5 garages spawn "P " .. registration)
        sql = {
            -- Must return user_id (and optionally model) for a plate.
            ownerByPlate = "SELECT user_id FROM vrp_user_identities WHERE registration = ?",
            -- Optional: vehicles of an owner, used to name the impounded model.
            ownerVehicles = "SELECT vehicle AS model FROM vrp_user_vehicles WHERE user_id = ?",
            -- Garages that store a plate per vehicle:
            -- ownerByPlate = "SELECT user_id, vehicle AS model FROM vrp_user_vehicles WHERE vehicle_plate = ?",
        },
        export = { resource = "", fn = "" }, -- exports[resource]:fn(plate) → { owner = user_id, model = "adder" }
        custom = function(plate) return nil end, -- → { owner = user_id, model = "adder" } | nil
    },

    -------------------------------------------------------------------------
    -- Vehicle impound status inside your garage
    -------------------------------------------------------------------------
    VehicleImpound = {
        type = "evora",                -- "evora" (garage calls Evora exports) | "sql" | "custom"
        -- "sql" hooks. Placeholders: @owner @model @plate @id
        sql = {
            onImpound = "UPDATE vrp_user_vehicles SET impounded = 1 WHERE user_id = @owner AND vehicle = @model",
            onRelease = "UPDATE vrp_user_vehicles SET impounded = 0 WHERE user_id = @owner AND vehicle = @model",
        },
        custom = {
            onImpound = function(record) end,
            onRelease = function(record) end,
        },
    },

    -------------------------------------------------------------------------
    -- Clothing (jail clothing, uniforms)
    -------------------------------------------------------------------------
    Clothing = {
        type = "vrp",                  -- "vrp" (get/setCustomization) | "builtin" (natives) | "custom"
        custom = {
            get = function(source) return nil end,
            set = function(source, clothing) end,
        },
    },

    -------------------------------------------------------------------------
    -- Handcuffs
    -------------------------------------------------------------------------
    Handcuff = {
        type = "vrp",                  -- "vrp" (isHandcuffed / setHandcuffed) | "builtin" | "custom"
        custom = {
            isCuffed = function(source) return false end,
            setCuffed = function(source, state) end,
        },
    },

    -------------------------------------------------------------------------
    -- Drag (سحب). Do not hardcode a server event: configure it here.
    -------------------------------------------------------------------------
    Drag = {
        type = "builtin",              -- "builtin" | "event" | "custom"
        event = "gggh",                -- example of a server's own drag event
        eventSide = "client",          -- "client" → TriggerClientEvent | "server" → TriggerEvent
        receiver = "target",           -- client that receives the event: "target" | "officer"
        args = function(officerSource, targetSource) return { officerSource } end,
        custom = function(officerSource, targetSource) end,
    },

    -------------------------------------------------------------------------
    -- Vehicle seats (إدخال للمركبة / إخراج من المركبة)
    -------------------------------------------------------------------------
    Seats = {
        type = "vrp",                  -- "vrp" | "builtin" | "custom"
        custom = {
            putIn = function(targetSource, officerSource) end,
            pullOut = function(targetSource, officerSource) end,
        },
    },

    -------------------------------------------------------------------------
    -- Money (fines, impound fees)
    -------------------------------------------------------------------------
    Money = {
        type = "vrp",                  -- "vrp" | "custom"
        custom = {
            pay = function(user_id, amount, method) return false end, -- method: "wallet" | "bank" | "full"
            give = function(user_id, amount) end,
        },
    },

    -------------------------------------------------------------------------
    -- Chat announcements
    -------------------------------------------------------------------------
    Chat = {
        type = "chat",                 -- "chat" (chat:addMessage) | "custom"
        custom = function(targets, title, message, color) end, -- targets = list of sources
    },

    -------------------------------------------------------------------------
    -- Job label (citizen inquiry, wanted list, identity card)
    -------------------------------------------------------------------------
    Job = {
        type = "vrp",                  -- "vrp" (group with gtype Config.Framework.JobGroupType) | "custom"
        unemployed = "بدون وظيفة",
        custom = function(user_id, source) return nil end,
    },

    -------------------------------------------------------------------------
    -- Profile image (identity card, citizen inquiry, iPad)
    -------------------------------------------------------------------------
    ProfileImage = {
        type = "none",                 -- "none" | "url" | "discord" | "steam" | "custom"
        url = "https://example.com/avatars/{user_id}.png", -- placeholders: {user_id} {discord} {steam} {license}
        cacheMinutes = 60,
        -- "discord" / "steam" need keys in config/server.lua (never sent to clients)
        custom = function(user_id, source) return nil end,
    },
}
