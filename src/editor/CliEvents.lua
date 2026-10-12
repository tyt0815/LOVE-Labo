local Operations = {}
function Operations.execute(project, level, request)
    local events = request.events
    if request["events-json"] then events = assert(require("project.Json").decode(request["events-json"])) end
    assert(type(events) == "table" and #events > 0 and #events <= 1000, "Expected 1..1000 script events")
    local debugSession = request.debug and require("editor.DebugSession").new() or nil
    return require("runtime.WorldLoader").run(project, level:toData(), debugSession, function(world)
        local viewport = require("core.Viewport").new(world, 0, 0, tonumber(request.width or 1280), tonumber(request.height or 720))
        for _, event in ipairs(events) do
            assert(type(event) == "table" and require("core.ScriptEvents").supported[event.name], "Unsupported script event")
            assert(type(event.args) == "table", "Expected event args array")
            assert(event.name ~= "joystickadded" and event.name ~= "joystickremoved" and not event.name:match("^gamepad")
                and not event.name:match("^joystick"), "Device events require a live LÖVE Joystick")
            if event.name == "focus" and not event.args[1] then world:cancelPointer() end
            local ok, err = require("core.ScriptEvents").screen(world, viewport, event.name, unpack(event.args))
            assert(ok, err)
        end
        local instances = {}
        for _, object in ipairs(world.lobjects) do
            instances[#instances + 1] = {authoringId = object.authoringId, name = object.name,
                transform = require("core.Transform").copy(object.transform), scripts = require("runtime.ScriptState").read(object)}
        end
        world:cancelPointer()
        return {events = #events, instances = instances, debug = debugSession and {history = debugSession.history} or nil}
    end)
end
return Operations
