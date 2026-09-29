local H, T = ...

local function objects()
    local n = 0
    for _, e in pairs(H.entities) do if e.kind == "object" then n = n + 1 end end
    return n
end

T.describe("Barricades", function()
    H.boot({ configure = function(cfg) cfg.BarricadeOptions.MaxPerOfficer = 2 end })
    local officer = H.connect(120, { name = "Officer", groups = { "ps_officer" }, coords = { x = 0, y = 0, z = 30 } })
    local other = H.connect(121, { name = "Other", groups = { "ps_officer" }, coords = { x = 0, y = 1, z = 30 } })
    local commander = H.connect(122, { name = "Commander", groups = { "ps_commander" }, coords = { x = 1, y = 0, z = 30 } })
    for _, s in ipairs({ officer, other, commander }) do H.rpc(s, "office:clock", {}) end

    T.it("starts a placement preview from the menu", function()
        H.choose(officer, H.mainMenu(officer), "الشرطة")
        H.select(officer, "الحواجز")
        H.select(officer, "وضع حاجز")
        H.select(officer, "حاجز 1")
        local ev = H.lastClientEvent(officer, "evora_police:barricade:place")
        T.eq(ev.args[1], 1)
        T.eq(ev.args[2], "prop_barrier_work05")
    end)

    T.it("validates the position and spawns a frozen server-side object", function()
        local ok, err = H.rpc(officer, "barricade:place", { index = 1, x = 40, y = 0, z = 30, heading = 90 })
        T.falsy(ok)
        T.eq(err, L("barricade_too_far"))
        H.advance(1000)
        local ok2, res = H.rpc(officer, "barricade:place", { index = 1, x = 2, y = 0, z = 30, heading = 90 })
        T.truthy(ok2, tostring(res))
        T.eq(objects(), 1)
        local ent = H.entities[res.netId - 5000]
        T.truthy(ent.frozen)
        T.eq(ent.heading, 90)
        T.eq(ent.model, H.joaat("prop_barrier_work05"))
    end)

    T.it("enforces the per-officer limit and refuses disabled objects", function()
        H.advance(1000)
        T.truthy((H.rpc(officer, "barricade:place", { index = 2, x = 2, y = 1, z = 30 })))
        H.advance(1000)
        local ok, err = H.rpc(officer, "barricade:place", { index = 3, x = 2, y = 2, z = 30 })
        T.falsy(ok)
        T.eq(err, L("barricade_limit"))
        Config.Barricades[4].enabled = false
        H.advance(1000)
        local ok2 = H.rpc(other, "barricade:place", { index = 4, x = 1, y = 1, z = 30 })
        T.falsy(ok2)
        Config.Barricades[4].enabled = true
    end)

    T.it("lets officers remove only their own barricades; admins remove any", function()
        H.choose(other, H.mainMenu(other), "الشرطة")
        H.select(other, "الحواجز")
        H.select(other, "إزالة حاجز")
        T.eq(H.lastNotification(other), L("barricade_none_near"))
        T.eq(objects(), 2)
        H.choose(commander, H.mainMenu(commander), "الشرطة")
        H.select(commander, "الحواجز")
        H.select(commander, "إزالة حاجز")
        T.eq(objects(), 1)
    end)

    T.it("cleans up the barricades of an officer who disconnects", function()
        H.disconnect(officer)
        T.eq(objects(), 0)
    end)
end)
