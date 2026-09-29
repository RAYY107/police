--[[
    Evora_Police — SERVER ONLY configuration

    This file is loaded as a server script and is never downloaded by clients.
    Keep every secret (webhooks, tokens, API keys) here.
]]

Config.Webhooks = {
    enabled = true,

    general = "",       -- fallback for every empty category below

    recruitment = "",   -- توظيف / فصل
    affairs = "",       -- broadcasts, recall, monitoring, resets, vacations
    attendance = "",    -- clock in / clock out
    reports = "",       -- citizen reports
    wanted = "",        -- wanted notices
    fines = "",         -- fines and payments
    jail = "",          -- jail, modifications, releases, escapes, tasks
    impound = "",       -- vehicle impound and releases
    field = "",         -- field actions, weapons, contraband, searches, inquiries
    security = "",      -- security alerts and barricades
    statistics = "",    -- Top 10 reports

    username = "Evora_Police",
    avatar = "",
    footer = "Evora_Police • Made By LR",
    mentionless = true, -- strip @everyone / @here from player supplied text
}

Config.Logs = {
    Database = true,    -- keep every log in the evora_police_logs table
    Console = false,    -- also print logs to the server console
}

Config.Secrets = {
    DiscordBotToken = "", -- only for Config.Integrations.ProfileImage.type = "discord"
    SteamApiKey = "",     -- only for Config.Integrations.ProfileImage.type = "steam"
}
