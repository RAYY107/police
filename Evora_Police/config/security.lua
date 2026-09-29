--[[
    Evora_Police — Security alert (الاستنفار الأمني) and barricades (الحواجز)

    Security alert rule: players ALREADY inside the zone when the alert starts are not
    affected; players who enter after it starts are. With ExemptionEndsOnExit = true an
    exempt player who leaves and comes back is treated as a new entry.
]]

Config.SecurityAlert = {
    Zones = {
        { id = "downtown", label = "وسط المدينة", coords = vector3(215.76, -810.12, 30.73), radius = 250.0 },
        { id = "pacific",  label = "البنك المركزي", coords = vector3(235.06, 216.54, 106.29), radius = 160.0 },
        { id = "airport",  label = "المطار الدولي", coords = vector3(-1037.0, -2737.0, 20.17), radius = 350.0 },
    },
    AllowCurrentLocation = true,  -- "موقعي الحالي"
    DefaultRadius = 200.0,
    MaxActive = 3,

    MapZone = {
        enabled = true,
        color = 1,                -- red
        alpha = 110,
        blip = { enabled = true, sprite = 161, color = 1, scale = 1.2, label = "استنفار أمني" },
    },

    VehicleSlowdown = { enabled = true, maxSpeed = 40.0 },  -- km/h
    PlayerSlowdown = { enabled = true, disableSprint = true, disableJump = true, moveRate = 0.85 },

    ExemptOfficers = true,        -- clocked-in officers are never slowed
    ExemptionEndsOnExit = true,
    AnnounceToCitizens = true,    -- citizen broadcast when an alert starts / stops
    CheckInterval = 400,          -- ms (client)
}

-- Barricade objects. Disable an object with enabled = false.
Config.Barricades = {
    { label = "حاجز 1", model = "prop_barrier_work05", enabled = true },
    { label = "حاجز 2", model = "prop_mp_barrier_02b", enabled = true },
    { label = "حاجز مروري", model = "prop_barrier_work06a", enabled = true },
    { label = "حاجز خرساني", model = "prop_mp_barrier_01", enabled = true },
    { label = "مخروط مروري", model = "prop_roadcone02a", enabled = true },
    { label = "لوحة تحويلة", model = "prop_mp_arrow_barrier_01", enabled = true },
}

Config.BarricadeOptions = {
    MaxPerOfficer = 10,
    MaxTotal = 80,
    PlaceDistance = 2.2,          -- metres in front of the officer
    MaxPlaceDistance = 6.0,       -- server-side validation
    DeleteRadius = 3.5,
    LifetimeMinutes = 60,         -- 0 = never expire
    DeleteOnDisconnect = true,
}
