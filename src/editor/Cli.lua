local Cli = {}
local Fs = require("editor.HostFileSystem")
local Json = require("project.Json")
local Project = require("editor.Project")
local function required(request, name)
    local item = assert(request[name], "Missing --" .. name)
    return item
end
local function absolute(path)
    assert(type(path) == "string" and path ~= "", "Invalid path")
    path = path:gsub("\\", "/")
    if not path:match("^%a:/") and path:sub(1, 1) ~= "/" then path = Fs.join(love.filesystem.getWorkingDirectory(), path) end
    return path
end
local function revision(bytes) return love.data.encode("string", "hex", love.data.hash("sha256", bytes)) end
local function checkRevision(request, bytes)
    assert(not request.revision or request.revision == revision(bytes), "Revision conflict: reload the document before editing")
end
local function basicResult(project, reference)
    return {reference = reference, assetId = project:getAssetId(reference), project = project.rootPath}
end
local function value(request)
    if request.value ~= nil then return request.value end
    local parsed, err = Json.decode(required(request, "value-json"))
    assert(parsed ~= nil and parsed ~= Json.null, err or "null is not a property value")
    return parsed
end
local function setProperty(project, target, name, item)
    local declaration = assert(target.class.properties[name], "Unknown property: " .. name)
    assert(require("project.LuaClass").validValue(declaration.type, item), "Invalid property value")
    if declaration.type == "image" and item ~= false then
        local path = assert(project:resolveAssetFile(item))
        local pixels = love.image.newImageData(love.filesystem.newFileData(assert(project:readAsset(item)), path))
        pixels:release()
    end
    if declaration.type == "object" and item ~= false then
        local found = false
        for _, object in ipairs(target.level and target.level.lobjects or {}) do if object.authoringId == item then found = true end end
        assert(found, "Object reference must identify an instance in the same level")
    end
    if require("core.PropertySchema").isTemplate(declaration.type) and item ~= false then
        local template = assert(require("project.LObjectTemplate").resolve(project, item))
        item = template.reference
    end
    local overrides = target:getOverrides()
    overrides[name] = item ~= declaration.default and item or nil
    -- false도 기본값과 다르면 명시적인 override이다.
    if item == false and item ~= declaration.default then overrides[name] = false end
    target:setOverrides(overrides)
end
local function properties(target)
    local values = {}
    local overrides = target:getOverrides()
    for name, declaration in pairs(target.class.properties) do
        values[name] = overrides[name]
        if values[name] == nil then values[name] = declaration.default end
    end
    return {schema = target.class.properties, values = values}
end

local function execute(request)
    local command = required(request, "command")
    if command == "help" then
        return {commands = {"project.create", "project.info", "project.set-default", "class.create", "prefab.create", "prefab.get", "prefab.set", "level.create", "level.get", "level.set", "instance.add", "instance.get", "instance.set", "instance.reparent", "export"}}
    end
    if command == "project.create" then
        local project = assert(Project.create(absolute(required(request, "parent")), required(request, "name")))
        return {project = project.rootPath, name = project.name}
    end
    local project = assert(Project.open(absolute(required(request, "project"))))
    if command == "project.info" then return {project = project.rootPath, name = project.name, defaultLevel = project.defaultLevelReference, assets = project.assetMetadata} end
    if command == "class.create" or command == "prefab.create" or command == "level.create" then
        local kind = command:match("^(.-)%.")
        local folder = request.folder or (kind == "class" and "Sources" or "Assets")
        local parent = kind == "class" and request.parent
        local builtin = ({LObjectComponent = true, SceneComponent = true, RenderComponent = true, SpriteComponent = true})[parent or ""]
        local options = {scriptKind = request.type or builtin and "component" or (parent and assert(project:getScriptKind(parent))) or "lobject",
            parentReference = parent, scriptReference = request.class}
        local ok, reference = project:createEntry(folder, kind == "class" and "lua" or kind, required(request, "name"), options)
        assert(ok, reference)
        return basicResult(project, reference)
    end
    if command == "project.set-default" then
        local reference = project:getAssetReference(required(request, "level"))
        assert(reference and reference:match("^Assets/.+%.level$"), "Default level must be an Assets/*.level file")
        assert(require("editor.LevelDocument").load(assert(project:resolveAssetFile(reference))))
        local path = Fs.join(project.rootPath, Project.FILE_NAME)
        local bytes = assert(Fs.read(path)); checkRevision(request, bytes)
        local data = assert(Json.decode(bytes))
        data.defaultLevelReference = project:getAssetId(reference)
        assert(Fs.writeAtomic(path, assert(Json.encode(data, true)) .. "\n"))
        return {defaultLevel = data.defaultLevelReference}
    end
    if command:match("^prefab%.") then
        local reference = required(request, "prefab")
        local document = assert(require("editor.PrefabDocument").load(project, reference))
        local bytes = assert(project:readAsset(reference)); checkRevision(request, bytes)
        assert(require("project.ObjectDefinition").resolve(project, reference))
        local definition = assert(require("project.ObjectDefinition").resolve(project, document.data.definitionReference))
        local proxy = {propertyOverrides = document.data.overrides.properties, componentOverrides = document.data.overrides.components}
        local target = assert(require("project.ObjectDefinition").inspectorTarget(project, proxy, definition))
        if command == "prefab.set" then
            setProperty(project, target, required(request, "property"), value(request))
            document.data.overrides.properties, document.data.overrides.components = proxy.propertyOverrides, proxy.componentOverrides
            assert(assert(project:readAsset(reference)) == bytes, "Revision conflict: file changed while editing")
            assert(document:save(project))
            bytes = assert(project:readAsset(reference))
        else assert(command == "prefab.get", "Unknown command: " .. command) end
        local result = properties(target); result.revision = revision(bytes); return result
    end
    local levelReference = request.level or project.defaultLevelReference
    assert(levelReference, "Missing --level and project has no default level")
    local levelPath = assert(project:resolveAssetFile(levelReference))
    assert(project:getAssetReference(levelReference):match("%.level$"), "Expected a level file")
    local bytes = assert(Fs.read(levelPath)); checkRevision(request, bytes)
    local document = assert(require("editor.LevelDocument").load(levelPath))
    local level = document.level
    local changed, object, target
    if command == "instance.add" then
        local prefab = request.template or required(request, "prefab")
        local reference = assert(project:getAssetReference(prefab))
        assert(require("project.LObjectTemplate").resolve(project, prefab))
        local x, y = tonumber(request.x or 0), tonumber(request.y or 0)
        assert(require("core.Transform").finite(x) and require("core.Transform").finite(y), "Invalid placement coordinates")
        object = assert(level:addLObject(x, y, project:getAssetId(reference), reference:match("([^/]+)%.[^.]+$")))
        if request.parent ~= nil and request.parent ~= false then
            local parent = assert(level:findLObject(tonumber(request.parent)), "Parent instance not found")
            object.parentAuthoringId = parent.authoringId
        end
        changed = true
    elseif command:match("^instance%.") then
        local id = tonumber(required(request, "instance"))
        for _, candidate in ipairs(level.lobjects) do if candidate.authoringId == id then object = candidate end end
        assert(object, "Instance not found")
        local definition = assert(require("project.ObjectDefinition").resolve(project, object.definitionReference))
        target = assert(require("project.ObjectDefinition").inspectorTarget(project, object, definition, level))
        if command == "instance.reparent" then
            local parent = request.parent ~= nil and request.parent ~= false and assert(level:findLObject(tonumber(request.parent)), "Parent instance not found") or nil
            assert(level:reparent({object}, parent)); changed = true
        elseif command == "instance.set" then
            local name, item = required(request, "property"), value(request)
            local transformField = name:match("^transform%.(.+)$")
            if transformField then
                assert(object.transform[transformField] ~= nil, "Unknown Transform field")
                local copy = require("project.PropertyData").copy(object.transform); copy[transformField] = item
                object.transform = assert(require("core.Transform").copy(copy))
            else setProperty(project, target, name, item) end
            changed = true
        else assert(command == "instance.get", "Unknown command: " .. command) end
    elseif command == "level.set" or command == "level.get" then
        local class = level.scriptReference and assert(require("project.LuaClass").load(project, level.scriptReference, "level"))
        target = {class = class or {properties = {}}, level = level,
            getOverrides = function() return require("project.PropertyData").copy(level.propertyOverrides) end,
            setOverrides = function(_, values) level.propertyOverrides = values end}
        if command == "level.set" then setProperty(project, target, required(request, "property"), value(request)); changed = true end
    elseif command == "export" then
        local ok, result = require("editor.Export").write(project, level, absolute(request.output or Fs.join(project.rootPath, "Build/Game.love")))
        assert(ok, result); return result
    else assert(command == "level.get", "Unknown command: " .. command) end
    if changed then
        assert(require("runtime.WorldLoader").prepare(project, level:toData()))
        -- 문서를 읽은 뒤 외부 저장이 있었으면 덮어쓰지 않는다.
        assert(assert(Fs.read(levelPath)) == bytes, "Revision conflict: file changed while editing")
        assert(document:save(levelPath))
        bytes = assert(Fs.read(levelPath))
    end
    local result = {revision = revision(bytes), level = project:getAssetReference(levelReference), data = object or level:toData()}
    if target then result.properties = properties(target) end
    return result
end

function Cli.execute(request)
    if request.command == "project.create" or request.command == "help" then return execute(request) end
    local directory = absolute(required(request, "project"))
    local lock = Fs.join(directory, ".labo-cli.lock")
    local acquired, err = Fs.createFile(lock, "Cli operation in progress\n")
    assert(acquired, "Project is busy or inaccessible: " .. tostring(err))
    local ok, result = pcall(execute, request)
    local removed, removeError = Fs.removeFile(lock)
    assert(removed, removeError)
    assert(ok, result)
    return result
end

function Cli.parse(args)
    local request, positionals = {}, {}
    local start
    for i, argument in ipairs(args) do if argument == "--cli" then start = i + 1; break end end
    local i = assert(start, "Missing --cli")
    while i <= #args do
        local item = args[i]
        if item:sub(1, 2) == "--" then
            local key = item:sub(3)
            local allowed = {project = true, parent = true, name = true, folder = true, type = true, class = true,
                prefab = true, template = true, level = true, instance = true, property = true, ["value-json"] = true,
                x = true, y = true, output = true, revision = true, request = true, result = true, value = true}
            assert(allowed[key], "Unknown option: " .. item)
            assert(args[i + 1] and args[i + 1]:sub(1, 2) ~= "--", "Missing value for " .. item)
            assert(request[key] == nil, "Duplicate option: " .. item)
            request[key], i = args[i + 1], i + 2
        else positionals[#positionals + 1] = item; i = i + 1 end
    end
    if request.request then
        local data = assert(Json.decode(assert(Fs.read(absolute(request.request)))))
        assert(type(data) == "table", "Request must be a JSON object")
        return data, request.result
    end
    request.command = table.concat(positionals, ".")
    if request.command == "" then request.command = "help" end
    return request, request.result
end
function Cli.run(args)
    local output
    local ok, result = pcall(function()
        local request
        request, output = Cli.parse(args)
        return Cli.execute(request)
    end)
    local response = {version = 1, ok = ok}
    if ok then response.result = result else response.error = tostring(result) end
    local text = assert(Json.encode(response))
    print(text)
    if output then
        local saved, err = Fs.writeAtomic(absolute(output), text .. "\n")
        if not saved then print(tostring(err)); ok = false end
    end
    love.event.quit(ok and 0 or 1)
end
return Cli
