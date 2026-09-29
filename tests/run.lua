-- Usage (from the repository root):  lua5.4 tests/run.lua [spec-name ...]
package.path = "tests/?.lua;tests/?/init.lua;" .. package.path

local H = require("harness")
package.loaded["harness"] = H
local T = require("harness.t")

local specs = {
    "hierarchy", "rpc", "duty", "vacation", "affairs", "reports_wanted", "fines", "jail",
    "field", "impound", "security", "barricades", "conventions", "schema",
}
local only = {}
for _, a in ipairs(arg) do only[a] = true end

for _, name in ipairs(specs) do
    if next(only) == nil or only[name] then
        local chunk = assert(loadfile("tests/specs/" .. name .. "_spec.lua"))
        chunk(H, T)
    end
end

os.exit(T.summary() and 0 or 1)
