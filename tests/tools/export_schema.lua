-- Regenerates Evora_Police/sql/evora_police.sql from server/core/database.lua (single source of truth).
Evora, Config = {}, {}
dofile("Evora_Police/server/core/database.lua")
local out = {
    "-- Evora_Police — database schema (Made By LR)",
    "-- The resource creates these tables automatically (Config.Database.AutoCreateTables).",
    "-- Import this file manually only if automatic creation is disabled.",
    "",
}
for _, statement in ipairs(Evora.DB.schema) do
    local text = statement:gsub("\n    ", "\n")
    out[#out + 1] = text .. ";"
    out[#out + 1] = ""
end
local f = assert(io.open("Evora_Police/sql/evora_police.sql", "w"))
f:write(table.concat(out, "\n"))
f:close()
print("wrote " .. #Evora.DB.schema .. " statements")
