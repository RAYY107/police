--[[
    Evora_Police — Government hierarchy & authority engine

        رئاسة الوزراء → الوزارات → القطاعات → الرتب → الصلاحيات → الأفراد

    config/government.lua is compiled into a rank index. A player's profile is the list of
    configured ranks (grants) they hold in vRP. Every scoped check pairs a permission with the
    scope of the SAME grant, so permissions never leak across sectors.
]]

local Gov = {
    ranks = {},         -- [group] = rank
    rankList = {},      -- ranks in display order
    sectors = {},       -- [sectorId] = sector
    sectorList = {},
    ministries = {},    -- [key] = ministry
    ministryList = {},
    prime = nil,
    profiles = {},      -- [user_id] = profile (online players)
}
Evora.Gov = Gov

Gov.PERMISSIONS = {
    "ipad", "clock", "vacation", "militaryCode", "reports", "wanted", "wantedClear", "citizenInquiry",
    "fines", "fineInquiry", "jail", "jailCheck", "jailModify", "jailMonitor", "jailRelease", "field",
    "equipment", "uniforms", "securityAlert", "impound", "impoundInquiry", "impoundRelease", "barricades",
    "barricadesAdmin", "affairs", "broadcastOfficers", "broadcastCitizens",
    "recruit", "dismiss", "recall", "monitor", "vacationBalance", "vacationBreak", "officerInquiry",
    "resetAttendance", "resetFines", "resetData", "statistics",
}
Gov.SCOPED = Utils.toSet({
    "recruit", "dismiss", "recall", "monitor", "vacationBalance", "vacationBreak", "officerInquiry",
    "resetAttendance", "resetFines", "resetData", "statistics",
})
local KNOWN = Utils.toSet(Gov.PERMISSIONS)
local ALIASES = {
    all = Gov.PERMISSIONS,
    broadcast = { "broadcastOfficers", "broadcastCitizens" },
    reset = { "resetAttendance", "resetFines", "resetData" },
}
local LEVEL = { prime = 1, ministry = 2, sector = 3 }
local EMPTY = { grants = {}, perms = {}, isMilitary = false, groups = {} }

---------------------------------------------------------------------------
-- Build
---------------------------------------------------------------------------
local function parseRank(entry)
    if type(entry) == "string" then return entry, nil end
    if type(entry) == "table" then return entry.group or entry[1], entry.label end
    return nil, nil
end

function Gov.build()
    Gov.ranks, Gov.rankList = {}, {}
    Gov.sectors, Gov.sectorList = {}, {}
    Gov.ministries, Gov.ministryList = {}, {}
    Gov.prime = nil

    local g = Config.Government or {}
    local global = 0

    local function addRank(entry, level, ministry, sector, position)
        local group, label = parseRank(entry)
        if type(group) ~= "string" or group == "" then
            Evora.warn("Invalid rank entry in config/government.lua (%s).", tostring(entry))
            return nil
        end
        if Gov.ranks[group] then
            Evora.warn("Group '%s' is listed twice in config/government.lua; the first entry is used.", group)
            return nil
        end
        global = global + 1
        local rank = {
            group = group, customLabel = label, level = level,
            ministry = ministry, sector = sector, order = position, global = global, perms = {},
        }
        Gov.ranks[group] = rank
        Gov.rankList[#Gov.rankList + 1] = rank
        return rank
    end

    local prime = g.PrimeMinistry or g.PrimeMinister
    if type(prime) == "table" then
        Gov.prime = { label = prime.label or "رئاسة الوزراء", ranks = {} }
        for i, entry in ipairs(prime.ranks or {}) do
            local r = addRank(entry, "prime", nil, nil, i)
            if r then Gov.prime.ranks[#Gov.prime.ranks + 1] = r.group end
        end
    end

    local ministries = g.Ministries or {}
    for _, mKey in ipairs(Utils.orderedKeys(ministries)) do
        local m = ministries[mKey]
        local ministry = { key = mKey, label = m.label or mKey, ranks = {}, sectors = {} }
        Gov.ministries[mKey] = ministry
        Gov.ministryList[#Gov.ministryList + 1] = ministry
        for i, entry in ipairs(m.ranks or {}) do
            local r = addRank(entry, "ministry", mKey, nil, i)
            if r then ministry.ranks[#ministry.ranks + 1] = r.group end
        end
        local sectors = m.sectors or {}
        for _, sKey in ipairs(Utils.orderedKeys(sectors)) do
            local s = sectors[sKey]
            local id = mKey .. "." .. sKey
            local sector = { id = id, key = sKey, label = s.label or sKey, ministry = mKey, ranks = {} }
            Gov.sectors[id] = sector
            Gov.sectorList[#Gov.sectorList + 1] = sector
            ministry.sectors[#ministry.sectors + 1] = id
            for i, entry in ipairs(s.ranks or {}) do
                local r = addRank(entry, "sector", mKey, id, i)
                if r then sector.ranks[#sector.ranks + 1] = r.group end
            end
        end
    end

    Gov.buildPermissions()
    Evora.debug("sectors", "%d ministries, %d sectors, %d ranks", #Gov.ministryList, #Gov.sectorList, #Gov.rankList)
end

local function rolePermissions(roleKey, stack)
    local roles = Config.Roles or {}
    local role = roles[roleKey]
    if type(role) ~= "table" then
        Evora.warn("Unknown role '%s' in config/permissions.lua (inherits).", tostring(roleKey))
        return {}
    end
    stack = stack or {}
    if stack[roleKey] then
        Evora.warn("Role inheritance loop detected at '%s'.", roleKey)
        return {}
    end
    stack[roleKey] = true
    local perms = {}
    local parents = role.inherits
    if type(parents) == "string" then parents = { parents } end
    for _, parent in ipairs(parents or {}) do
        for p in pairs(rolePermissions(parent, stack)) do perms[p] = true end
    end
    for key, value in pairs(role.permissions or {}) do
        local list = ALIASES[key] or { key }
        for _, p in ipairs(list) do
            if not KNOWN[p] then
                Evora.warn("Unknown permission '%s' in role '%s'.", tostring(p), roleKey)
            end
            perms[p] = value and true or nil
        end
    end
    stack[roleKey] = nil
    return perms
end

function Gov.buildPermissions()
    for _, rank in pairs(Gov.ranks) do rank.perms = {} end
    for roleKey, role in pairs(Config.Roles or {}) do
        local perms = rolePermissions(roleKey)
        for _, entry in ipairs(role.ranks or {}) do
            local group = parseRank(entry)
            local rank = group and Gov.ranks[group]
            if rank then
                for p in pairs(perms) do rank.perms[p] = true end
            else
                Evora.warn("Role '%s' lists group '%s' which is not part of config/government.lua.", roleKey, tostring(group))
            end
        end
    end
end

function Gov.validateGroups()
    local missing = {}
    for _, rank in ipairs(Gov.rankList) do
        if Evora.Framework.groupExists(rank.group) == false then missing[#missing + 1] = rank.group end
    end
    if #missing > 0 then
        Evora.warn("Groups missing from vrp/cfg/groups.lua: %s", table.concat(missing, ", "))
    end
    local inactive = Config.Vacation and Config.Vacation.InactiveGroup
    if inactive and Evora.Framework.groupExists(inactive) == false then
        Evora.warn("Vacation group '%s' is missing from vrp/cfg/groups.lua.", inactive)
    end
end

---------------------------------------------------------------------------
-- Labels
---------------------------------------------------------------------------
function Gov.rankLabel(group)
    local rank = Gov.ranks[group]
    if rank and rank.customLabel then return rank.customLabel end
    return Evora.Framework.groupTitle(group) or group
end

function Gov.sectorLabel(id)
    local s = id and Gov.sectors[id]
    return s and s.label or ""
end

function Gov.ministryLabel(key)
    local m = key and Gov.ministries[key]
    return m and m.label or ""
end

-- Public description of a rank (used by UI and logs).
function Gov.describeRank(rank)
    if not rank then return nil end
    return {
        group = rank.group,
        label = Gov.rankLabel(rank.group),
        level = rank.level,
        sector = rank.sector or "",
        sectorLabel = rank.sector and Gov.sectorLabel(rank.sector) or "",
        ministry = rank.ministry or "",
        ministryLabel = rank.level == "prime" and (Gov.prime and Gov.prime.label or "") or Gov.ministryLabel(rank.ministry),
    }
end

---------------------------------------------------------------------------
-- Profiles
---------------------------------------------------------------------------
local function sortGrants(a, b)
    if LEVEL[a.level] ~= LEVEL[b.level] then return LEVEL[a.level] < LEVEL[b.level] end
    return a.global < b.global
end

-- groups: set { [group] = true } or list { "group", ... }
function Gov.resolve(groups)
    local grants = {}
    for k, v in pairs(groups or {}) do
        local group = type(k) == "string" and k or v
        local rank = type(group) == "string" and Gov.ranks[group]
        if rank then grants[#grants + 1] = rank end
    end
    table.sort(grants, sortGrants)
    local perms = {}
    local memberSector
    for _, g in ipairs(grants) do
        for p in pairs(g.perms) do perms[p] = true end
        if not memberSector and g.level == "sector" then memberSector = g.sector end
    end
    return {
        grants = grants,
        perms = perms,
        isMilitary = #grants > 0,
        primary = grants[1],
        memberSector = memberSector,
    }
end

local function signature(profile)
    local parts = {}
    for _, g in ipairs(profile.grants or {}) do parts[#parts + 1] = g.group end
    return table.concat(parts, ",")
end

-- fresh = true re-reads the vRP groups (always used for sensitive actions).
function Gov.getProfile(user_id, fresh)
    user_id = tonumber(user_id)
    if not user_id then return EMPTY end
    local cached = Gov.profiles[user_id]
    if cached and not fresh then return cached end
    local groups = Evora.Framework.getUserGroups(user_id)
    local profile = Gov.resolve(groups)
    profile.user_id = user_id
    profile.groups = groups
    if Evora.Players.isOnline(user_id) then
        Gov.profiles[user_id] = profile
        if (cached and signature(cached) or "") ~= signature(profile) then
            Evora.debug("permissions", "profile of %d → [%s]", user_id, signature(profile))
            Evora.emit("profileChanged", user_id, profile, cached)
        end
    end
    return profile
end

-- Cached profile (never yields). Used by menu builders and lists.
function Gov.cached(user_id)
    return Gov.profiles[tonumber(user_id)] or EMPTY
end

function Gov.forget(user_id)
    Gov.profiles[tonumber(user_id)] = nil
end

-- Military groups (hierarchy ranks) from a set or list of groups, most senior first.
function Gov.militaryGroups(groups)
    local list = {}
    for _, g in ipairs(Gov.resolve(groups).grants) do list[#list + 1] = g.group end
    return list
end

---------------------------------------------------------------------------
-- Permissions & scope
---------------------------------------------------------------------------
function Gov.has(profile, perm)
    return profile ~= nil and profile.perms ~= nil and profile.perms[perm] == true
end

function Gov.hasAny(profile, perm)
    if type(perm) == "table" then
        for _, p in ipairs(perm) do
            if Gov.has(profile, p) then return true end
        end
        return false
    end
    return Gov.has(profile, perm)
end

local function sameContainer(a, b)
    if a.level ~= b.level then return false end
    if a.level == "prime" then return true end
    if a.level == "ministry" then return a.ministry == b.ministry end
    return a.sector == b.sector
end

local function sameContainerAllowed(src, tgt)
    local mode = (Config.Hierarchy and Config.Hierarchy.SameContainer) or "junior"
    if mode == "all" then return true end
    if mode == "none" then return false end
    return tgt.order > src.order
end

-- Does grant `src` cover rank `tgt`?
function Gov.covers(src, tgt)
    if not src or not tgt then return false end
    if sameContainer(src, tgt) then return sameContainerAllowed(src, tgt) end
    if src.level == "prime" then
        return tgt.level ~= "prime"
    elseif src.level == "ministry" then
        return tgt.level == "sector" and tgt.ministry == src.ministry
    end
    return false
end

function Gov.coversSector(grant, sectorId)
    local sector = sectorId and Gov.sectors[sectorId]
    if not grant or not sector then return false end
    if grant.level == "prime" then return true end
    if grant.level == "ministry" then return sector.ministry == grant.ministry end
    return grant.sector == sectorId
end

-- Can the profile use `perm` on the given rank (group name or rank table)?
function Gov.canOnRank(profile, perm, target)
    local rank = type(target) == "string" and Gov.ranks[target] or target
    if not rank or not profile or not profile.grants then return false end
    for _, g in ipairs(profile.grants) do
        if g.perms[perm] and Gov.covers(g, rank) then return true end
    end
    return false
end

-- Can the profile use `perm` on a user whose military groups are `targetGroups`?
-- The target's most senior rank must be covered. Self-management is refused by default.
function Gov.canOnTarget(profile, perm, targetGroups, targetUserId)
    if targetUserId and profile and targetUserId == profile.user_id
        and not (Config.Hierarchy and Config.Hierarchy.AllowSelfManagement) then
        return false
    end
    local target = Gov.resolve(targetGroups)
    if not target.primary then return false end
    return Gov.canOnRank(profile, perm, target.primary)
end

-- Ranks of the target that the profile may act on with `perm` (used for dismissal).
function Gov.coveredRanks(profile, perm, targetGroups)
    local list = {}
    for _, rank in ipairs(Gov.resolve(targetGroups).grants) do
        if Gov.canOnRank(profile, perm, rank) then list[#list + 1] = rank.group end
    end
    return list
end

-- Set of sector ids where the profile may use `perm`.
function Gov.sectorsFor(profile, perm)
    local set = {}
    for _, g in ipairs(profile and profile.grants or {}) do
        if g.perms[perm] then
            for id in pairs(Gov.sectors) do
                if Gov.coversSector(g, id) then set[id] = true end
            end
        end
    end
    return set
end

-- Ranks the profile may assign with "recruit", grouped for the UI.
function Gov.assignableRanks(profile)
    local groups = {}
    local index = {}
    for _, rank in ipairs(Gov.rankList) do
        if Gov.canOnRank(profile, "recruit", rank) then
            local key, label
            if rank.level == "sector" then
                key, label = rank.sector, Gov.ministryLabel(rank.ministry) .. " — " .. Gov.sectorLabel(rank.sector)
            elseif rank.level == "ministry" then
                key, label = "ministry:" .. rank.ministry, Gov.ministryLabel(rank.ministry)
            else
                key, label = "prime", Gov.prime and Gov.prime.label or ""
            end
            if not index[key] then
                index[key] = { key = key, label = label, ranks = {} }
                groups[#groups + 1] = index[key]
            end
            table.insert(index[key].ranks, { group = rank.group, label = Gov.rankLabel(rank.group) })
        end
    end
    return groups
end

-- Short description of a profile for UI / state sync.
function Gov.summary(profile)
    local p = profile and profile.primary
    local d = p and Gov.describeRank(p) or {}
    local perms = {}
    for k in pairs(profile and profile.perms or {}) do perms[#perms + 1] = k end
    table.sort(perms)
    return {
        military = profile ~= nil and profile.isMilitary == true,
        rank = d.label or "",
        group = d.group or "",
        level = d.level or "",
        sector = profile and profile.memberSector or d.sector or "",
        sectorLabel = profile and profile.memberSector and Gov.sectorLabel(profile.memberSector) or d.sectorLabel or "",
        ministryLabel = d.ministryLabel or "",
        permissions = perms,
    }
end
