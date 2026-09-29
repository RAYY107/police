--[[
    Evora_Police — logging (database + Discord webhooks). Server only.

    Logs.add(category, action, {
        actor = user_id, target = user_id,          -- names are resolved as FiveM names
        fields = { { "label", "value" }, ... },
        description = "...",
    })
]]

local Logs = {}
Evora.Logs = Logs

local COLORS = {
    general = 0x8B5CF6, recruitment = 0x22C55E, affairs = 0x8B5CF6, attendance = 0x38BDF8,
    reports = 0xF59E0B, wanted = 0xEF4444, fines = 0xF97316, jail = 0xA855F7, impound = 0x3B82F6,
    field = 0x14B8A6, security = 0xDC2626, statistics = 0xEAB308,
}

local MAX_QUEUE = 250
local queue = {}
local pumping = false

local function clip(s, n)
    s = tostring(s or "")
    if Utils.utf8len(s) > n then return Utils.utf8sub(s, 1, n - 1) .. "…" end
    return s
end

-- Player supplied text must never ping or format in Discord.
local function discordSafe(s)
    s = tostring(s or "")
    if Config.Webhooks and Config.Webhooks.mentionless ~= false then
        s = s:gsub("@", "@\u{200B}")
    end
    s = s:gsub("`", "'")
    return s
end
Logs.discordSafe = discordSafe

local function urlFor(category)
    local hooks = Config.Webhooks
    if not hooks or hooks.enabled == false then return nil end
    local url = hooks[category]
    if type(url) ~= "string" or url == "" then url = hooks.general end
    if type(url) ~= "string" or url == "" then return nil end
    return url
end

local function pump()
    if pumping then return end
    pumping = true
    Evora.thread(function()
        while #queue > 0 do
            local item = table.remove(queue, 1)
            local p = promise.new()
            local finished = false
            PerformHttpRequest(item.url, function(status, body, headers)
                if finished then return end
                finished = true
                p:resolve({ status = status, body = body })
            end, "POST", item.body, { ["Content-Type"] = "application/json" })
            SetTimeout(15000, function()
                if finished then return end
                finished = true
                p:resolve({ status = 0 })
            end)
            local r = Citizen.Await(p)
            if r.status == 429 then
                local retry = 2.0
                local ok, decoded = pcall(json.decode, r.body or "")
                if ok and type(decoded) == "table" and tonumber(decoded.retry_after) then
                    retry = tonumber(decoded.retry_after)
                    if retry > 100 then retry = retry / 1000 end
                end
                item.tries = (item.tries or 0) + 1
                if item.tries <= 3 then table.insert(queue, 1, item) end
                Citizen.Wait(math.floor(math.max(retry, 0.5) * 1000))
            else
                if r.status and r.status >= 400 then
                    Evora.debug("integrations", "webhook responded %s", tostring(r.status))
                end
                Citizen.Wait(700)
            end
        end
        pumping = false
    end)
end

-- Sends a raw embed to the webhook of a category.
function Logs.webhook(category, embed)
    local url = urlFor(category)
    if not url then return end
    local hooks = Config.Webhooks
    embed.color = embed.color or COLORS[category] or COLORS.general
    embed.footer = { text = hooks.footer or "Evora_Police • Made By LR" }
    embed.timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ")
    if embed.title then embed.title = clip(embed.title, 250) end
    if embed.description then embed.description = clip(embed.description, 4000) end
    local payload = { username = hooks.username or "Evora_Police", embeds = { embed } }
    if type(hooks.avatar) == "string" and hooks.avatar ~= "" then payload.avatar_url = hooks.avatar end
    if #queue >= MAX_QUEUE then table.remove(queue, 1) end
    queue[#queue + 1] = { url = url, body = json.encode(payload) }
    pump()
end

local function who(user_id, name)
    return ("%s | ID: %s"):format(discordSafe(name or Evora.Players.name(user_id)), tostring(user_id))
end
Logs.who = who

function Logs.add(category, action, entry)
    entry = entry or {}
    local now = Evora.now()
    local actorId = tonumber(entry.actor) or 0
    local targetId = tonumber(entry.target) or 0
    local actorName = actorId > 0 and (entry.actorName or Evora.Players.name(actorId)) or ""
    local targetName = targetId > 0 and (entry.targetName or Evora.Players.name(targetId)) or ""
    local title = entry.title or L("log_" .. action)

    local details = {}
    for _, f in ipairs(entry.fields or {}) do
        details[#details + 1] = { tostring(f[1]), tostring(f[2]) }
    end
    if entry.description then details[#details + 1] = { "description", tostring(entry.description) } end

    if Config.Logs and Config.Logs.Database ~= false and Evora.DB.ready then
        Evora.DB.executeAsync(
            "INSERT INTO evora_police_logs (category, action, actor_id, actor_name, target_id, target_name, details, created_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
            { category, action, actorId, actorName, targetId, targetName, json.encode(details), now }
        )
    end

    if Config.Logs and Config.Logs.Console then
        Evora.print("[%s] %s — %s → %s", category, action, actorName ~= "" and who(actorId, actorName) or "-", targetName ~= "" and who(targetId, targetName) or "-")
    end

    local fields = {}
    if actorId > 0 then fields[#fields + 1] = { name = entry.actorLabel or L("log_field_actor"), value = who(actorId, actorName), inline = true } end
    if targetId > 0 then fields[#fields + 1] = { name = entry.targetLabel or L("log_field_target"), value = who(targetId, targetName), inline = true } end
    for _, f in ipairs(entry.fields or {}) do
        if #fields >= 24 then break end
        local value = tostring(f[2] == nil and "-" or f[2])
        if value == "" then value = "-" end
        fields[#fields + 1] = { name = clip(f[1], 250), value = clip(discordSafe(value), 1000), inline = f[3] == true }
    end

    Logs.webhook(category, {
        title = title,
        description = entry.description and discordSafe(entry.description) or nil,
        fields = fields,
    })
end
