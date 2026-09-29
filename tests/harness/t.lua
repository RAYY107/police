-- Tiny test framework.
local S = require("harness.scheduler")

local T = { passed = 0, failed = 0, failures = {}, suite = "" }

local function fmt(v)
    if type(v) == "string" then return string.format("%q", v) end
    return tostring(v)
end

function T.describe(name, fn)
    T.suite = name
    print("\n\27[1m" .. name .. "\27[0m")
    fn()
end

function T.it(name, fn)
    S.errors = {}
    local H = package.loaded["harness"]
    if H then H.sqlErrors = {} end
    local ok, err = xpcall(fn, debug.traceback)
    if ok and #S.errors > 0 then
        ok, err = false, "thread errors:\n" .. table.concat(S.errors, "\n")
    end
    if ok and H and H.sqlErrors and #H.sqlErrors > 0 then
        ok, err = false, "SQL errors:\n" .. table.concat(H.sqlErrors, "\n")
    end
    if ok then
        T.passed = T.passed + 1
        print("  \27[32m✓\27[0m " .. name)
    else
        T.failed = T.failed + 1
        T.failures[#T.failures + 1] = { suite = T.suite, name = name, err = err }
        print("  \27[31m✗ " .. name .. "\27[0m\n" .. tostring(err):gsub("\n", "\n      "))
    end
end

function T.eq(actual, expected, msg)
    if actual ~= expected then
        error(("%sexpected %s, got %s"):format(msg and (msg .. ": ") or "", fmt(expected), fmt(actual)), 2)
    end
end

function T.truthy(v, msg) if not v then error((msg or "expected a truthy value") .. " (got " .. fmt(v) .. ")", 2) end end
function T.falsy(v, msg) if v then error((msg or "expected a falsy value") .. " (got " .. fmt(v) .. ")", 2) end end

function T.contains(haystack, needle, msg)
    if type(haystack) ~= "string" or not haystack:find(needle, 1, true) then
        error(("%sexpected %s to contain %s"):format(msg and (msg .. ": ") or "", fmt(haystack), fmt(needle)), 2)
    end
end

function T.near(actual, expected, tolerance, msg)
    if type(actual) ~= "number" or math.abs(actual - expected) > tolerance then
        error(("%sexpected %s ± %s, got %s"):format(msg and (msg .. ": ") or "", fmt(expected), fmt(tolerance), fmt(actual)), 2)
    end
end

function T.has(list, value, msg)
    for _, v in ipairs(list or {}) do if v == value then return end end
    error(("%sexpected list to contain %s"):format(msg and (msg .. ": ") or "", fmt(value)), 2)
end

function T.hasNot(list, value, msg)
    for _, v in ipairs(list or {}) do
        if v == value then error(("%sexpected list NOT to contain %s"):format(msg and (msg .. ": ") or "", fmt(value)), 2) end
    end
end

function T.summary()
    print(("\n%d passed, %d failed"):format(T.passed, T.failed))
    return T.failed == 0
end

return T
