local Transform = require("core.Transform")
local Input = require("core.Input")
local Pointer = {}
local CALLBACKS = {down = "onDown", up = "onUp", move = "onMove"}
function Pointer.dispatch(world, kind, x, y, button, dx, dy, context)
    assert(CALLBACKS[kind], "Unknown pointer event")
    assert(Transform.finite(x) and Transform.finite(y) and Transform.finite(dx or 0) and Transform.finite(dy or 0), "Invalid pointer coordinates")
    button = button or 1
    assert(type(button) == "number" and button >= 1 and button % 1 == 0, "Invalid pointer button")
    context = context or {image = function() end}
    local captures = world.pointerCaptures or {}; world.pointerCaptures = captures
    for id, region in pairs(captures) do if not region:isActive() then captures[id] = nil end end
    if kind == "down" then captures[button] = nil end
    local captured = kind == "up" and captures[button]
    if kind == "up" then captures[button] = nil end
    local candidates, seen = {}, {}
    if captured then candidates[1] = captured
    elseif kind == "move" and next(captures) then
        local buttons = {}; for id in pairs(captures) do buttons[#buttons + 1] = id end; table.sort(buttons)
        for _, id in ipairs(buttons) do local region = captures[id]; if not seen[region] then candidates[#candidates + 1] = region; seen[region] = true end end
    else
        for _, region in ipairs(world.inputRegions or {}) do
            if region:isActive() then
                candidates[#candidates + 1] = region
            end
        end
        local ranks = {}
        for _, entry in ipairs(require("core.ScriptOrder").entries(require("core.ScriptOrder").hosts(world), "draw")) do ranks[entry.script] = entry.index end
        local orders = {}
        for _, region in ipairs(candidates) do
            local source = region.filterSource()
            orders[region] = {priority = Input.value(region, "priority"), order = Input.value(region, "order"), rank = ranks[source] or region.id}
        end
        table.sort(candidates, function(a, b)
            local left, right = orders[a], orders[b]
            if left.priority ~= right.priority then return left.priority > right.priority end
            if left.order ~= right.order then return left.order > right.order end
            if left.rank ~= right.rank then return left.rank > right.rank end
            return a.id > b.id
        end)
    end
    local result = {consumed = false, targets = {}}
    for _, region in ipairs(candidates) do
        local script = region.owner
        local source = region.filterSource()
        if region:isActive() and source and (not context.view or context.view:includes(source)) then
            local hit, localX, localY = region.hitTest(context, x, y)
            if context.worldVisible == false then hit = false end
            if hit or captured == region or seen[region] then
                local event = {kind = kind, worldX = x, worldY = y, localX = localX, localY = localY,
                    button = button, dx = dx or 0, dy = dy or 0, inside = hit == true, world = world,
                    screenX = context.screenX, screenY = context.screenY, coordinateSpace = "world", view = context.view, viewport = context.viewport, projection = context.projection}
                local owner, id = script.owner, script.id
                local callback = region[CALLBACKS[kind]]
                local consumed = (callback and callback(event) == true or false) or Input.value(region, "block") == true
                result.targets[#result.targets + 1] = {runtimeId = owner.runtimeId,
                    authoringId = owner.authoringId, script = id, consumed = consumed}
                if consumed or captured == region then
                    result.consumed = true
                    if kind == "down" and region:isActive() then captures[button] = region end
                    if not (kind == "move" and seen[region]) then break end
                end
            end
        end
    end
    return result
end
return Pointer
