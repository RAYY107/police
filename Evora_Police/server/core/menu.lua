--[[
    Evora_Police — menu abstraction

    Menus are plain data built on the server:
        { title = "...", items = { { label, description, action = function(source) end } }, parent = function(source) end }
    Rendered with the vRP Builder Menu (vRP.openMenu) or the Evora NUI menu (builtin).
    Item actions always run in a fresh thread, never inside vRP's callback.
]]

local Menu = { sessions = {}, token = 0 }
Evora.Menu = Menu

local ZW = "\u{200B}"

local function cfg()
    return (Config.Integrations and Config.Integrations.BuilderMenu) or {}
end

function Menu.mode()
    local t = cfg().type or "vrp"
    if t == "vrp" and not Evora.Framework.available then return "builtin" end
    return t
end

-- vRP sorts choices alphabetically; prefixes keep Evora's order.
local function orderedLabel(index, label)
    local ordering = cfg().ordering or "invisible"
    if ordering == "numbers" then return index .. ". " .. label end
    if ordering == "invisible" then return string.rep(ZW, index) .. label end
    return label
end

local function runAction(source, item)
    if type(item.action) ~= "function" then return end
    Evora.thread(item.action, source)
end

local function renderVrp(source, menu)
    local data = {
        name = Utils.escapeHtml(menu.title or "Evora"),
        css = { top = "75px", header_color = cfg().headerColor or "rgba(124, 58, 237, 0.80)" },
    }
    local count = 0
    local function add(item)
        count = count + 1
        local label = orderedLabel(count, Utils.escapeHtml(item.label))
        while data[label] do label = label .. ZW end
        data[label] = {
            function(player) runAction(player, item) end,
            Utils.escapeHtml(item.description or ""),
        }
    end
    for _, item in ipairs(menu.items or {}) do add(item) end
    if menu.parent then
        add({ label = L("menu_back"), description = "", action = function(src) Menu.open(src, menu.parent(src)) end })
    end
    Evora.Framework.openMenu(source, data)
end

local function renderBuiltin(source, menu)
    Menu.token = Menu.token + 1
    local token = Menu.token
    Menu.sessions[source] = { token = token, menu = menu }
    local items = {}
    for i, item in ipairs(menu.items or {}) do
        items[i] = { label = item.label, description = item.description or "", icon = item.icon }
    end
    TriggerClientEvent("evora_police:menu:open", source, token, {
        title = menu.title or "Evora",
        subtitle = menu.subtitle,
        items = items,
        back = menu.parent ~= nil,
    })
end

function Menu.open(source, menu)
    if not source or type(menu) ~= "table" then return end
    if #(menu.items or {}) == 0 and not menu.parent then
        Evora.notify(source, "menu_empty", nil, "info")
        return
    end
    if Menu.mode() == "vrp" then
        renderVrp(source, menu)
    else
        renderBuiltin(source, menu)
    end
end

function Menu.close(source)
    if Menu.mode() == "vrp" then
        Evora.Framework.closeMenu(source)
    else
        Menu.sessions[source] = nil
        TriggerClientEvent("evora_police:menu:close", source)
    end
end

function Menu.forget(source)
    Menu.sessions[source] = nil
end

---------------------------------------------------------------------------
-- Builtin menu callbacks
---------------------------------------------------------------------------
Evora.RPC.register("menu:select", {}, function(ctx, data)
    local session = Menu.sessions[ctx.source]
    if not session or session.token ~= Utils.toInt(data.token) then return nil, L("err_invalid_request") end
    local item = session.menu.items and session.menu.items[Utils.toInt(data.index) or 0]
    if not item then return nil, L("err_invalid_request") end
    runAction(ctx.source, item)
    return true
end)

Evora.RPC.register("menu:back", {}, function(ctx, data)
    local session = Menu.sessions[ctx.source]
    if not session or session.token ~= Utils.toInt(data.token) then return nil, L("err_invalid_request") end
    if session.menu.parent then
        local parent = session.menu.parent
        Evora.thread(function() Menu.open(ctx.source, parent(ctx.source)) end)
    else
        Menu.sessions[ctx.source] = nil
    end
    return true
end)

Evora.RPC.register("menu:close", {}, function(ctx)
    Menu.sessions[ctx.source] = nil
    return true
end)

---------------------------------------------------------------------------
-- Main menu entries ("الشرطة", "إبلاغ عن مجرم")
--   builder(source) → items. Must not yield (cached data only).
---------------------------------------------------------------------------
local mainBuilder = nil

function Menu.registerMain(builder)
    mainBuilder = builder
    if Menu.mode() ~= "vrp" then return end
    Evora.Framework.registerMenuBuilder(cfg().menu or "main", function(add, data)
        local source = type(data) == "table" and tonumber(data.player) or nil
        local choices = {}
        if source then
            local ok, items = pcall(builder, source)
            if ok and type(items) == "table" then
                for _, item in ipairs(items) do
                    local label = Utils.escapeHtml(item.label)
                    choices[label] = {
                        function(player) runAction(player, item) end,
                        Utils.escapeHtml(item.description or ""),
                    }
                end
            elseif not ok then
                Evora.error("main menu builder failed: %s", tostring(items))
            end
        end
        add(choices)
    end)
end

-- Builtin mode: the client key / command asks for the main menu.
Evora.RPC.register("menu:main", {}, function(ctx)
    if Menu.mode() == "vrp" or not mainBuilder then return nil, L("err_invalid_request") end
    local items = mainBuilder(ctx.source) or {}
    Menu.open(ctx.source, { title = Config.UI.Brand or "Evora", items = items })
    return true
end)
