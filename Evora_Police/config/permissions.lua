--[[
    Evora_Police — Roles & permissions

    Nothing is hardcoded as "a commander can do X". Every rank receives the permissions of
    the roles it is listed in. A rank listed in several roles receives all of them.
    `inherits` copies the permissions of another role (string or list of role names).

    WHERE a permission applies is decided by the hierarchy (config/government.lua):
        sector rank    → its own sector
        ministry rank  → every sector of its ministry
        prime ministry → every configured ministry and sector

    ── Capabilities ───────────────────────────────────────────────────────────────
    ipad               open القائمة العسكرية (police iPad)
    clock              تسجيل الدخول / تسجيل الخروج
    vacation           request / break own vacation
    militaryCode       edit own military / radio code
    reports            view and handle citizen reports (البلاغات)
    wanted             create wanted notices (تعميم بلاغ)
    wantedClear        remove wanted notices
    citizenInquiry     استعلام عن مواطن
    fines              issue fines
    fineInquiry        استعلام عن مخالفات
    jail               jail players
    jailCheck          التحقق من سجن لاعب
    jailModify         تعديل مدة السجن
    jailMonitor        مراقبة سجين
    jailRelease        فك سجن
    field              خيارات الميدان
    equipment          أخذ العتاد
    uniforms           الملابس
    securityAlert      الاستنفار الأمني
    impound            حجز المركبات
    impoundInquiry     الاستعلام عن المركبات المحجوزة
    impoundRelease     release impounded vehicles
    barricades         spawn / remove own barricades
    barricadesAdmin    remove anyone's barricades
    affairs            open الشؤون
    broadcastOfficers  تعميم على العساكر
    broadcastCitizens  تعميم على المواطنين

    ── Scoped (only on officers inside the administrator's scope) ────────────────
    recruit            توظيف
    dismiss            فصل
    recall             سحب العساكر
    monitor            مراقبة العساكر
    vacationBalance    إضافة رصيد إجازة
    vacationBreak      break another officer's vacation
    officerInquiry     استعلام عن عسكري
    resetAttendance    تصفير تواجد عسكري
    resetFines         تصفير مخالفات عسكري
    resetData          تصفير بيانات عسكري
    statistics         توب 10 عساكر

    ── Shorthands ─────────────────────────────────────────────────────────────────
    all = true         every permission above
    broadcast = true   broadcastOfficers + broadcastCitizens
    reset = true       resetAttendance + resetFines + resetData
]]

Config.Roles = {

    Officer = {
        ranks = {
            "ps_officer",
            "ps_patrol",
            "traffic_officer",
            "sector_officer",
        },
        permissions = {
            ipad = true,
            clock = true,
            vacation = true,
            militaryCode = true,
            reports = true,
            wanted = true,
            citizenInquiry = true,
            fines = true,
            fineInquiry = true,
            jail = true,
            jailCheck = true,
            field = true,
            equipment = true,
            uniforms = true,
            impound = true,
            impoundInquiry = true,
            barricades = true,
        },
    },

    SectorDeputy = {
        ranks = {
            "ps_deputy",
        },
        inherits = "Officer",
        permissions = {
            wantedClear = true,
            jailMonitor = true,
            securityAlert = true,
            affairs = true,
            broadcastOfficers = true,
            monitor = true,
            officerInquiry = true,
            statistics = true,
        },
    },

    SectorCommander = {
        ranks = {
            "ps_commander",
            "traffic_commander",
            "sector_commander",
        },
        inherits = "SectorDeputy",
        permissions = {
            affairs = true,
            recruit = true,
            dismiss = true,
            broadcast = true,
            recall = true,
            monitor = true,
            vacationBalance = true,
            vacationBreak = true,
            resetData = true,
            resetAttendance = true,
            resetFines = true,
            statistics = true,
            jailModify = true,
            jailRelease = true,
            impoundRelease = true,
            barricadesAdmin = true,
        },
    },

    MinistryLeadership = {
        ranks = {
            "interior_minister",
            "interior_deputy",
            "defense_minister",
            "defense_deputy",
        },
        inherits = "SectorCommander",
        permissions = {},
    },

    PrimeMinistry = {
        ranks = {
            "prime_minister",
            "prime_deputy",
        },
        permissions = {
            all = true,
        },
    },

}
