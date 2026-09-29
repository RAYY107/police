--[[
    Evora_Police — nearby target picker (fines, jail, field options)

    The list is built from SERVER-SIDE positions and every selection is re-validated when it
    is used, so a player can never act on someone who is not really next to them.
]]

local Targets = {}
Evora.Targets = Targets

local P = Evora.Players

function Targets.radius()
    return (Config.Targeting and Config.Targeting.Radius) or 4.0
end

-- Opens a menu of nearby players. onPick(targetSource, targetUserId) runs in a new thread.
function Targets.pick(source, title, onPick, parent, radius)
    radius = radius or Targets.radius()
    local list = P.nearby(source, radius)
    if #list == 0 then
        Evora.notify(source, "target_none", { radius = radius }, "error")
        return
    end
    local items = {}
    local max = (Config.Targeting and Config.Targeting.MaxResults) or 8
    for i = 1, math.min(#list, max) do
        local entry = list[i]
        items[#items + 1] = {
            label = ("%s | ID: %d"):format(entry.name, entry.user_id),
            description = L("target_distance", { distance = ("%.1f"):format(entry.dist) }),
            action = function(src) onPick(entry.source, entry.user_id) end,
        }
    end
    Evora.Menu.open(source, { title = title, items = items, parent = parent })
end

-- Re-validates a target right before acting.
function Targets.check(source, targetSource, targetUserId, radius)
    if not targetSource or not GetPlayerName(targetSource) then return false, L("err_target_offline") end
    if P.bySource[targetSource] ~= targetUserId then return false, L("err_target_offline") end
    if P.distance(source, targetSource) > (radius or Targets.radius()) + 1.0 then
        return false, L("target_too_far")
    end
    return true
end
