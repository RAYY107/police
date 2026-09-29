local H, T = ...

T.describe("Database schema", function()
    H.boot()

    T.it("ships sql/evora_police.sql identical to the auto-created schema", function()
        local f = assert(io.open("Evora_Police/sql/evora_police.sql"))
        local file = f:read("a")
        f:close()
        local function norm(s) return Utils.trim((s:gsub("%-%-[^\n]*", ""):gsub("%s+", " "):gsub(" ;", ";"))) end
        local expected = {}
        for _, statement in ipairs(Evora.DB.schema) do expected[#expected + 1] = statement .. ";" end
        T.eq(norm(file), norm(table.concat(expected, "\n")), "run: lua5.4 tests/tools/export_schema.lua")
    end)

    T.it("creates every table on start", function()
        local names = {}
        for _, row in ipairs(H.query("SHOW TABLES LIKE 'evora_police_%'")) do
            for _, v in pairs(row) do names[#names + 1] = v end
        end
        T.eq(#names, 12)
    end)

    T.it("imports cleanly on an empty database", function()
        H.db.wipe()
        local f = assert(io.open("Evora_Police/sql/evora_police.sql"))
        local sql = f:read("a")
        f:close()
        for statement in sql:gsub("%-%-[^\n]*", ""):gmatch("[^;]+") do
            if statement:match("%S") then H.db.raw(statement) end
        end
        T.eq(#H.query("SHOW TABLES LIKE 'evora_police_%'"), 12)
    end)
end)
