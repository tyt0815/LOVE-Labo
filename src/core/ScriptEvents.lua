local Events = {}
Events.names = {
    "keypressed", "keyreleased", "textinput", "textedited",
    "mousepressed", "mousereleased", "mousemoved", "wheelmoved",
    "touchpressed", "touchreleased", "touchmoved",
    "joystickpressed", "joystickreleased", "joystickaxis", "joystickhat",
    "gamepadpressed", "gamepadreleased", "gamepadaxis", "joystickadded", "joystickremoved",
    "focus", "mousefocus", "visible", "resize"
}
Events.supported = {}
for _, name in ipairs(Events.names) do Events.supported[name] = true end

function Events.dispatch(world, name, ...)
    if not Events.supported[name] then return false, "Unsupported script event: " .. tostring(name) end
    -- 이벤트 시작 시 후보를 고정하고 호출 직전에 생존·활성 상태를 다시 검사한다.
    local pending = {}
    for _, object in ipairs(require("core.ScriptOrder").objects(world.lobjects)) do
        for _, id in ipairs(object.scriptOrder) do
            local script = object.scripts[id]
            if type(script[name]) == "function" then pending[#pending + 1] = {object = object, script = script} end
        end
    end
    for _, entry in ipairs(pending) do
        local object, script = entry.object, entry.script
        if object.world == world and script.owner == object and object.scripts[script.id] == script and script.enabled ~= false then
            local ok, err = pcall(script[name], script, ...)
            if not ok then return false, "Script " .. script.name .. " " .. name .. " failed: " .. tostring(err) end
        end
    end
    return true
end

function Events.screen(world, viewport, name, ...)
    local args, count = {...}, select("#", ...)
    local mouse = name == "mousepressed" or name == "mousereleased" or name == "mousemoved"
    local touch = name == "touchpressed" or name == "touchreleased" or name == "touchmoved"
    if mouse or touch then
        local index = touch and 2 or 1
        local x, y = args[index], args[index + 1]
        local inside = x >= viewport.x and y >= viewport.y and x < viewport.x + viewport.width and y < viewport.y + viewport.height
        world.eventCaptures = world.eventCaptures or {mouse = {}, touch = {}}
        local captures = touch and world.eventCaptures.touch or world.eventCaptures.mouse
        local key = touch and args[1] or args[3]
        local pressed = name == "mousepressed" or name == "touchpressed"
        local released = name == "mousereleased" or name == "touchreleased"
        local captured = name == "mousemoved" and next(captures) ~= nil or captures[key] ~= nil
        if pressed then
            if not inside then return true end
            captures[key] = true
        elseif not inside and not captured then return true end
        if released then captures[key] = nil end
        args[index], args[index + 1] = x - viewport.x, y - viewport.y
    end
    return Events.dispatch(world, name, unpack(args, 1, count))
end

function Events.cancel(world) world.eventCaptures = nil end
return Events
