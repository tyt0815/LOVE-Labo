local Pointer = require("core.PointerComponent")
local Transform = require("core.Transform")
local Input = {}
local CALLBACKS = {down = "onPointerDown", up = "onPointerUp", move = "onPointerMove"}
function Input.dispatch(world, kind, x, y, button, dx, dy, context)
    assert(CALLBACKS[kind], "Unknown pointer event")
    assert(Transform.finite(x) and Transform.finite(y) and Transform.finite(dx or 0) and Transform.finite(dy or 0), "Invalid pointer coordinates")
    button = button or 1
    assert(type(button) == "number" and button >= 1 and button % 1 == 0, "Invalid pointer button")
    context = context or {image = function() end}
    world.pointerCaptures = world.pointerCaptures or {}
    local live = {}; for _, object in ipairs(world.lobjects) do live[object] = true end
    for id, component in pairs(world.pointerCaptures) do
        if not live[component.owner] or component.owner.components[component.name] ~= component or not component.properties.enabled then world.pointerCaptures[id] = nil end
    end
    if kind == "down" then world.pointerCaptures[button] = nil end
    local candidates, seen = {}, {}
    local captured = kind == "up" and world.pointerCaptures[button]
    if kind == "up" then world.pointerCaptures[button] = nil end
    if captured then candidates[1] = captured
    elseif kind == "move" and next(world.pointerCaptures) then
        local buttons = {}; for id in pairs(world.pointerCaptures) do buttons[#buttons + 1] = id end; table.sort(buttons)
        for _, id in ipairs(buttons) do
            local component = world.pointerCaptures[id]
            if not seen[component] then candidates[#candidates + 1] = component; seen[component] = true end
        end
    else
        local entries = require("core.ComponentOrder").entries(world.lobjects, Pointer, function(component) return component.properties.enabled end)
        for index = #entries, 1, -1 do candidates[#candidates + 1] = entries[index].component end
    end
    local result = {consumed = false, targets = {}}
    for _, component in ipairs(candidates) do
        if component.owner and component.properties.enabled then
            local screen = require("core.CoordinateSpace").canvas(component:getBoundsSource()) ~= nil
            local hitX, hitY = x, y
            if screen and context.screenX ~= nil then hitX, hitY = context.screenX, context.screenY end
            local hit, localX, localY = component:hitTest(context, hitX, hitY)
            if not screen and context.worldVisible == false then hit = false end
            if hit or captured == component or seen[component] then
                local event = {kind = kind, worldX = x, worldY = y, localX = localX, localY = localY,
                    button = button, dx = screen and context.screenDx or dx or 0, dy = screen and context.screenDy or dy or 0,
                    screenX = context.screenX, screenY = context.screenY, coordinateSpace = screen and "screen" or "world", inside = hit == true, world = world}
                local consumed = component[CALLBACKS[kind]](component, event) == true or component.properties.blockPointer
                result.targets[#result.targets + 1] = {runtimeId = component.owner.runtimeId, authoringId = component.owner.authoringId, component = component.name, consumed = consumed}
                if consumed or captured == component then
                    result.consumed = true
                    if kind == "down" then world.pointerCaptures[button] = component end
                    if not (kind == "move" and seen[component]) then break end
                end
            end
        end
    end
    return result
end
return Input
