local Operations = {}
function Operations.execute(project, level, request)
    local events = request.events
    if request["events-json"] then events = assert(require("project.Json").decode(request["events-json"])) end
    assert(type(events) == "table" and #events > 0 and #events <= 1000, "Expected 1..1000 script events")
    local debugSession = request.debug and require("editor.DebugSession").new() or nil
    return require("runtime.WorldLoader").run(project, level:toData(), debugSession, function(world, setWorld)
        local step = request["step-dt"] ~= nil and tonumber(request["step-dt"]) or nil
        assert(request["step-dt"] == nil or require("core.Transform").finite(step) and step >= 0, "step-dt must be finite and non-negative")
        for _, event in ipairs(events) do
            assert(type(event) == "table" and require("core.ScriptEvents").supported[event.name], "Unsupported script event")
            assert(type(event.args) == "table", "Expected event args array")
            assert(event.name ~= "joystickadded" and event.name ~= "joystickremoved" and not event.name:match("^gamepad")
                and not event.name:match("^joystick"), "Device events require a live LÖVE Joystick")
            local viewport = require("core.Viewport").new(world, 0, 0, tonumber(request.width or 1280), tonumber(request.height or 720))
            if event.name == "focus" and not event.args[1] then world:cancelPointer() end
            local ok, err = require("core.ScriptEvents").screen(world, viewport, event.name, unpack(event.args))
            assert(ok, err)
            if step then
                assert(world:update(step))
                local nextWorld, transitionError = world:takeLevelTransition()
                if nextWorld then world = nextWorld; setWorld(world) end
                assert(not transitionError, transitionError)
            end
        end
        local instances = {}
        for _, object in ipairs(world.lobjects) do
            instances[#instances + 1] = {authoringId = object.authoringId, name = object.name,
                transform = require("core.Transform").copy(object.transform), scripts = require("runtime.ScriptState").read(object)}
        end
        world:cancelPointer()
        return {events = #events, instances = instances, levelReference = world.levelReference,
            projectScripts = world.project and require("runtime.ScriptState").read(world.project),
            levelScripts = require("runtime.ScriptState").read(world), debug = debugSession and {history = debugSession.history} or nil}
    end)
end
return Operations
