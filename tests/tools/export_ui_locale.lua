-- Prints the NUI init payload (LocaleUI + UI config) as JSON, for the NUI preview tests.
package.path = "tests/?.lua;" .. package.path
local json = require("harness.json")
vector3 = function(x, y, z) return { x = x, y = y, z = z } end
Config = {}
for _, f in ipairs({ "config", "government", "permissions", "fines", "jail", "impound", "field", "equipment", "uniforms", "security", "integrations", "locale" }) do
    dofile("Evora_Police/config/" .. f .. ".lua")
end
io.write(json.encode({
    locale = LocaleUI,
    ui = Config.UI,
    confirm = { accept = Config.Confirm.AcceptLabel, reject = Config.Confirm.RejectLabel },
    broadcast = Config.Broadcast.Style,
    spectate = { key = Config.Spectate.StopKeyLabel },
    wanted = Config.Wanted.QuickOpen,
    vacation = { durations = Config.Vacation.Durations },
}))
