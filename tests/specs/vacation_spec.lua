local H, T = ...

local function balance(uid)
    return H.query("SELECT vacation_balance FROM evora_police_officers WHERE user_id = ?", { uid })[1].vacation_balance
end

T.describe("Vacations", function()
    H.boot()
    local officer = H.connect(30, { name = "Saad", groups = { "ps_officer", "traffic_officer" } })

    T.it("swaps every military group for the inactive group and consumes balance", function()
        local ok, res = H.rpc(officer, "vacation:request", { days = 3 })
        T.truthy(ok, tostring(res))
        T.eq(res.days, 3)
        local groups = H.groups(30)
        T.eq(table.concat(groups, ","), "police_vacation")
        T.eq(balance(30), Config.Vacation.DefaultBalance - 3)
        local row = H.query("SELECT * FROM evora_police_vacations WHERE user_id = 30")[1]
        T.eq(row.status, "active")
        local saved = json.decode(row.original_groups)
        table.sort(saved)
        T.eq(table.concat(saved, ","), "ps_officer,traffic_officer")
        T.truthy(Evora.Vacation.isOnVacation(30))
    end)

    T.it("keeps the officer out of duty but offers the restricted police menu", function()
        local ok, err = H.rpc(officer, "office:clock", {})
        T.falsy(ok)
        T.eq(err, L("err_not_military"))
        H.choose(officer, H.mainMenu(officer), "الشرطة")
        local labels = H.labels(H.menu(officer))
        T.has(labels, "كسر الإجازة")
        T.hasNot(labels, "المخالفات")
        local ok2, boot = H.rpc(officer, "ipad:bootstrap", {})
        T.truthy(ok2, tostring(boot))
        T.truthy(boot.me.vacation)
        T.eq(next(boot.perms), nil, "no permissions while on vacation")
        T.truthy(boot.office.vacation.active)
    end)

    T.it("restores the exact groups when the vacation is broken, refunding unused days", function()
        H.advance(4000)
        local ok, err = H.rpc(officer, "vacation:break", {})
        T.truthy(ok, tostring(err))
        T.eq(table.concat(H.groups(30), ","), "ps_officer,traffic_officer")
        T.falsy(Evora.Vacation.isOnVacation(30))
        T.eq(balance(30), Config.Vacation.DefaultBalance - 3 + 2)
        local row = H.query("SELECT status, restored FROM evora_police_vacations WHERE user_id = 30")[1]
        T.eq(row.status, "broken")
        T.eq(row.restored, 1)
    end)

    T.it("refuses a vacation longer than the balance", function()
        H.advance(4000)
        local ok, err = H.rpc(officer, "vacation:request", { days = 30 })
        T.falsy(ok)
        T.contains(err, "رصيد")
    end)

    T.it("restores groups on the next join when a vacation expires offline", function()
        H.advance(4000)
        T.truthy((H.rpc(officer, "vacation:request", { days = 1 })))
        H.disconnect(officer)
        Evora.Vacation.active[30].end_at = os.time() - 5
        H.advance(Config.Vacation.CheckInterval * 1000 + 1000)
        local row = H.query("SELECT status, restored FROM evora_police_vacations WHERE user_id = 30 ORDER BY id DESC")[1]
        T.eq(row.status, "ended")
        T.eq(row.restored, 0, "cannot restore while offline")
        officer = H.connect(30, { name = "Saad" })
        T.eq(table.concat(H.groups(30), ","), "ps_officer,traffic_officer")
        row = H.query("SELECT restored FROM evora_police_vacations WHERE user_id = 30 ORDER BY id DESC")[1]
        T.eq(row.restored, 1)
    end)

    T.it("cancels the vacation (no restore) when the officer is dismissed during it", function()
        H.advance(4000)
        T.truthy((H.rpc(officer, "vacation:request", { days = 1 })))
        local minister = H.connect(31, { name = "Minister", groups = { "interior_minister" } })
        local id = H.rpcStart(minister, "affairs:dismiss", { user_id = 30 })
        H.confirm(minister, true)
        local done, ok, err = H.rpcResult(minister, id)
        T.truthy(done and ok, tostring(err))
        T.eq(#H.groups(30), 0, "inactive group removed, nothing restored")
        T.falsy(Evora.Vacation.isOnVacation(30))
        local row = H.query("SELECT status FROM evora_police_vacations WHERE user_id = 30 ORDER BY id DESC")[1]
        T.eq(row.status, "cancelled")
    end)
end)
