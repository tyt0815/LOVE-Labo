local Json = require("project.Json")
local Commands = require("project.GameCommands")
local Host = {}

function Host.definition(project, entry)
    local moduleRequire, loadModule = require("project.LuaScript").moduleLoader(project, project.plugins)
    return loadModule(entry)
end

function Host.execute(project, entry, request)
    Commands.validateRequest(request)
    local definition = Host.definition(project, entry)
    local context = {project = project}
    if request.workspace then
        context.workspace = require("project.Workspace").new(request.workspace)
        return context.workspace:withLock(function() return Commands.execute(definition, request, context) end)
    end
    return Commands.execute(definition, request, context)
end

function Host.run(args)
    local request
    local ok, result = pcall(function()
        request = Commands.parse(args)
        local manifest = assert(Json.decode(assert(love.filesystem.read("game.json"))))
        assert(manifest.cliEntry, "Package has no CLI entry")
        return Host.execute(require("runtime.PackageProject").new(manifest), manifest.cliEntry, request)
    end)
    local bytes
    bytes, ok = require("project.CliResponse").finish(ok, result, request and request.result and function(text)
        return require("project.NativeFileSystem").writeAtomic(request.result, text)
    end)
    io.stdout:write(bytes .. "\n"); io.stdout:flush()
    love.event.quit(ok and 0 or 1)
end
return Host
