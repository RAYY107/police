--[[
    Evora_Police — fines (المخالفات)

    A fine is recorded only after the target accepts it (F5). Unpaid fines are paid at a
    payment point (server validates the player's position) or charged immediately (AutoCharge).
]]

local Fines = { lastIssue = {}, paying = {} }
Evora.Fines = Fines

local DB, P, Gov, Logs, Officers, Confirm, Targets, RPC =
    Evora.DB, Evora.Players, Evora.Gov, Evora.Logs, Evora.Officers, Evora.Confirm, Evora.Targets, Evora.RPC
local I = Evora.Integrations

local function cfg() return Config.Fines or {} end

function Fines.categories()
    local list = {}
    for _, cat in ipairs(cfg().Categories or {}) do
        if cat.enabled ~= false then
            local fines = {}
            for _, f in ipairs(cat.fines or {}) do
                if f.enabled ~= false then fines[#fines + 1] = f end
            end
            if #fines > 0 then list[#list + 1] = { id = cat.id, label = cat.label, fines = fines } end
        end
    end
    return list
end

function Fines.find(categoryId, fineId)
    for _, cat in ipairs(Fines.categories()) do
        if cat.id == categoryId then
            for _, f in ipairs(cat.fines) do
                if f.id == fineId then return cat, f end
            end
        end
    end
    return nil, nil
end

local function officerAllowed(user_id)
    local profile = Gov.getProfile(user_id, true)
    if not Evora.feature("Fines") or not Gov.has(profile, "fines") then return false, L("err_no_permission") end
    if not Officers.dutyOk(user_id, "fines") then return false, L("err_not_on_duty") end
    return true
end
Fines.officerAllowed = officerAllowed

function Fines.issue(officerSrc, categoryId, fineId, targetSrc, targetId)
    local officerId = P.getUserId(officerSrc)
    if not officerId then return end
    local ok, err = officerAllowed(officerId)
    if not ok then return Evora.notify(officerSrc, err, nil, "error") end
    local cat, fine = Fines.find(categoryId, fineId)
    if not fine then return Evora.notify(officerSrc, "err_invalid_request", nil, "error") end
    if targetId == officerId then return Evora.notify(officerSrc, "target_self", nil, "error") end
    local now = GetGameTimer()
    if Fines.lastIssue[officerId] and now - Fines.lastIssue[officerId] < (cfg().Cooldown or 5) * 1000 then
        return Evora.notify(officerSrc, "err_cooldown", nil, "error")
    end
    ok, err = Targets.check(officerSrc, targetSrc, targetId)
    if not ok then return Evora.notify(officerSrc, err, nil, "error") end
    Fines.lastIssue[officerId] = now

    local officerName, targetName = P.name(officerId), P.name(targetId)
    Evora.notify(officerSrc, "confirm_waiting", { name = targetName }, "info")
    local accepted, reason = Confirm.forAction("fine", officerSrc, targetSrc, {
        title = L("confirm_fine_title"),
        message = L("confirm_fine_msg", { officer = officerName, officer_id = officerId }),
        details = {
            { L("field_category"), cat.label },
            { L("field_fine"), fine.label },
            { L("field_amount"), "$" .. Utils.money(fine.amount) },
            { L("field_description"), fine.description or "-" },
        },
        timeout = cfg().ConfirmTimeout,
        icon = "fine",
    })
    if not accepted then
        Evora.notify(officerSrc, Confirm.failMessage(reason), nil, "error")
        if reason == "rejected" then
            Logs.add("fines", "fine_rejected", { actor = officerId, target = targetId, fields = { { L("field_fine"), fine.label } } })
        end
        return
    end

    -- Re-validate after the wait: officer still authorised and target still connected.
    ok, err = officerAllowed(officerId)
    if not ok then return Evora.notify(officerSrc, err, nil, "error") end
    if P.bySource[targetSrc] ~= targetId then return Evora.notify(officerSrc, "err_target_offline", nil, "error") end

    local created = Evora.now()
    local id = DB.insert(
        "INSERT INTO evora_police_fines (target_id, target_name, officer_id, officer_name, category, category_label, fine_id, label, amount, status, created_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 'unpaid', ?)",
        { targetId, targetName, officerId, officerName, cat.id, cat.label, fine.id, fine.label, fine.amount, created }
    )
    if not id then return Evora.notify(officerSrc, "err_internal", nil, "error") end
    Officers.increment(officerId, "fines_issued", 1)

    local paid = false
    if cfg().AutoCharge and I.Money.pay(targetId, fine.amount, cfg().PaymentMethod) then
        DB.execute("UPDATE evora_police_fines SET status = 'paid', paid_at = ? WHERE id = ?", { created, id })
        paid = true
    end

    local vars = { officer = officerName, officer_id = officerId, target = targetName, target_id = targetId, amount = Utils.money(fine.amount), label = fine.label }
    Evora.notify(officerSrc, "fine_issued_officer", vars, "success")
    Evora.notify(targetSrc, paid and "fine_issued_target_paid" or "fine_issued_target", vars, "warning", 10)
    I.Chat.announce("Fine", vars, { officerSrc, targetSrc })
    Logs.add("fines", "fine_issue", {
        actor = officerId, target = targetId, actorName = officerName, targetName = targetName,
        fields = {
            { L("field_fine"), fine.label, true },
            { L("field_category"), cat.label, true },
            { L("field_amount"), "$" .. Utils.money(fine.amount), true },
            { L("log_field_fine_id"), "#" .. id, true },
            { L("log_field_status"), paid and L("fine_status_paid") or L("fine_status_unpaid"), true },
        },
    })
end

---------------------------------------------------------------------------
-- Menus
---------------------------------------------------------------------------
-- Menu builders return menu tables; `parent(source)` returns the parent menu table.
function Fines.rootMenu(source, parent)
    local items = {}
    for _, cat in ipairs(Fines.categories()) do
        items[#items + 1] = {
            label = cat.label,
            description = L("fines_count", { count = #cat.fines }),
            action = function(src) Evora.Menu.open(src, Fines.categoryMenu(src, cat.id, parent)) end,
        }
    end
    return { title = L("menu_fines"), items = items, parent = parent }
end

function Fines.categoryMenu(source, categoryId, parent)
    local items, title = {}, L("menu_fines")
    for _, cat in ipairs(Fines.categories()) do
        if cat.id == categoryId then
            title = cat.label
            for _, fine in ipairs(cat.fines) do
                items[#items + 1] = {
                    label = ("%s — $%s"):format(fine.label, Utils.money(fine.amount)),
                    description = fine.description or "",
                    action = function(src)
                        local ok, err = officerAllowed(P.getUserId(src))
                        if not ok then return Evora.notify(src, err, nil, "error") end
                        Targets.pick(src, L("target_pick_title"), function(targetSrc, targetId)
                            Fines.issue(src, cat.id, fine.id, targetSrc, targetId)
                        end, function(s) return Fines.categoryMenu(s, categoryId, parent) end)
                    end,
                }
            end
        end
    end
    return { title = title, items = items, parent = function(s) return Fines.rootMenu(s, parent) end }
end

function Fines.openMenu(source, parent)
    local ok, err = officerAllowed(P.getUserId(source))
    if not ok then return Evora.notify(source, err, nil, "error") end
    Evora.Menu.open(source, Fines.rootMenu(source, parent))
end

---------------------------------------------------------------------------
-- Inquiry (استعلام عن مخالفات)
---------------------------------------------------------------------------
function Fines.list(target_id)
    local rows = DB.query(
        "SELECT * FROM evora_police_fines WHERE target_id = ? ORDER BY (status = 'unpaid') DESC, id DESC LIMIT " .. (cfg().InquiryLimit or 50),
        { target_id }
    )
    local list, unpaidTotal, unpaidCount = {}, 0, 0
    for _, f in ipairs(rows) do
        local unpaid = f.status == "unpaid"
        if unpaid then
            unpaidTotal = unpaidTotal + (tonumber(f.amount) or 0)
            unpaidCount = unpaidCount + 1
        end
        list[#list + 1] = {
            id = tonumber(f.id), category = f.category_label, label = f.label, amount = tonumber(f.amount),
            officer = { id = tonumber(f.officer_id), name = f.officer_name }, createdAt = tonumber(f.created_at),
            paidAt = tonumber(f.paid_at), status = f.status,
        }
    end
    return { list = list, unpaidTotal = unpaidTotal, unpaidCount = unpaidCount }
end

function Fines.inquiryFlow(source)
    local user_id = P.getUserId(source)
    if not user_id then return end
    local profile = Gov.getProfile(user_id, true)
    if not Gov.has(profile, "fineInquiry") then return Evora.notify(source, "err_no_permission", nil, "error") end
    if not Officers.dutyOk(user_id, "inquiries") then return Evora.notify(source, "err_not_on_duty", nil, "error") end
    local values = I.Popup.input(source, L("fine_inquiry_title"), {
        { key = "id", label = L("field_citizen_id"), type = "number", min = 1 },
    })
    if not values then return Evora.notify(source, "action_cancelled", nil, "info") end
    if not P.exists(values.id) then return Evora.notify(source, "err_unknown_id", nil, "error") end
    local data = Fines.list(values.id)
    data.user_id = values.id
    data.name = P.name(values.id)
    Evora.ui(source, "panel", { kind = "fines", title = L("fine_inquiry_title"), data = data })
    Logs.add("fines", "fine_inquiry", { actor = user_id, target = values.id })
end

---------------------------------------------------------------------------
-- Payment points
---------------------------------------------------------------------------
function Fines.nearPoint(source)
    local coords = P.coords(source)
    if not coords then return nil end
    for _, point in ipairs(cfg().PaymentPoints or {}) do
        if Utils.dist(coords, point.coords) <= (point.radius or 1.5) + 2.0 then return point end
    end
    return nil
end

function Fines.openPayment(source, user_id)
    if not Fines.nearPoint(source) then return nil, L("fine_point_far") end
    local data = Fines.list(user_id)
    local unpaid = {}
    for _, f in ipairs(data.list) do
        if f.status == "unpaid" then unpaid[#unpaid + 1] = f end
    end
    return { list = unpaid, total = data.unpaidTotal, count = data.unpaidCount }
end

RPC.register("fines:pay", { feature = "Fines", cooldown = 1500 }, function(ctx, data)
    if not Fines.nearPoint(ctx.source) then return nil, L("fine_point_far") end
    if Fines.paying[ctx.user_id] then return nil, L("err_cooldown") end
    Fines.paying[ctx.user_id] = true
    local ok, result, err = pcall(function()
        local ids = {}
        if data.all == true then
            for _, row in ipairs(DB.query("SELECT id FROM evora_police_fines WHERE target_id = ? AND status = 'unpaid'", { ctx.user_id })) do
                ids[#ids + 1] = tonumber(row.id)
            end
        elseif type(data.ids) == "table" then
            for i = 1, math.min(#data.ids, 100) do
                local id = Utils.toInt(data.ids[i])
                if id then ids[#ids + 1] = id end
            end
        end
        if #ids == 0 then return nil, L("fine_none_selected") end
        local marks = string.rep("?, ", #ids):sub(1, -3)
        local params = { ctx.user_id }
        for _, id in ipairs(ids) do params[#params + 1] = id end
        local rows = DB.query("SELECT id, amount FROM evora_police_fines WHERE target_id = ? AND status = 'unpaid' AND id IN (" .. marks .. ")", params)
        if #rows == 0 then return nil, L("fine_none_selected") end
        local total, payIds = 0, {}
        for _, r in ipairs(rows) do
            total = total + (tonumber(r.amount) or 0)
            payIds[#payIds + 1] = tonumber(r.id)
        end
        if not I.Money.pay(ctx.user_id, total, cfg().PaymentMethod) then return nil, L("fine_no_money", { amount = Utils.money(total) }) end
        local marks2 = string.rep("?, ", #payIds):sub(1, -3)
        local params2 = { Evora.now(), ctx.user_id }
        for _, id in ipairs(payIds) do params2[#params2 + 1] = id end
        DB.execute("UPDATE evora_police_fines SET status = 'paid', paid_at = ? WHERE target_id = ? AND status = 'unpaid' AND id IN (" .. marks2 .. ")", params2)
        Logs.add("fines", "fine_paid", { actor = ctx.user_id, fields = {
            { L("field_amount"), "$" .. Utils.money(total), true }, { L("log_field_count"), #payIds, true },
        } })
        Evora.notify(ctx.source, "fine_paid", { amount = Utils.money(total), count = #payIds }, "success")
        return Fines.openPayment(ctx.source, ctx.user_id) or { list = {}, total = 0, count = 0 }
    end)
    Fines.paying[ctx.user_id] = nil
    if not ok then
        Evora.error("fines:pay failed: %s", tostring(result))
        return nil, L("err_internal")
    end
    return result, err
end)

RPC.register("fines:open", { feature = "Fines", cooldown = 1000 }, function(ctx)
    local data, err = Fines.openPayment(ctx.source, ctx.user_id)
    if not data then return nil, err end
    return data
end)
