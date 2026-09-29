local H, T = ...

T.describe("Hierarchy & authority engine", function()
    H.boot()
    local Gov = Evora.Gov

    local function profile(groups)
        local set = {}
        for _, g in ipairs(groups) do set[g] = true end
        local p = Gov.resolve(set)
        p.user_id = 999
        return p
    end

    T.it("compiles ministries, namespaced sectors and ranks from config", function()
        T.eq(#Gov.ministryList, 2)
        T.eq(#Gov.sectorList, 3)
        T.eq(#Gov.rankList, 14)
        T.truthy(Gov.sectors["Interior.PublicSecurity"], "PublicSecurity sector id")
        T.truthy(Gov.sectors["Interior.Traffic"], "Traffic sector id")
        T.eq(Gov.ranks.ps_officer.sector, "Interior.PublicSecurity")
        T.eq(Gov.ranks.ps_officer.ministry, "Interior")
        T.eq(Gov.ranks.interior_minister.level, "ministry")
        T.eq(Gov.ranks.prime_minister.level, "prime")
        T.eq(Gov.ranks.ps_commander.order, 1)
        T.eq(Gov.ranks.ps_patrol.order, 4)
    end)

    T.it("reads rank titles from groups.lua", function()
        T.eq(Gov.rankLabel("ps_commander"), "قائد الأمن العام")
        T.eq(Gov.sectorLabel("Interior.Traffic"), "المرور")
    end)

    T.it("merges role permissions with inheritance and shorthands", function()
        local cmd = Gov.ranks.ps_commander.perms
        T.truthy(cmd.fines, "commander inherits officer permission")
        T.truthy(cmd.monitor, "commander inherits deputy permission")
        T.truthy(cmd.recruit, "commander permission")
        T.truthy(cmd.broadcastOfficers and cmd.broadcastCitizens, "broadcast shorthand")
        T.falsy(Gov.ranks.ps_deputy.perms.recruit, "deputy cannot recruit")
        T.truthy(Gov.ranks.ps_deputy.perms.monitor)
        T.falsy(Gov.ranks.ps_officer.perms.affairs, "officer has no affairs")
        T.truthy(Gov.ranks.prime_minister.perms.barricadesAdmin, "all = true")
        T.truthy(Gov.ranks.interior_minister.perms.resetData, "ministry inherits commander")
    end)

    T.it("sector commander manages only juniors of their own sector", function()
        local cmd = Gov.ranks.ps_commander
        T.truthy(Gov.covers(cmd, Gov.ranks.ps_deputy))
        T.truthy(Gov.covers(cmd, Gov.ranks.ps_officer))
        T.truthy(Gov.covers(cmd, Gov.ranks.ps_patrol))
        T.falsy(Gov.covers(cmd, Gov.ranks.ps_commander), "same rank")
        T.falsy(Gov.covers(cmd, Gov.ranks.traffic_officer), "other sector")
        T.falsy(Gov.covers(cmd, Gov.ranks.traffic_commander), "other sector commander")
        T.falsy(Gov.covers(cmd, Gov.ranks.interior_minister), "ministry leadership")
        T.falsy(Gov.covers(cmd, Gov.ranks.sector_officer), "other ministry")
        T.falsy(Gov.covers(Gov.ranks.ps_deputy, Gov.ranks.ps_commander), "deputy vs commander")
    end)

    T.it("ministry leadership manages every sector of its ministry only", function()
        local min = Gov.ranks.interior_minister
        T.truthy(Gov.covers(min, Gov.ranks.ps_commander))
        T.truthy(Gov.covers(min, Gov.ranks.traffic_officer))
        T.truthy(Gov.covers(min, Gov.ranks.interior_deputy), "junior minister")
        T.falsy(Gov.covers(Gov.ranks.interior_deputy, min), "deputy vs minister")
        T.falsy(Gov.covers(min, Gov.ranks.sector_officer), "defense sector")
        T.falsy(Gov.covers(min, Gov.ranks.defense_deputy), "other ministry leadership")
        T.falsy(Gov.covers(min, Gov.ranks.prime_deputy), "prime ministry")
    end)

    T.it("prime ministry manages every ministry and sector", function()
        local pm = Gov.ranks.prime_minister
        for _, g in ipairs({ "interior_minister", "defense_minister", "ps_patrol", "traffic_commander", "sector_officer", "prime_deputy" }) do
            T.truthy(Gov.covers(pm, Gov.ranks[g]), g)
        end
        T.falsy(Gov.covers(Gov.ranks.prime_deputy, pm))
    end)

    T.it("pairs each permission with the scope of the same grant", function()
        local p = profile({ "ps_commander", "traffic_officer" })
        T.truthy(Gov.canOnRank(p, "recruit", "ps_officer"))
        T.falsy(Gov.canOnRank(p, "recruit", "traffic_officer"), "recruit must not leak into Traffic")
        T.eq(p.primary.group, "ps_commander")
        T.eq(p.memberSector, "Interior.PublicSecurity")
    end)

    T.it("lists assignable ranks strictly inside the scope", function()
        local groups = Gov.assignableRanks(profile({ "ps_commander" }))
        T.eq(#groups, 1)
        T.eq(groups[1].key, "Interior.PublicSecurity")
        local names = {}
        for _, r in ipairs(groups[1].ranks) do names[#names + 1] = r.group end
        T.eq(table.concat(names, ","), "ps_deputy,ps_officer,ps_patrol")

        local minister = Gov.assignableRanks(profile({ "interior_minister" }))
        local all = {}
        for _, g in ipairs(minister) do for _, r in ipairs(g.ranks) do all[#all + 1] = r.group end end
        T.has(all, "interior_deputy")
        T.has(all, "traffic_commander")
        T.has(all, "ps_patrol")
        T.hasNot(all, "sector_officer")
        T.hasNot(all, "interior_minister")
    end)

    T.it("refuses self-management by default", function()
        local p = profile({ "interior_minister" })
        T.falsy(Gov.canOnTarget(p, "resetData", { ps_officer = true }, 999), "self")
        T.truthy(Gov.canOnTarget(p, "resetData", { ps_officer = true }, 5), "other")
    end)

    T.it("uses the most senior rank of a multi-rank target", function()
        local cmd = profile({ "ps_commander" })
        T.falsy(Gov.canOnTarget(cmd, "dismiss", { ps_officer = true, interior_deputy = true }, 5))
        local covered = Gov.coveredRanks(profile({ "interior_minister" }), "dismiss", { ps_officer = true, traffic_officer = true })
        T.eq(#covered, 2)
    end)

    T.it("supports SameContainer = all / none", function()
        Config.Hierarchy.SameContainer = "all"
        T.truthy(Gov.covers(Gov.ranks.ps_deputy, Gov.ranks.ps_commander))
        Config.Hierarchy.SameContainer = "none"
        T.falsy(Gov.covers(Gov.ranks.ps_commander, Gov.ranks.ps_deputy))
        T.truthy(Gov.covers(Gov.ranks.interior_minister, Gov.ranks.ps_commander), "lower level still covered")
        Config.Hierarchy.SameContainer = "junior"
    end)

    T.it("lets a role remove an inherited permission with false", function()
        Config.Roles.SectorDeputy.permissions.fines = false
        Gov.buildPermissions()
        T.falsy(Gov.ranks.ps_deputy.perms.fines, "removed")
        T.truthy(Gov.ranks.ps_officer.perms.fines, "parent unchanged")
        Config.Roles.SectorDeputy.permissions.fines = nil
        Gov.buildPermissions()
        T.truthy(Gov.ranks.ps_deputy.perms.fines)
    end)

    T.it("computes sector scope sets", function()
        local set = Gov.sectorsFor(profile({ "interior_minister" }), "monitor")
        T.truthy(set["Interior.PublicSecurity"] and set["Interior.Traffic"])
        T.falsy(set["Defense.ExampleSector"])
        local pm = Gov.sectorsFor(profile({ "prime_minister" }), "monitor")
        T.eq(Utils.count(pm), 3)
    end)
end)
