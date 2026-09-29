-- Evora_Police test harness: boots the real server scripts (fxmanifest order) against mocked
-- FiveM natives, a mocked vRP and a real MariaDB database.
local S = require("harness.scheduler")
local fivem = require("harness.fivem")
local vrpmock = require("harness.vrp")
local db = require("harness.db")

local H = { root = "Evora_Police/", realOsTime = os.time }
H.S = S
H.db = db
H.joaat = fivem.joaat

local ZW = "\u{200B}"
local GLOBALS = { "Evora", "Config", "Locale", "LocaleUI", "Utils", "L", "module", "source" }

function H.manifest()
    local lists = {}
    local env = setmetatable({}, { __index = function(_, key)
        return function(value)
            lists[key] = value
            return function() end
        end
    end })
    assert(loadfile(H.root .. "fxmanifest.lua", "t", env))()
    return lists
end

function H.load(path)
    local chunk, err = loadfile(H.root .. path, "t", _G)
    if not chunk then error("cannot load " .. path .. ": " .. tostring(err)) end
    local ok, runErr = xpcall(chunk, debug.traceback)
    if not ok then error("error running " .. path .. ": " .. tostring(runErr)) end
end

function H.defaultGroups()
    local groups = {}
    local titles = {
        prime_minister = "رئيس الوزراء", prime_deputy = "نائب رئيس الوزراء",
        interior_minister = "وزير الداخلية", interior_deputy = "نائب وزير الداخلية",
        defense_minister = "وزير الدفاع", defense_deputy = "نائب وزير الدفاع",
        ps_commander = "قائد الأمن العام", ps_deputy = "نائب قائد الأمن العام", ps_officer = "ضابط أمن عام", ps_patrol = "دورية أمن عام",
        traffic_commander = "قائد المرور", traffic_officer = "رجل مرور",
        sector_commander = "قائد القطاع العسكري", sector_officer = "عسكري",
    }
    for g, t in pairs(titles) do groups[g] = { _config = { title = t } } end
    groups.police_vacation = { _config = { title = "إجازة" } }
    groups.taxi = { _config = { title = "سائق تاكسي", gtype = "job" } }
    groups.mechanic = { _config = { title = "ميكانيكي", gtype = "job" } }
    groups.user = { _config = {} }
    return groups
end

function H.defaultCustom()
    return {
        modelhash = fivem.joaat("mp_m_freemode_01"),
        [3] = { 0, 0, 0 }, [4] = { 10, 0, 0 }, [6] = { 5, 0, 0 }, [8] = { 15, 0, 0 }, [11] = { 20, 0, 0 },
        p0 = { -1, 0 },
    }
end

function H.createVrpTables()
    db.raw([[CREATE TABLE IF NOT EXISTS vrp_user_identities (user_id INT PRIMARY KEY, registration VARCHAR(20), firstname VARCHAR(50), name VARCHAR(50))]])
    db.raw([[CREATE TABLE IF NOT EXISTS vrp_user_vehicles (user_id INT, vehicle VARCHAR(100), PRIMARY KEY (user_id, vehicle))]])
    db.raw([[CREATE TABLE IF NOT EXISTS vrp_user_data (user_id INT, dkey VARCHAR(100), dvalue TEXT, PRIMARY KEY (user_id, dkey))]])
end

local function resetGlobals()
    for _, k in ipairs(GLOBALS) do _G[k] = nil end
end

local function loadResource(configure)
    local lists = H.manifest()
    for _, f in ipairs(lists.shared_scripts) do H.load(f) end
    for _, f in ipairs(lists.server_scripts) do
        H.load(f)
        if f == "config/server.lua" and configure then configure(Config) end
    end
    S.settle()
    if not Evora.ready then
        error("Evora did not become ready:\n" .. table.concat(S.errors, "\n"))
    end
end

-- opts: style ("legacy"|"modern"), onesync (bool), configure(fn(Config)), groups
function H.boot(opts)
    opts = opts or {}
    H.opts = opts
    S.reset()
    resetGlobals()
    fivem.install(H)
    fivem.helpers(H)
    H.vrp = vrpmock.install(H, opts.style or "legacy")
    H.vrp.groupsCfg = opts.groups or H.defaultGroups()
    db.install(H)
    db.wipe()
    H.createVrpTables()
    H.sqlErrors = {}
    if opts.onesync == false then H.convars.onesync = "off" end
    H.nextSource = 1
    H.reqId = 0
    loadResource(opts.configure)
    return H
end

-- Resource restart: Lua state and threads are lost, players / vRP / database stay.
function H.restart()
    local keep = {
        players = H.players, entities = H.entities, entitySeq = H.entitySeq, vrp = H.vrp, statebags = H.statebags,
        clientResponders = H.clientResponders, convars = H.convars,
    }
    S.threads, S.timers = {}, {}
    resetGlobals()
    fivem.install(H)
    H.players, H.entities, H.entitySeq, H.statebags = keep.players, keep.entities, keep.entitySeq, keep.statebags
    H.clientResponders, H.convars = keep.clientResponders, keep.convars
    local users, sources, sdata, cfg = keep.vrp.users, keep.vrp.sources, keep.vrp.sdata, keep.vrp.groupsCfg
    H.vrp = vrpmock.install(H, keep.vrp.style)
    H.vrp.users, H.vrp.sources, H.vrp.sdata, H.vrp.groupsCfg = users, sources, sdata, cfg
    db.install(H)
    loadResource(H.opts and H.opts.configure)
end

---------------------------------------------------------------------------
-- Players
---------------------------------------------------------------------------
-- opts: name, groups (list), coords, wallet, bank, inventory, weapons, custom, cuffed
function H.connect(uid, opts)
    opts = opts or {}
    local src = H.nextSource
    H.nextSource = H.nextSource + 1
    local c = opts.coords or { x = 100.0, y = 100.0, z = 30.0 }
    local ped = H.newEntity("ped", c)
    H.players[src] = { name = opts.name or ("Player" .. uid), ped = ped, bucket = 0, identifiers = { "license:lic" .. uid, "discord:" .. (1000 + uid) } }
    local existing = H.vrp.users[uid]
    if existing and not opts.fresh then
        existing.source = src
    else
        local groups = {}
        for _, g in ipairs(opts.groups or {}) do groups[g] = true end
        H.vrp.users[uid] = {
            source = src, groups = groups, inventory = opts.inventory or {}, wallet = opts.wallet or 0, bank = opts.bank or 0,
            weapons = opts.weapons or {}, custom = opts.custom or H.defaultCustom(), cuffed = opts.cuffed == true,
        }
    end
    H.vrp.sources[src] = uid
    TriggerEvent("vRP:playerJoin", uid, src, H.players[src].name, 0)
    TriggerEvent("vRP:playerSpawn", uid, src, true)
    S.settle()
    return src
end

function H.withSource(src, name, ...)
    local args = table.pack(...)
    for _, fn in ipairs(H.handlers[name] or {}) do
        S.spawnNow(function()
            _G.source = src
            fn(table.unpack(args, 1, args.n))
        end)
    end
end

function H.disconnect(src)
    local uid = H.vrp.sources[src]
    H.withSource(src, "playerDropped", "Exiting")
    TriggerEvent("vRP:playerLeave", uid, src)
    S.settle()
    local p = H.players[src]
    if p then H.entities[p.ped] = nil end
    H.players[src] = nil
    H.vrp.sources[src] = nil
    if uid and H.vrp.users[uid] then H.vrp.users[uid].source = nil end
    S.settle()
end

function H.move(src, x, y, z)
    local p = H.players[src]
    H.entities[p.ped].coords = fivem.vector3(x, y, z or 30.0)
end

function H.coords(src)
    local p = H.players[src]
    return H.entities[p.ped].coords
end

function H.user(uid) return H.vrp.users[uid] end

function H.groups(uid)
    local list = {}
    for g in pairs(H.vrp.users[uid].groups) do list[#list + 1] = g end
    table.sort(list)
    return list
end

function H.addVehicle(plate, coords, model)
    return H.newEntity("vehicle", coords, { plate = plate, model = fivem.joaat(model or "adder") })
end

---------------------------------------------------------------------------
-- RPC / confirmations / popups
---------------------------------------------------------------------------
function H.rpcStart(src, name, payload)
    H.reqId = H.reqId + 1
    local id = H.reqId
    H.fromClient(src, "evora_police:rpc", id, name, payload or {})
    S.settle()
    return id
end

function H.rpcResult(src, id)
    for _, e in ipairs(H.sent) do
        if e.name == "evora_police:rpc:res" and e.target == src and e.args[1] == id then
            return true, e.args[2], e.args[3]
        end
    end
    return false
end

function H.rpc(src, name, payload)
    local id = H.rpcStart(src, name, payload)
    local done, ok, data = H.rpcResult(src, id)
    if not done then error("rpc '" .. name .. "' did not answer (waiting on a confirmation?)", 2) end
    return ok, data
end

function H.pendingConfirm(src)
    local open = {}
    local order = {}
    for _, e in ipairs(H.sent) do
        if e.target == src and e.name == "evora_police:confirm:show" then
            open[e.args[1]] = e.args[2]
            order[#order + 1] = e.args[1]
        elseif e.target == src and e.name == "evora_police:confirm:hide" then
            open[e.args[1]] = nil
        end
    end
    for i = #order, 1, -1 do
        if open[order[i]] then return order[i], open[order[i]] end
    end
    return nil
end

function H.confirm(src, accept)
    local id = H.pendingConfirm(src)
    if not id then error("no pending confirmation for source " .. tostring(src), 2) end
    return H.rpc(src, "confirm:answer", { id = id, accepted = accept ~= false })
end

-- Answers for vRP.prompt (Popup type "vrp"), in order. nil = cancel.
function H.prompts(src, list)
    H.vrp.prompts[src] = list
end

---------------------------------------------------------------------------
-- Menus (vRP Builder Menu)
---------------------------------------------------------------------------
local function clean(label)
    return (label:gsub(ZW, ""):gsub("&amp;", "&"):gsub("&lt;", "<"):gsub("&gt;", ">"):gsub("&quot;", '"'))
end
H.clean = clean

function H.mainMenu(src)
    local choices = {}
    for _, builder in ipairs(H.vrp.builders.main or {}) do
        builder(function(c) for k, v in pairs(c or {}) do choices[k] = v end end, { player = src })
    end
    return choices
end

function H.labels(menudata)
    local list = {}
    for k, v in pairs(menudata or {}) do
        if type(v) == "table" and type(v[1]) == "function" then list[#list + 1] = k end
    end
    table.sort(list, function(a, b) return a:upper() < b:upper() end)
    for i, k in ipairs(list) do list[i] = clean(k) end
    return list
end

function H.choose(src, menudata, label)
    for k, v in pairs(menudata or {}) do
        if type(v) == "table" and type(v[1]) == "function" and clean(k) == label then
            v[1](src, k)
            S.settle()
            return true
        end
    end
    error(("menu item '%s' not found in [%s]"):format(label, table.concat(H.labels(menudata), " | ")), 2)
end

function H.menu(src) return H.vrp.menus[src] end

function H.select(src, label) return H.choose(src, H.menu(src), label) end

function H.selectMatching(src, pattern)
    for _, label in ipairs(H.labels(H.menu(src))) do
        if label:find(pattern, 1, true) then return H.select(src, label) end
    end
    error(("no menu item matching '%s' in [%s]"):format(pattern, table.concat(H.labels(H.menu(src)), " | ")), 2)
end

function H.advance(ms) S.advance(ms) end
function H.settle() S.settle() end

function H.notifications(src)
    local list = {}
    for _, c in ipairs(H.vrp.calls) do
        if c.fn == "notify" and c.src == src then list[#list + 1] = c.args[1] end
    end
    return list
end

function H.lastNotification(src)
    local list = H.notifications(src)
    return list[#list]
end

function H.query(sql, params) return db.raw(db.interpolate(sql, params)) end

return H
