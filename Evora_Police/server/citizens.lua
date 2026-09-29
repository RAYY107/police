--[[
    Evora_Police — citizen inquiry (استعلام عن مواطن)

    Shows the FiveM name, vRP id, job, profile image, fines and wanted status. Character names
    are never used.
]]

local Citizens = {}
Evora.Citizens = Citizens

local DB, P, Gov, Logs, Officers = Evora.DB, Evora.Players, Evora.Gov, Evora.Logs, Evora.Officers

function Citizens.card(target_id)
    local unpaid = DB.query(
        "SELECT id, category_label, label, amount, officer_name, officer_id, created_at FROM evora_police_fines WHERE target_id = ? AND status = 'unpaid' ORDER BY id DESC LIMIT 20",
        { target_id }
    )
    local totalRow = DB.single("SELECT COUNT(*) AS c, COALESCE(SUM(amount), 0) AS s FROM evora_police_fines WHERE target_id = ? AND status = 'unpaid'", { target_id })
    local wanted = Evora.Wanted.getActive(target_id)
    local jail = Evora.Jail and Evora.Jail.status(target_id)
    local fines = {}
    for _, f in ipairs(unpaid) do
        fines[#fines + 1] = {
            id = tonumber(f.id), category = f.category_label, label = f.label, amount = tonumber(f.amount),
            officer = { id = tonumber(f.officer_id), name = f.officer_name }, createdAt = tonumber(f.created_at),
        }
    end
    return {
        user_id = target_id,
        name = P.name(target_id),
        online = P.isOnline(target_id),
        job = Evora.Integrations.Job.get(target_id),
        avatar = Evora.Integrations.ProfileImage.get(target_id),
        fines = {
            count = tonumber(totalRow and totalRow.c) or 0,
            total = tonumber(totalRow and totalRow.s) or 0,
            list = fines,
        },
        wanted = wanted and {
            active = true, reason = wanted.reason, by = wanted.created_by_name, byId = tonumber(wanted.created_by_id),
            createdAt = tonumber(wanted.created_at),
        } or { active = false },
        jailed = jail and jail.jailed or false,
    }
end

-- Builder Menu flow: "استعلام عن مواطن"
function Citizens.inquiryFlow(source)
    local user_id = P.getUserId(source)
    if not user_id then return end
    local profile = Gov.getProfile(user_id, true)
    if not Evora.feature("CitizenInquiry") or not Gov.has(profile, "citizenInquiry") then
        return Evora.notify(source, "err_no_permission", nil, "error")
    end
    if not Officers.dutyOk(user_id, "citizenInquiry") then return Evora.notify(source, "err_not_on_duty", nil, "error") end
    local values = Evora.Integrations.Popup.input(source, L("citizen_inquiry_title"), {
        { key = "id", label = L("field_citizen_id"), type = "number", min = 1 },
    })
    if not values then return Evora.notify(source, "action_cancelled", nil, "info") end
    -- The input can stay open for minutes: re-check against live groups.
    if not Gov.has(Gov.getProfile(user_id, true), "citizenInquiry") then return Evora.notify(source, "err_no_permission", nil, "error") end
    if not P.exists(values.id) then return Evora.notify(source, "err_unknown_id", nil, "error") end
    local card = Citizens.card(values.id)
    Evora.ui(source, "panel", { kind = "citizen", title = L("citizen_inquiry_title"), data = card })
    Logs.add("field", "citizen_inquiry", { actor = user_id, target = values.id })
end
