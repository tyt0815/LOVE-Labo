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
    local response = {version = 1, ok = ok}
    if ok then response.result = result else response.error = tostring(result) end
    local bytes, encodeError = Json.encode(response)
    if not bytes then
        ok = false
        bytes = assert(Json.encode({version = 1, ok = false, error = "Cannot encode command result: " .. tostring(encodeError)}))
    end
    if request and request.result then
        local called, saved, err = pcall(function()
            return require("project.NativeFileSystem").writeAtomic(request.result, bytes .. "\n")
        end)
        if not called or not saved then
            ok = false
            bytes = assert(Json.encode({version = 1, ok = false, error = tostring(called and err or saved)}))
        end
    end
    io.stdout:write(bytes .. "\n"); io.stdout:flush()
    love.event.quit(ok and 0 or 1)
end
return Host
