-- Virtual-time coroutine scheduler mimicking the FiveM Lua runtime (Citizen.*, SetTimeout, promise).
local S = {}

function S.reset()
    S.now = 0                 -- virtual milliseconds (GetGameTimer)
    S.epoch = 1760000000      -- os.time() at now = 0
    S.threads = {}
    S.timers = {}
    S.errors = {}
    S.seq = 0
end
S.reset()

local function record(err, co)
    local tb = co and debug.traceback(co, tostring(err)) or tostring(err)
    S.errors[#S.errors + 1] = tb
end

local function resume(t, ...)
    local prev = S.current
    S.current = t
    local ok, req = coroutine.resume(t.co, ...)
    S.current = prev
    if not ok then
        record(req, t.co)
        t.dead = true
        return
    end
    if coroutine.status(t.co) == "dead" then
        t.dead = true
        return
    end
    if type(req) == "table" and req.wait then
        t.wake, t.await = S.now + math.max(0, req.wait), nil
    elseif type(req) == "table" and req.await then
        t.wake, t.await = nil, req.await
    else
        t.wake, t.await = S.now, nil
    end
end

local function newThread(fn, ...)
    local t = { co = coroutine.create(fn), args = table.pack(...) }
    return t
end

-- Deferred thread (Citizen.CreateThread)
function S.spawn(fn, ...)
    local t = newThread(fn, ...)
    t.wake = S.now
    t.fresh = true
    S.threads[#S.threads + 1] = t
    return t
end

-- Immediate thread (event handlers / CreateThreadNow)
function S.spawnNow(fn, ...)
    local t = newThread(fn, ...)
    S.threads[#S.threads + 1] = t
    resume(t, table.unpack(t.args, 1, t.args.n))
    return t
end

function S.wait(ms)
    if not coroutine.isyieldable() then error("Citizen.Wait called outside of a thread", 2) end
    coroutine.yield({ wait = ms or 0 })
end

---------------------------------------------------------------------------
-- promise (FiveM ignores resolves with nil and repeated resolves)
---------------------------------------------------------------------------
local Promise = {}
Promise.__index = Promise

function Promise.new()
    return setmetatable({ state = "pending" }, Promise)
end

function Promise:resolve(value)
    if self.state ~= "pending" or value == nil then return end
    self.state = "resolved"
    self.value = value
end

function Promise:reject(err)
    if self.state ~= "pending" then return end
    self.state = "rejected"
    self.value = err
end

S.promise = { new = Promise.new }

function S.await(p)
    if p.state == "pending" then
        if not coroutine.isyieldable() then error("Citizen.Await called outside of a thread", 2) end
        coroutine.yield({ await = p })
    end
    if p.state == "rejected" then error(p.value, 2) end
    return p.value
end

function S.setTimeout(ms, fn)
    S.seq = S.seq + 1
    S.timers[#S.timers + 1] = { at = S.now + math.max(0, ms or 0), fn = fn, seq = S.seq }
end

---------------------------------------------------------------------------
-- Running
---------------------------------------------------------------------------
local function runnable(t)
    if t.dead then return false end
    if t.await then return t.await.state ~= "pending" end
    return t.wake ~= nil and t.wake <= S.now
end

-- Runs everything that is ready at the current virtual time.
function S.settle(maxLoops)
    maxLoops = maxLoops or 100000
    local loops = 0
    local progressed = true
    while progressed do
        progressed = false
        loops = loops + 1
        if loops > maxLoops then error("scheduler did not settle (infinite loop?)") end
        -- timers
        table.sort(S.timers, function(a, b) if a.at ~= b.at then return a.at < b.at end return a.seq < b.seq end)
        while S.timers[1] and S.timers[1].at <= S.now do
            local timer = table.remove(S.timers, 1)
            S.spawnNow(timer.fn)
            progressed = true
        end
        -- threads
        local list = S.threads
        for i = 1, #list do
            local t = list[i]
            if t and runnable(t) then
                if t.fresh then
                    t.fresh = nil
                    resume(t, table.unpack(t.args, 1, t.args.n))
                else
                    resume(t)
                end
                progressed = true
            end
        end
        -- compact
        local alive = {}
        for _, t in ipairs(S.threads) do
            if not t.dead then alive[#alive + 1] = t end
        end
        S.threads = alive
    end
end

-- Advances virtual time by `ms`, running everything that becomes due on the way.
function S.advance(ms)
    local target = S.now + ms
    S.settle()
    while true do
        local nextAt
        for _, t in ipairs(S.threads) do
            if not t.dead and not t.await and t.wake and t.wake > S.now then
                if not nextAt or t.wake < nextAt then nextAt = t.wake end
            end
        end
        for _, timer in ipairs(S.timers) do
            if not nextAt or timer.at < nextAt then nextAt = timer.at end
        end
        if not nextAt or nextAt > target then
            S.now = target
            S.settle()
            return
        end
        S.now = math.max(S.now, nextAt)
        S.settle()
    end
end

function S.time()
    return S.epoch + math.floor(S.now / 1000)
end

return S
