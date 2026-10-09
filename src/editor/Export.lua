local Fs = require("editor.HostFileSystem")
local Json = require("project.Json")
local Export = {}

local function ensureFolder(path)
    local info, err = Fs.info(path)
    if err then return false, err end
    if info then return info.type == "directory" and not info.isLink, "Output parent must be a regular folder" end
    local parent = Fs.parent(path)
    if parent == path or not parent then return false, "Invalid output parent" end
    local ok, parentError = ensureFolder(parent)
    if not ok then return false, parentError end
    return Fs.mkdir(path)
end

function Export.write(project, level, output)
    if type(output) ~= "string" or not output:lower():match("%.love$") then return false, "Output must be a .love file" end
    output = output:gsub("\\", "/")
    if not output:match("^%a:/") and output:sub(1, 1) ~= "/" then output = Fs.join(project.rootPath, output) end
    local relative = project:referenceForPath(output)
    if relative and (relative:match("^Assets/") or relative:match("^Sources/")) then return false, "Export output must be outside Assets and Sources" end
    local world, err = require("runtime.WorldLoader").prepare(project, level:toData())
    if not world then return false, err end
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
    for _, folder in ipairs({"core", "project", "runtime"}) do collect(folder) end
    add("Engine.lua", assert(love.filesystem.read("Engine.lua")))
    add("main.lua", [[local host = require("runtime.Host")
love.load = host.load
love.update = host.update
love.draw = host.draw
]])
    add("conf.lua", [[function love.conf(t)
t.version = "11.5"
t.identity = "labo-exported-game"
t.window.title = "Labo Game"
t.window.width = 1280
t.window.height = 720
t.window.resizable = true
end
]])
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
    add("game.json", assert(Json.encode({version = 1, level = data, metadata = metadata}, true)))
    local bytes = require("editor.Zip").encode(entries)
    local made, makeError = ensureFolder(Fs.parent(output))
    if not made then return false, makeError end
    local written, writeError = Fs.writeAtomic(output, bytes)
    if not written then return false, writeError end
    return true, {output = output, files = #entries, bytes = #bytes}
end
return Export
