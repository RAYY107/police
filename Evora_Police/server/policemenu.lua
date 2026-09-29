--[[
    Evora_Police — Builder Menu integration

    Main menu entries:
        الشرطة           → configured police / sector authority (or an officer on vacation)
        إبلاغ عن مجرم    → everyone
    Police menu (each entry has its Config.Features switch and permission):
        1 القائمة العسكرية  2 تسجيل الدخول/الخروج  3 استعلام عن مواطن  4 تعميم بلاغ  5 المخالفات
        6 السجن  7 خيارات الميدان  8 الأدوات الأمنية  9 استعلامات  10 حجز المركبات  11 الحواجز
]]

local PoliceMenu = {}
Evora.PoliceMenu = PoliceMenu

local P, Gov, Officers, Vacation = Evora.Players, Evora.Gov, Evora.Officers, Evora.Vacation

local function root(source) return PoliceMenu.build(source) end

local function securityMenu(source)
    local profile = Gov.getProfile(P.getUserId(source), true)
    local back = function(s) return securityMenu(s) end
    local items = {}
    if Gov.has(profile, "equipment") then
        items[#items + 1] = { label = L("menu_equipment"), description = L("menu_equipment_desc"),
            action = function(src) local m = Evora.Equipment.kitsMenu(src, back) if m then Evora.Menu.open(src, m) end end }
    end
    if Gov.has(profile, "uniforms") then
        items[#items + 1] = { label = L("menu_uniforms"), description = L("menu_uniforms_desc"),
            action = function(src) local m = Evora.Equipment.uniformsMenu(src, back) if m then Evora.Menu.open(src, m) end end }
    end
    if Gov.has(profile, "securityAlert") then
        items[#items + 1] = { label = L("menu_security_alert"), description = L("menu_security_alert_desc"),
            action = function(src) local m = Evora.Alert.menu(src, back) if m then Evora.Menu.open(src, m) end end }
    end
    return { title = L("menu_security_tools"), items = items, parent = root }
end

local function inquiriesMenu(source)
    local profile = Gov.getProfile(P.getUserId(source), true)
    local back = function(s) return inquiriesMenu(s) end
    local items = {}
    local function add(perm, feature, key, fn)
        if Gov.has(profile, perm) and Evora.feature(feature) then
            items[#items + 1] = { label = L(key), description = L(key .. "_desc"), action = function(src) fn(src, back) end }
        end
    end
    add("fineInquiry", "Fines", "inq_fines", function(src) Evora.Fines.inquiryFlow(src) end)
    add("jailCheck", "Jail", "inq_jail_check", function(src) Evora.Jail.checkFlow(src) end)
    add("jailModify", "Jail", "inq_jail_modify", function(src, b) Evora.Jail.modifyFlow(src, b) end)
    add("jailMonitor", "Jail", "inq_jail_monitor", function(src, b) Evora.Jail.monitorFlow(src, b) end)
    add("jailRelease", "Jail", "inq_jail_release", function(src, b) Evora.Jail.releaseFlow(src, b) end)
    add("impoundInquiry", "Impound", "inq_impound", function(src) Evora.Impound.inquiryFlow(src) end)
    return { title = L("menu_inquiries"), items = items, parent = root }
end

-- Police menu built from the player's LIVE groups.
function PoliceMenu.build(source)
    local user_id = P.getUserId(source)
    local profile = Gov.getProfile(user_id, true)
    local items = {}

    if Vacation.isOnVacation(user_id) then
        if Evora.feature("Ipad") then
            items[#items + 1] = { label = L("menu_ipad"), description = L("menu_ipad_desc"), action = function(src) Evora.Ipad.open(src, "office") end }
        end
        items[#items + 1] = {
            label = L("menu_vacation_break"), description = L("menu_vacation_break_desc"),
            action = function(src)
                local uid = P.getUserId(src)
                local ok, err = Vacation.finish(uid, "broken", uid)
                if not ok then Evora.notify(src, err, nil, "error") end
            end,
        }
        return { title = L("menu_police"), subtitle = L("vacation_active_subtitle"), items = items }
    end

    local function add(feature, perms, key, fn, labelOverride)
        if not Evora.feature(feature) or not Gov.hasAny(profile, perms) then return end
        items[#items + 1] = { label = labelOverride or L(key), description = L(key .. "_desc"), action = fn }
    end

    add("Ipad", "ipad", "menu_ipad", function(src) Evora.Ipad.open(src, "office") end)
    add("Clock", "clock", "menu_clock", function(src) Evora.Ipad.toggleDuty(src) end,
        Officers.isOnDuty(user_id) and L("menu_clock_out") or L("menu_clock_in"))
    add("CitizenInquiry", "citizenInquiry", "menu_citizen_inquiry", function(src) Evora.Citizens.inquiryFlow(src) end)
    add("Wanted", "wanted", "menu_wanted", function(src) Evora.Wanted.createFlow(src) end)
    add("Fines", "fines", "menu_fines", function(src) Evora.Fines.openMenu(src, root) end)
    add("Jail", "jail", "menu_jail", function(src) Evora.Jail.openMenu(src, root) end)
    add("Field", "field", "menu_field", function(src) Evora.Menu.open(src, Evora.Field.menu(src, root)) end)
    add("SecurityTools", { "equipment", "uniforms", "securityAlert" }, "menu_security_tools", function(src) Evora.Menu.open(src, securityMenu(src)) end)
    add("Inquiries", { "fineInquiry", "jailCheck", "jailModify", "jailMonitor", "jailRelease", "impoundInquiry" }, "menu_inquiries",
        function(src) Evora.Menu.open(src, inquiriesMenu(src)) end)
    add("Impound", { "impound", "impoundInquiry", "impoundRelease" }, "menu_impound", function(src) Evora.Menu.open(src, Evora.Impound.menu(src, root)) end)
    add("Barricades", "barricades", "menu_barricades", function(src) local m = Evora.Barricades.menu(src, root) if m then Evora.Menu.open(src, m) end end)

    local summary = Gov.summary(profile)
    return {
        title = L("menu_police"),
        subtitle = ("%s • %s"):format(summary.rank, summary.sectorLabel ~= "" and summary.sectorLabel or summary.ministryLabel),
        items = items,
    }
end

-- Main menu entries. Runs inside vRP's menu builder: cached data only, never yields.
function PoliceMenu.mainEntries(source)
    local items = {}
    local user_id = P.bySource[source]
    if user_id then
        local profile = Gov.cached(user_id)
        if profile.isMilitary or Vacation.isOnVacation(user_id) then
            items[#items + 1] = {
                label = L("menu_police"), description = L("menu_police_desc"),
                action = function(src) Evora.Menu.open(src, PoliceMenu.build(src)) end,
            }
        end
    end
    if Evora.feature("CitizenReport") then
        items[#items + 1] = {
            label = L("menu_report"), description = L("menu_report_desc"),
            action = function(src) Evora.Reports.createFlow(src) end,
        }
    end
    return items
end

function PoliceMenu.register()
    Evora.Menu.registerMain(PoliceMenu.mainEntries)
end
