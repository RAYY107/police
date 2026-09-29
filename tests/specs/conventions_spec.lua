local H, T = ...

T.describe("Universal vRP: modern calling convention", function()
    H.boot({ style = "modern" })
    local cmd = H.connect(130, { name = "Commander", groups = { "ps_commander" }, coords = { x = 0, y = 0, z = 30 } })
    local citizen = H.connect(131, { name = "Hossam", coords = { x = 1, y = 0, z = 30 } })

    T.it("detects the modern convention from vrp/lib/Proxy.lua", function()
        T.eq(Evora.Framework.style, "modern")
    end)

    T.it("reads and changes groups", function()
        T.truthy((H.rpc(cmd, "affairs:recruit", { user_id = 131, rank = "ps_patrol" })))
        T.eq(table.concat(H.groups(131), ","), "ps_patrol")
    end)

    T.it("uses vRP.prompt (returning values) for popups", function()
        local reporter = H.connect(132, { name = "Reporter" })
        H.prompts(reporter, { "131", "اختبار" })
        H.choose(reporter, H.mainMenu(reporter), "إبلاغ عن مجرم")
        T.eq(#H.query("SELECT id FROM evora_police_reports"), 1)
    end)

    T.it("reads clothing / cuffs through the client tunnel", function()
        H.advance(2000)
        H.rpc(cmd, "office:clock", {})
        H.choose(cmd, H.mainMenu(cmd), "الشرطة")
        H.select(cmd, "السجن")
        H.selectMatching(cmd, "اعتداء")
        H.select(cmd, "Hossam | ID: 131")
        H.confirm(citizen, true)
        T.truthy(Evora.Jail.isJailed(131))
        T.truthy(H.user(131).cuffed)
        T.eq(H.user(131).custom[11][1], 146)
    end)
end)

T.describe("Without OneSync (client-reported positions)", function()
    H.boot({ onesync = false })
    H.clientResponders.coords = function(src)
        local c = H.coords(src)
        return { x = c.x, y = c.y, z = c.z }
    end
    H.clientResponders.nearbyPlayers = function(src, args)
        local list = {}
        local me = H.coords(src)
        for other in pairs(H.players) do
            if other ~= src then
                local c = H.coords(other)
                local d = math.sqrt((c.x - me.x) ^ 2 + (c.y - me.y) ^ 2 + (c.z - me.z) ^ 2)
                if d <= args.radius then list[#list + 1] = { source = other, dist = d } end
            end
        end
        return list
    end
    local officer = H.connect(140, { name = "Rayy", groups = { "ps_officer" }, coords = { x = 0, y = 0, z = 30 } })
    local target = H.connect(141, { name = "Hossam", coords = { x = 2, y = 0, z = 30 } })
    H.rpc(officer, "office:clock", {})

    T.it("detects that OneSync is off", function()
        T.falsy(Evora.Players.oneSync())
    end)

    T.it("still lists nearby targets and issues fines", function()
        H.choose(officer, H.mainMenu(officer), "الشرطة")
        H.select(officer, "المخالفات")
        H.select(officer, "مخالفات عامة")
        H.selectMatching(officer, "إزعاج عام")
        T.has(H.labels(H.menu(officer)), "Hossam | ID: 141")
        H.select(officer, "Hossam | ID: 141")
        H.confirm(target, true)
        T.eq(#H.query("SELECT id FROM evora_police_fines"), 1)
    end)

    T.it("accepts client escape reports only for jailed players", function()
        local ok = H.rpc(target, "jail:escaped", {})
        T.truthy(ok)
        T.eq(#H.clientEvents(target, "evora_police:teleport"), 0, "not jailed: nothing happens")
    end)
end)
