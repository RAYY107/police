local H, T = ...

local function field(officer, action, targetLabel)
    H.choose(officer, H.mainMenu(officer), "الشرطة")
    H.select(officer, "خيارات الميدان")
    H.select(officer, action)
    if targetLabel then H.select(officer, targetLabel) end
    H.advance(1600) -- field cooldown
end

T.describe("Field options", function()
    H.boot({ configure = function(cfg) cfg.Webhooks.field = "https://discord.test/field" end })
    local officer = H.connect(90, { name = "Rayy", groups = { "ps_officer" }, coords = { x = 0, y = 0, z = 30 } })
    local target = H.connect(91, {
        name = "Hossam", coords = { x = 1, y = 1, z = 30 }, wallet = 750,
        inventory = { weed = 5, water = 2, cocaine = 1 },
        weapons = { WEAPON_PISTOL = { ammo = 40 }, WEAPON_KNIFE = { ammo = 0 } },
    })
    H.rpc(officer, "office:clock", {})

    T.it("toggles handcuffs through the handcuff adapter", function()
        field(officer, "كلبشة / فك الكلبشة", "Hossam | ID: 91")
        T.truthy(H.user(91).cuffed)
        field(officer, "كلبشة / فك الكلبشة", "Hossam | ID: 91")
        T.falsy(H.user(91).cuffed)
    end)

    T.it("requires the target to be cuffed before seizing weapons", function()
        field(officer, "استيلاء على الأسلحة", "Hossam | ID: 91")
        T.eq(H.lastNotification(officer), L("field_requires_cuffed"))
        T.truthy(H.user(91).weapons.WEAPON_PISTOL)
        field(officer, "كلبشة / فك الكلبشة", "Hossam | ID: 91")
        field(officer, "استيلاء على الأسلحة", "Hossam | ID: 91")
        T.eq(next(H.user(91).weapons), nil, "weapons cleared")
    end)

    T.it("shows the search panel with items, contraband flags, weapons and money", function()
        H.user(91).weapons = { WEAPON_BAT = { ammo = 0 } }
        H.clearEvents()
        field(officer, "تفتيش", "Hossam | ID: 91")
        local panel = H.uiEvents(officer, "panel")[1]
        T.eq(panel.kind, "search")
        T.eq(panel.data.name, "Hossam")
        T.eq(panel.data.money, 750)
        local weed
        for _, it in ipairs(panel.data.items) do if it.item == "weed" then weed = it end end
        T.eq(weed.amount, 5)
        T.eq(weed.label, "حشيش")
        T.truthy(weed.contraband)
        T.eq(panel.data.weapons[1].name, "WEAPON_BAT")
    end)

    T.it("seizes contraband and logs the exact items and quantities", function()
        local before = #H.http
        field(officer, "استيلاء على الممنوعات", "Hossam | ID: 91")
        T.eq(H.user(91).inventory.weed, nil)
        T.eq(H.user(91).inventory.cocaine, nil)
        T.eq(H.user(91).inventory.water, 2, "legal items untouched")
        H.advance(2000)
        local body
        for i = before + 1, #H.http do if H.http[i].body:find("seize_contraband", 1, true) or H.http[i].body:find("مصادرة ممنوعات", 1, true) then body = H.http[i].body end end
        T.truthy(body, "webhook sent")
        T.contains(body, "weed")
        T.contains(body, "× 5")
        T.contains(body, "cocaine")
    end)

    T.it("puts the target into and out of a vehicle through the seats adapter", function()
        H.vrp.calls = {}
        field(officer, "إدخال للمركبة", "Hossam | ID: 91")
        field(officer, "إخراج من المركبة", "Hossam | ID: 91")
        local fns = {}
        for _, c in ipairs(H.vrp.calls) do if c.src == target then fns[#fns + 1] = c.fn end end
        T.has(fns, "putIn")
        T.has(fns, "eject")
    end)

    T.it("drags with the configured drag integration", function()
        field(officer, "سحب", "Hossam | ID: 91")
        local ev = H.lastClientEvent(target, "evora_police:drag")
        T.eq(ev.args[1], officer)
        Config.Integrations.Drag.type = "event"
        field(officer, "سحب", "Hossam | ID: 91")
        T.truthy(H.lastClientEvent(target, "gggh"), "custom server event (no hardcoding)")
        Config.Integrations.Drag.type = "builtin"
    end)

    T.it("shows the identity card only after the target accepts", function()
        H.clearEvents()
        H.choose(officer, H.mainMenu(officer), "الشرطة")
        H.select(officer, "خيارات الميدان")
        H.select(officer, "عرض الهوية")
        H.select(officer, "Hossam | ID: 91")
        T.eq(#H.uiEvents(officer, "idcard"), 0)
        H.confirm(target, true)
        local card = H.uiEvents(officer, "idcard")[1]
        T.eq(card.name, "Hossam")
        T.eq(card.user_id, 91)
        T.eq(card.job, Config.Integrations.Job.unemployed)
        T.truthy(H.lastClientEvent(target, "evora_police:idcard:present"))
        H.advance(1600)
    end)

    T.it("searches the trunk of the nearest vehicle and seizes its contraband", function()
        H.query("INSERT INTO vrp_user_identities (user_id, registration) VALUES (91, '123ABC')")
        H.query("INSERT INTO vrp_user_vehicles (user_id, vehicle) VALUES (91, 'sultan')")
        H.vrp.sdata["chest:u91veh_sultan"] = json.encode({ meth = { amount = 3 }, bandage = { amount = 1 } })
        H.addVehicle("P 123ABC", { x = 2, y = -1, z = 30 }, "sultan")
        H.clearEvents()
        field(officer, "تفتيش مركبة")
        local panel = H.uiEvents(officer, "panel")[1]
        T.truthy(panel, "vehicle panel")
        T.eq(panel.kind, "vehicle")
        T.eq(panel.data.plate, "P 123ABC")
        T.eq(panel.data.model, "sultan")
        T.eq(panel.data.owner.name, "Hossam")
        T.truthy(panel.data.canSeize)
        local ok, res = H.rpc(officer, "field:vehicleSeize", { token = panel.data.token })
        T.truthy(ok, tostring(res))
        local chest = json.decode(H.vrp.sdata["chest:u91veh_sultan"])
        T.eq(chest.meth, nil)
        T.eq(chest.bandage.amount, 1)
        H.advance(2500)
        local ok2 = H.rpc(officer, "field:vehicleSeize", { token = panel.data.token })
        T.falsy(ok2, "token is single use")
    end)

    T.it("refuses field actions to officers off duty", function()
        H.advance(2500)
        H.rpc(officer, "office:clock", {})
        H.choose(officer, H.mainMenu(officer), "الشرطة")
        H.select(officer, "خيارات الميدان")
        H.select(officer, "تفتيش")
        T.eq(H.lastNotification(officer), L("err_not_on_duty"))
    end)
end)
