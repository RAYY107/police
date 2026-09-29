local H, T = ...

T.describe("RPC gatekeeping (single entry point)", function()
    H.boot()
    local citizen = H.connect(1, { name = "Citizen" })
    local officer = H.connect(2, { name = "Officer", groups = { "ps_officer" } })
    local commander = H.connect(3, { name = "Commander", groups = { "ps_commander" } })

    T.it("rejects unknown actions", function()
        local ok, err = H.rpc(citizen, "affairs:giveMeAdmin", {})
        T.falsy(ok)
        T.eq(err, L("err_unknown_action"))
    end)

    T.it("rejects non-military players on military actions", function()
        local ok, err = H.rpc(citizen, "ipad:online", {})
        T.falsy(ok)
        T.eq(err, L("err_not_military"))
    end)

    T.it("rejects officers without the permission", function()
        local ok, err = H.rpc(officer, "affairs:overview", {})
        T.falsy(ok)
        T.eq(err, L("err_no_permission"))
        ok = H.rpc(commander, "affairs:overview", {})
        T.truthy(ok, "commander allowed")
    end)

    T.it("enforces duty requirements", function()
        local ok, err = H.rpc(officer, "barricade:place", { index = 1, x = 100, y = 101, z = 30 })
        T.falsy(ok)
        T.eq(err, L("err_not_on_duty"))
    end)

    T.it("enforces feature switches", function()
        Config.Features.Affairs.enabled = false
        local ok, err = H.rpc(commander, "affairs:overview", {})
        Config.Features.Affairs.enabled = true
        T.falsy(ok)
        T.eq(err, L("err_feature_disabled"))
    end)

    T.it("validates payloads", function()
        local ok, err = H.rpc(commander, "affairs:recruit", { user_id = "abc", rank = { 1 } })
        T.falsy(ok)
        T.eq(err, L("err_invalid_request"))
        H.advance(2000) -- invalid calls still consume the action cooldown
        ok, err = H.rpc(commander, "affairs:recruit", { user_id = 1, rank = "not_a_rank" })
        T.falsy(ok)
        T.eq(err, L("err_invalid_request"))
    end)

    T.it("rate limits bursts per player", function()
        local limited = 0
        for _ = 1, 40 do
            local ok, err = H.rpc(citizen, "session:init", {})
            if not ok and err == L("err_rate_limit") then limited = limited + 1 end
        end
        T.truthy(limited > 0, "some calls must be rate limited")
        H.advance(5000)
        local ok = H.rpc(citizen, "session:init", {})
        T.truthy(ok, "bucket refills")
    end)

    T.it("applies per-action cooldowns", function()
        local ok = H.rpc(officer, "office:clock", {})
        T.truthy(ok)
        local ok2, err = H.rpc(officer, "office:clock", {})
        T.falsy(ok2)
        T.eq(err, L("err_cooldown"))
        H.advance(2500)
        T.truthy((H.rpc(officer, "office:clock", {})))
    end)

    T.it("ignores events that are not registered network events", function()
        T.falsy(H.fromClient(citizen, "evora_police:jail:finish", 1))
        T.falsy(H.fromClient(citizen, "vRP:playerSpawn", 1, citizen, true))
    end)

    T.it("ignores client callback answers coming from another player", function()
        local done, value = false, nil
        Evora.thread(function()
            value = Evora.clientRequest(officer, "coords", nil, 2000)
            done = true
        end)
        H.settle()
        local req = H.lastClientEvent(officer, "evora_police:creq")
        H.fromClient(citizen, "evora_police:cres", req.args[1], { x = 1, y = 2, z = 3 })
        H.settle()
        T.falsy(done, "answer from the wrong player must be ignored")
        H.fromClient(officer, "evora_police:cres", req.args[1], { x = 5, y = 6, z = 7 })
        H.settle()
        T.truthy(done)
        T.eq(value.x, 5)
    end)
end)
