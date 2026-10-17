local Fs = require("editor.HostFileSystem")
local Json = require("project.Json")
local GamePackage = {}

local function ensureFolder(path)
    local ok, err = pcall(require("project.Workspace").ensureDirectory, path)
    return ok, err
end

function GamePackage.write(project, level, output, options)
    options = options or {}
    if type(output) ~= "string" or not output:lower():match("%.love$") then return false, "Output must be a .love file" end
    output = output:gsub("\\", "/")
    if not output:match("^%a:/") and output:sub(1, 1) ~= "/" then output = Fs.join(project.rootPath, output) end
    output = require("project.Workspace").absolute(output)
    local relative = project:referenceForPath(output)
    if relative and (relative == "Assets" or relative:match("^Assets/")) then return false, "Export output must be outside Assets" end
    if not options.cliEntry then
        local world, err = require("runtime.WorldLoader").prepare(project, level:toData())
        if not world then return false, err end
    end
    local entries = {}
    local function add(name, bytes) entries[#entries + 1] = {name = name, bytes = assert(bytes)} end
    local function collect(directory)
        for _, name in ipairs(love.filesystem.getDirectoryItems(directory)) do
            local path = directory .. "/" .. name
            local info = love.filesystem.getInfo(path)
            if info.type == "directory" then collect(path)
            elseif name:match("%.lua$") then add(path, assert(love.filesystem.read(path))) end
        end
    end
    for _, folder in ipairs({"core", "project", "runtime", "Engine"}) do collect(folder) end
    local plugins = project.plugins:export()
    for _, plugin in ipairs(plugins.manifests) do
        for name, file in pairs(plugin.scripts) do
            local id = project.plugins.scripts[name].id
            add("plugins/" .. plugin.name .. "/" .. file, id and project:readSource(id) or project.plugins.plugins[plugin.name].read(file))
        end
    end
    add("Engine.lua", assert(love.filesystem.read("Engine.lua")))
    if options.cliEntry then
        add("main.lua", [[love.load = require("runtime.CliHost").run
love.errorhandler = function(message)
    io.stderr:write(tostring(message) .. "\n")
    return function() return 1 end
end
]])
        add("conf.lua", [[function love.conf(t)
t.version = "11.5"
t.identity = ]] .. string.format("%q", project.saveIdentity) .. "\n" .. [[
t.console = true
t.window = false
t.modules.audio = false
t.modules.graphics = false
end
]])
    else
        add("main.lua", [[local host = require("runtime.Host")
love.load = host.load
love.update = host.update
love.draw = host.draw
love.quit = host.quit
for _, name in ipairs(require("core.ScriptEvents").names) do love[name] = host[name] end
]])
        local config = require("editor.GameConfig")
        add("ProjectConf.lua", config.read(project))
        add("conf.lua", config.wrapper(project))
    end
    local metadata = {}
    local references = {}
    for reference in pairs(project.assetMetadata or {}) do references[#references + 1] = reference end
    table.sort(references)
    for _, reference in ipairs(references) do
        local path, info = project:checkedEntry(reference)
        if not path or info.type ~= "file" then return false, "Invalid export resource: " .. reference end
        local bytes, readError
        if reference:match("^Assets/") then bytes, readError = project:readAsset(reference)
        else bytes, readError = Fs.read(path) end
        if not bytes then return false, "Cannot read export resource " .. reference .. ": " .. tostring(readError) end
        add("project/" .. reference, bytes)
        metadata[reference] = project.assetMetadata[reference]
    end
    local data = level:toData()
    data.lobjects = Json.array(data.lobjects)
    add("game.json", assert(Json.encode({version = 1, id = project.id, saveIdentity = project.saveIdentity, cliEntry = options.cliEntry, level = data, metadata = metadata, plugins = plugins,
        scripts = Json.array(require("project.ScriptAttachments").copy(project.scripts)), scriptOverrides = project.scriptOverrides}, true)))
    local bytes = require("editor.Zip").encode(entries)
    local made, makeError = ensureFolder(Fs.parent(output))
    if not made then return false, makeError end
    local written, writeError = Fs.writeAtomic(output, bytes)
    if not written then return false, writeError end
    return true, {output = output, files = #entries, bytes = #bytes}
end
return GamePackage
