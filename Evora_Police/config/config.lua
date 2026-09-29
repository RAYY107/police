--[[
    ███████╗██╗   ██╗ ██████╗ ██████╗  █████╗
    ██╔════╝██║   ██║██╔═══██╗██╔══██╗██╔══██╗
    █████╗  ██║   ██║██║   ██║██████╔╝███████║
    ██╔══╝  ╚██╗ ██╔╝██║   ██║██╔══██╗██╔══██║
    ███████╗ ╚████╔╝ ╚██████╔╝██║  ██║██║  ██║
    ╚══════╝  ╚═══╝   ╚═════╝ ╚═╝  ╚═╝╚═╝  ╚═╝
    Evora_Police — Made By LR

    General configuration. Every file inside /config is shared with clients
    EXCEPT config/server.lua (webhooks and secrets). Never put secrets here.
]]

Config = Config or {}

-- Prints permission / group / sector / integration / database / jail / impound / spectate
-- diagnostics to the server and client console. Keep false in production.
Config.Debug = false

---------------------------------------------------------------------------
-- Framework (Universal vRP)
---------------------------------------------------------------------------
Config.Framework = {
    Resource = "vrp",        -- name of the vRP resource folder
    CallStyle = "auto",      -- "auto" | "legacy" (vRP.fn({args})) | "modern" (vRP.fn(args...))
    JobGroupType = "job",    -- vRP group gtype shown as the citizen's job
    ReadGroupsConfig = true, -- read vrp/cfg/groups.lua to validate groups and read titles
}

-- "auto" reads the onesync convar. OneSync is strongly recommended: it enables
-- server-side distance checks, server teleports and vehicle validation.
Config.OneSync = "auto"      -- "auto" | true | false

Config.Database = {
    Driver = "auto",         -- "auto" | "oxmysql" | "mysql-async" | "ghmattimysql" | "custom"
    AutoCreateTables = true, -- create the evora_police_* tables on start
    -- Driver = "custom": functions receive (sql, params, callback) with positional "?" params.
    -- Custom = { query = function(sql, params, cb) end, execute = ..., insert = ... },
}

---------------------------------------------------------------------------
-- Feature switches (Builder Menu entries and systems)
---------------------------------------------------------------------------
Config.Features = {
    Ipad           = { enabled = true },  -- القائمة العسكرية
    Clock          = { enabled = true },  -- تسجيل الدخول / تسجيل الخروج
    CitizenInquiry = { enabled = true },  -- استعلام عن مواطن
    Wanted         = { enabled = true },  -- تعميم بلاغ
    Fines          = { enabled = true },  -- المخالفات
    Jail           = { enabled = true },  -- السجن
    Field          = { enabled = true },  -- خيارات الميدان
    SecurityTools  = { enabled = true },  -- الأدوات الأمنية
    Inquiries      = { enabled = true },  -- استعلامات
    Impound        = { enabled = true },  -- حجز المركبات
    Barricades     = { enabled = true },  -- الحواجز
    CitizenReport  = { enabled = true },  -- إبلاغ عن مجرم (everyone)
    Vacation       = { enabled = true },  -- الإجازات
    Affairs        = { enabled = true },  -- الشؤون (iPad)
    Reports        = { enabled = true },  -- البلاغات (iPad)
}

---------------------------------------------------------------------------
-- Duty / attendance
---------------------------------------------------------------------------
-- Officers are always clocked out when they disconnect: attendance only counts while
-- clocked in and connected.
Config.Duty = {
    HeartbeatInterval = 60,     -- seconds between attendance heartbeats
    MaxStaleSessionHours = 12,  -- cap applied when closing a session found after a crash
    -- Actions that require the officer to be clocked in.
    RequireDutyFor = {
        citizenInquiry = false,
        wanted = true,
        fines = true,
        jail = true,
        field = true,
        equipment = true,
        uniforms = false,
        securityAlert = true,
        impound = true,
        barricades = true,
        reports = false,
        inquiries = false,
    },
}

-- Military / radio code (الكود العسكري). Connected to the radio through Config.Integrations.Radio.
Config.MilitaryCode = {
    MaxLength = 12,
    Default = "",
}

---------------------------------------------------------------------------
-- Vacation (الإجازات)
---------------------------------------------------------------------------
Config.Vacation = {
    -- Group given to officers while on vacation. It MUST exist in vrp/cfg/groups.lua.
    InactiveGroup = "police_vacation",
    DefaultBalance = 7,   -- days granted when an officer record is created
    MaxBalance = 60,
    Durations = {
        { days = 1, label = "يوم واحد" },
        { days = 3, label = "3 أيام" },
        { days = 7, label = "أسبوع" },
        { days = 14, label = "أسبوعين" },
    },
    AllowCustom = true,
    MaxCustomDays = 30,
    RefundOnBreak = true, -- give back unused full days when a vacation is broken early
    CheckInterval = 60,   -- seconds
}

---------------------------------------------------------------------------
-- Targeting (nearby player picker)
---------------------------------------------------------------------------
Config.Targeting = {
    Radius = 4.0,     -- metres
    MaxResults = 8,
}

---------------------------------------------------------------------------
-- Confirmation system (F5 = قبول / F6 = رفض)
---------------------------------------------------------------------------
Config.Confirm = {
    AcceptKey = 166,       -- F5 (INPUT_SELECT_CHARACTER_MICHAEL)
    RejectKey = 167,       -- F6 (INPUT_SELECT_CHARACTER_FRANKLIN)
    AcceptLabel = "F5",
    RejectLabel = "F6",
    DefaultTimeout = 30,   -- seconds
    -- Who confirms each action: "target" (the affected player), "self" (the officer) or false.
    Actions = {
        fine = "target",
        jail = "target",
        recall = "target",
        identity = "target",
        jailModify = "self",
        jailRelease = "self",
        impound = "self",
        impoundRelease = "self",
        dismiss = "self",
        recruit = false,
        resetAttendance = "self",
        resetFines = "self",
        resetData = "self",
        vacationBalance = false,
        vacationBreak = "self",
    },
}

---------------------------------------------------------------------------
-- Broadcasts (تعميم على العساكر / تعميم على المواطنين)
---------------------------------------------------------------------------
Config.Broadcast = {
    OfficerEnabled = true,
    CitizenEnabled = true,
    OfficerTitle = "تعميم عسكري",
    CitizenTitle = "تعميم",
    OfficerAudience = "all",  -- "all" military personnel | "scope" of the sender | "onduty" only
    Duration = 12,            -- seconds on screen
    MaxLength = 300,
    Cooldown = 30,            -- seconds between broadcasts per sender
    ShowSender = true,
    Style = {
        top = "26%",          -- slightly above screen centre
        width = "560px",
        animation = "slide",  -- "slide" | "fade" | "zoom"
        officerAccent = "#8b5cf6",
        citizenAccent = "#f59e0b",
    },
    Sound = { enabled = true, name = "CHECKPOINT_PERFECT", set = "HUD_MINI_GAME_SOUNDSET" },
}

---------------------------------------------------------------------------
-- Officer recall (سحب العساكر)
---------------------------------------------------------------------------
Config.Recall = {
    Timeout = 45,             -- seconds each officer has to answer
    Cooldown = 120,
    IncludeOffDuty = true,    -- off-duty officers of the scope are recalled too
    Waypoint = "caller",      -- "caller" | "hq" | "none"
    HQ = vector3(441.1, -981.9, 30.7),
    AutoClockIn = true,       -- accepting officers are clocked in automatically
    DefaultMessage = "مطلوب حضوركم إلى موقع الاستدعاء فوراً",
}

---------------------------------------------------------------------------
-- Resets (تصفير) — define exactly what "تصفير بيانات عسكري" clears
---------------------------------------------------------------------------
Config.Reset = {
    Data = {
        attendance = true,        -- total attendance (seconds)
        attendanceHistory = false,-- delete stored duty sessions
        fines = true,             -- issued-fine counter
        jails = true,             -- jail counter
        reports = true,           -- handled-reports counter
        impounds = true,          -- impound counter
        vacationBalance = false,  -- restore DefaultBalance
        militaryCode = false,
    },
}

---------------------------------------------------------------------------
-- Statistics / Top 10 (توب 10 عساكر)
---------------------------------------------------------------------------
Config.Statistics = {
    Top = 10,
    -- One combined ranking: score = attendance hours * attendanceHour + fines * fine
    Weights = { attendanceHour = 1.0, fine = 0.5 },
    WebhookCooldown = 60,
}

---------------------------------------------------------------------------
-- Reports (البلاغات / إبلاغ عن مجرم)
---------------------------------------------------------------------------
Config.Reports = {
    Cooldown = 60,            -- seconds between reports per citizen
    MaxOpenPerReporter = 3,
    MaxReasonLength = 250,
    NotifyOfficers = "onduty",-- "onduty" | "all" | "none"
    NotifyReporterOnClaim = true,
    AllowSelfReport = false,
    StoreLocation = true,     -- lets officers set a waypoint to where the report was filed
    ListLimit = 100,
}

---------------------------------------------------------------------------
-- Wanted (تعميم بلاغ / مطلوبين الدولة)
---------------------------------------------------------------------------
Config.Wanted = {
    MaxReasonLength = 250,
    NotifyOfficers = "onduty",-- "onduty" | "all"
    ClearOnJail = true,
    QuickOpen = { enabled = true, key = 47, label = "G", seconds = 10 }, -- open the wanted page from the alert
    ListLimit = 100,
}

---------------------------------------------------------------------------
-- Spectate (مراقبة العساكر / مراقبة سجين)
---------------------------------------------------------------------------
Config.Spectate = {
    StopKey = 194,            -- BACKSPACE
    StopKeyLabel = "BACKSPACE",
    FollowInterval = 500,     -- ms between follow updates
    Command = "evora_stopspectate", -- emergency stop command
}

---------------------------------------------------------------------------
-- iPad
---------------------------------------------------------------------------
Config.Ipad = {
    Command = false,          -- e.g. "tablet" to also open the iPad with a command
    Key = false,              -- e.g. "F10" (only used when Command is set)
    Animation = true,
    Prop = "prop_cs_tablet",
    AnimDict = "amb@code_human_in_bus_passenger_idles@female@tablet@base",
    AnimName = "base",
}

---------------------------------------------------------------------------
-- Identity card (عرض الهوية)
---------------------------------------------------------------------------
Config.IdCard = {
    Title = "بطاقة الهوية الوطنية",
    Country = "المملكة العربية السعودية",
    Duration = 10,            -- seconds the card stays on the officer's screen
    Animation = { dict = "mp_common", name = "givetake1_a", duration = 1500 },
}

---------------------------------------------------------------------------
-- Chat announcements (placeholders: {officer} {officer_id} {target} {target_id} ...)
---------------------------------------------------------------------------
Config.Chat = {
    Fine = {
        enabled = true,
        audience = "all",     -- "all" | "officers" | "involved"
        title = "الشرطة",
        color = { 231, 76, 60 },
        template = "العسكري {officer} | ID: {officer_id} قام بمخالفة اللاعب {target} | ID: {target_id} بقيمة {amount}$",
    },
    Jail = {
        enabled = true,
        audience = "all",
        title = "الشرطة",
        color = { 155, 89, 182 },
        template = "العسكري {officer} | ID: {officer_id} قام بسجن اللاعب {target} | ID: {target_id} لمدة {minutes} دقيقة",
    },
    JailRelease = {
        enabled = true,
        audience = "all",
        title = "الشرطة",
        color = { 46, 204, 113 },
        template = "العسكري {officer} | ID: {officer_id} قام بفك سجن اللاعب {target} | ID: {target_id}",
    },
    JailServed = {
        enabled = false,
        audience = "all",
        title = "الشرطة",
        color = { 46, 204, 113 },
        template = "تم الإفراج عن اللاعب {target} | ID: {target_id} بعد انتهاء محكوميته",
    },
}

---------------------------------------------------------------------------
-- UI
---------------------------------------------------------------------------
Config.UI = {
    Brand = "Evora",
    Product = "Evora_Police",
    Author = "Made By LR",
    Accent = "#8b5cf6",
    ArabicDigits = false,     -- show ٠١٢٣ instead of 0123
    Hints = true,             -- NUI key hints near interaction points
}
