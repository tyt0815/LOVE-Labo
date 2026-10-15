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
    live[world] = true
    if world.project then live[world.project] = true end
    for id, script in pairs(world.pointerCaptures) do
        if not live[script.owner] or script.owner.scripts[script.id] ~= script or script.properties.enabled == false then world.pointerCaptures[id] = nil end
    end
    if kind == "down" then world.pointerCaptures[button] = nil end
    local candidates, seen = {}, {}
    local captured = kind == "up" and world.pointerCaptures[button]
    if kind == "up" then world.pointerCaptures[button] = nil end
    if captured then candidates[1] = captured
    elseif kind == "move" and next(world.pointerCaptures) then
        local buttons = {}; for id in pairs(world.pointerCaptures) do buttons[#buttons + 1] = id end; table.sort(buttons)
        for _, id in ipairs(buttons) do
            local script = world.pointerCaptures[id]
            if not seen[script] then candidates[#candidates + 1] = script; seen[script] = true end
        end
    else
        local hosts = {}; for _, object in ipairs(world.lobjects) do hosts[#hosts + 1] = object end
        table.insert(hosts, 1, world)
        if world.project then table.insert(hosts, 1, world.project) end
        local entries = require("core.ScriptOrder").entries(hosts, "pointer", function(script) return script.properties.enabled ~= false end)
        for index = #entries, 1, -1 do candidates[#candidates + 1] = entries[index].script end
    end
    local result = {consumed = false, targets = {}}
    for _, script in ipairs(candidates) do
        if script.owner and script.properties.enabled ~= false then
            local screen = require("core.CoordinateSpace").canvas(script:getBoundsSource()) ~= nil
            local hitX, hitY = x, y
            if screen and context.screenX ~= nil then hitX, hitY = context.screenX, context.screenY end
            local hit, localX, localY = script:hitTest(context, hitX, hitY)
            if context.worldVisible == false then hit = false end
            if hit or captured == script or seen[script] then
                local event = {kind = kind, worldX = x, worldY = y, localX = localX, localY = localY,
                    button = button, dx = screen and context.screenDx or dx or 0, dy = screen and context.screenDy or dy or 0,
                    screenX = context.screenX, screenY = context.screenY, coordinateSpace = screen and "screen" or "world", inside = hit == true, world = world}
                local callback = script[CALLBACKS[kind]]
                local owner, id = script.owner, script.id
                local consumed = (callback and callback(script, event) == true or false) or script.properties.blockPointer == true
                result.targets[#result.targets + 1] = {runtimeId = owner.runtimeId, authoringId = owner.authoringId, script = id, consumed = consumed}
                if consumed or captured == script then
                    result.consumed = true
                    if kind == "down" and owner.world == world and script.owner == owner and owner.scripts[id] == script then world.pointerCaptures[button] = script end
                    if not (kind == "move" and seen[script]) then break end
                end
            end
        end
    end
    return result
end
return Input
