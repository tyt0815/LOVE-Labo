local Simulation = {}
function Simulation.execute(project, level, request)
    local frames, dt = tonumber(request.frames or 1), tonumber(request.dt or 1 / 60)
    assert(frames and frames >= 0 and frames <= 10000 and frames % 1 == 0, "frames must be an integer between 0 and 10000")
    assert(require("core.Transform").finite(dt) and dt >= 0, "dt must be finite and non-negative")
    local debugSession = request.debug and require("editor.DebugSession").new() or nil
    return require("runtime.WorldLoader").run(project, level:toData(), debugSession, function(world, setWorld)
        for _ = 1, frames do
            if debugSession then debugSession:finishFrame(); debugSession:update(dt) end
            assert(world:update(dt))
            local nextWorld, transitionError = world:takeLevelTransition()
            if nextWorld then world = nextWorld; setWorld(world) end
            assert(not transitionError, transitionError)
        end
        local instances = {}
        for _, object in ipairs(world.lobjects) do
            instances[#instances + 1] = {runtimeId = object.runtimeId, authoringId = object.authoringId,
                name = object.name, transform = require("core.Transform").copy(object.transform), scripts = require("runtime.ScriptState").read(object)}
        end
        return {frames = frames, dt = dt, elapsedTime = world.elapsedTime, levelReference = world.levelReference, instances = instances,
            projectScripts = world.project and require("runtime.ScriptState").read(world.project),
            levelScripts = require("runtime.ScriptState").read(world),
            debug = debugSession and {history = debugSession.history, screens = debugSession.screens, shapes = debugSession.shapes} or nil}
    end)
end
return Simulation
