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
        item = project:getAssetId(project:getAssetReference(item)) or item
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

local api = {required = required, absolute = absolute, revision = revision, checkRevision = checkRevision,
    basicResult = basicResult, value = value, setProperty = setProperty, properties = properties}
local COMMANDS = {"project.create", "project.info", "project.set-default", "project.validate", "class.create", "class.list", "class.get", "class.set-source",
    "folder.create", "asset.list", "asset.get", "asset.move", "asset.rename", "asset.delete", "asset.import", "asset.copy",
    "prefab.create", "prefab.get", "prefab.tree", "prefab.set", "prefab.reset", "prefab.set-parent",
    "prefab.child.add", "prefab.child.remove", "prefab.child.rename", "level.create", "level.get", "level.set", "level.reset", "level.set-parent", "level.validate", "level.pointer", "level.view",
    "instance.add", "instance.get", "instance.list", "instance.set", "instance.reset", "instance.rename", "instance.reparent", "instance.duplicate", "instance.delete", "export"}
local function execute(request)
    local command = required(request, "command")
    if command == "help" then
        return {commands = COMMANDS, requestFormat = "JSON object: command, project, command arguments",
            propertyValues = "Use value-json for numbers/booleans and value for strings; JSON requests use value directly",
            prefabNodes = "root or root/<child-id>/...; object references accept node paths",
            multiSelection = "instances: JSON array or comma-separated --instances; includes descendants",
            examples = {{command = "project.validate", project = "D:/Games/MyGame"},
                {command = "instance.duplicate", project = "D:/Games/MyGame", instances = {1, 2}},
                {command = "prefab.child.add", project = "D:/Games/MyGame", prefab = "Assets/PF_Enemy.prefab", node = "root", template = "Sources/Weapon.lua"}}}
    end
    local known = false; for _, name in ipairs(COMMANDS) do if name == command then known = true; break end end
    assert(known, "Unknown command: " .. command)
    if command == "project.create" then
        local project = assert(Project.create(absolute(required(request, "parent")), required(request, "name")))
        return {project = project.rootPath, name = project.name}
    end
    local project = assert(Project.open(absolute(required(request, "project"))))
    local extra = require("editor.CliAssets").execute(project, request, api)
    if extra then return extra end
    if command == "project.info" then return {project = project.rootPath, name = project.name, defaultLevel = project.defaultLevelReference, assets = project.assetMetadata} end
    if command == "class.create" or command == "prefab.create" or command == "level.create" then
        local kind = command:match("^(.-)%.")
        local folder = request.folder or (kind == "class" and "Sources" or "Assets")
        local parent = kind == "class" and request.parent
        local builtin = ({LObjectComponent = true, SceneComponent = true, BoundsComponent = true, PointerComponent = true, RenderComponent = true, SpriteComponent = true, CameraComponent = true, RectComponent = true, CanvasComponent = true})[parent or ""]
        local options = {scriptKind = request.type or builtin and "component" or (parent and assert(project:getScriptKind(parent))) or "lobject",
            parentReference = parent, scriptReference = request.class}
        if kind == "prefab" and request.instance then
            local document = assert(require("editor.LevelDocument").load(assert(project:resolveAssetFile(request.level or project.defaultLevelReference))))
            local object = assert(document.level:findLObject(tonumber(request.instance)), "Instance not found")
            options.prefabData = assert(require("project.PrefabHierarchy").capture(project, document.level, object))
        end
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
        return require("editor.CliPrefab").execute(project, request, api)
    end
    local levelReference = request.level or project.defaultLevelReference
    assert(levelReference, "Missing --level and project has no default level")
    local levelPath = assert(project:resolveAssetFile(levelReference))
    assert(project:getAssetReference(levelReference):match("%.level$"), "Expected a level file")
    local bytes = assert(Fs.read(levelPath)); checkRevision(request, bytes)
    local document = assert(require("editor.LevelDocument").load(levelPath))
    local level = document.level
    level.beforeReparent = function(roots, parent) return require("project.PrefabHierarchy").prepareReparent(project, level, roots, parent) end
    level.duplicateData = function(object) return require("project.PrefabHierarchy").duplicateData(project, level, object) end
    local function selected()
        local ids = request.instances
        if type(ids) == "string" then local list = {}; for id in ids:gmatch("[^,]+") do list[#list + 1] = assert(tonumber(id), "Invalid instance ID") end; ids = list end
        ids = ids or {required(request, "instance")}
        assert(type(ids) == "table" and #ids > 0, "Expected instance IDs")
        local objects = {}; for _, id in ipairs(ids) do objects[#objects + 1] = assert(level:findLObject(tonumber(id)), "Instance not found") end
        return objects
    end
    local changed, object, target
    if command == "instance.add" then
        local prefab = request.template or request.prefab
        local reference
        if prefab then reference = assert(project:getAssetReference(prefab)); assert(require("project.LObjectTemplate").resolve(project, prefab)) end
        local x, y = tonumber(request.x or 0), tonumber(request.y or 0)
        assert(require("core.Transform").finite(x) and require("core.Transform").finite(y), "Invalid placement coordinates")
        object = assert(level:addLObject(x, y, project:getAssetId(reference), request.name or reference and reference:match("([^/]+)%.[^.]+$") or "LObject"))
        assert(require("project.PrefabHierarchy").expandAuthoring(project, level, object))
        if request.parent ~= nil and request.parent ~= false then
            local parent = assert(level:findLObject(tonumber(request.parent)), "Parent instance not found")
            object.parentAuthoringId = parent.authoringId
        end
        changed = true
    elseif command == "instance.list" then
        local rows = {}
        for _, row in ipairs(level:treeRows()) do rows[#rows + 1] = {data = row.object, depth = row.depth, worldTransform = level:getWorldTransform(row.object)} end
        return {revision = revision(bytes), instances = rows}
    elseif command == "instance.duplicate" then
        local copies = level:duplicateLObjects(selected())
        object = copies[1]; changed = true
    elseif command == "instance.delete" then
        assert(level:removeLObjects(selected())); changed = true
    elseif command:match("^instance%.") then
        local id = tonumber(request.instance or request.instances and selected()[1].authoringId)
        assert(id, "Missing --instance")
        for _, candidate in ipairs(level.lobjects) do if candidate.authoringId == id then object = candidate end end
        assert(object, "Instance not found")
        local definition = assert(require("project.PrefabHierarchy").authoringDefinition(project, level, object))
        target = assert(require("project.ObjectDefinition").inspectorTarget(project, object, definition, level))
        if command == "instance.reparent" then
            local parent = request.parent ~= nil and request.parent ~= false and assert(level:findLObject(tonumber(request.parent)), "Parent instance not found") or nil
            assert(level:reparent(selected(), parent)); changed = true
        elseif command == "instance.rename" then
            local name = required(request, "name"); assert(type(name) == "string" and name ~= "", "Invalid instance name")
            object.name = name; changed = true
        elseif command == "instance.set" or command == "instance.reset" then
            local name = required(request, "property")
            local item
            if command == "instance.set" then item = value(request)
            elseif name:match("^transform%.") then
                local defaults = assert(require("core.Transform").copy({x = 0, y = 0}))
                if object.prefabRootId and object.prefabRootId ~= object.authoringId then
                    local root = assert(level:findLObject(object.prefabRootId))
                    local node = assert(require("project.PrefabHierarchy").resolve(project, root.definitionReference)).byPath[object.prefabNodePath]
                    if node then defaults = node.transform end
                end
                item = defaults[name:match("^transform%.(.+)$")]
            else item = assert(target.class.properties[name], "Unknown property: " .. name).default end
            local transformField = name:match("^transform%.(.+)$")
            if transformField then
                assert(object.transform[transformField] ~= nil, "Unknown Transform field")
                local copy = require("project.PropertyData").copy(object.transform); copy[transformField] = item
                object.transform = assert(require("core.Transform").copy(copy))
            else setProperty(project, target, name, item) end
            changed = true
        else assert(command == "instance.get", "Unknown command: " .. command) end
    elseif command == "level.view" then
        local result = require("editor.CliView").execute(project, level, request)
        result.revision = revision(bytes); return result
    elseif command == "level.pointer" then
        local result = require("editor.CliPointer").execute(project, level, request)
        result.revision = revision(bytes); return result
    elseif command == "level.validate" then
        local world = assert(require("runtime.WorldLoader").prepare(project, level:toData()))
        return {valid = true, objects = #world.lobjects, revision = revision(bytes)}
    elseif command == "level.set" or command == "level.get" or command == "level.reset" or command == "level.set-parent" then
        local class = level.scriptReference and assert(require("project.LuaClass").load(project, level.scriptReference, "level"))
        target = {class = class or {properties = {}}, level = level,
            getOverrides = function() return require("project.PropertyData").copy(level.propertyOverrides) end,
            setOverrides = function(_, values) level.propertyOverrides = values end}
        if command == "level.set-parent" then
            local parent = request.parent; if parent == "None" or parent == false then parent = nil end
            local nextClass = parent and assert(require("project.LuaClass").load(project, parent, "level"))
            level.scriptReference = parent and project:getAssetId(project:getAssetReference(parent)) or nil
            level.propertyOverrides = require("project.LuaClass").compatibleOverrides(nextClass, level.propertyOverrides)
            target.class = nextClass or {properties = {}}; changed = true
        elseif command ~= "level.get" then
            local name = required(request, "property")
            local item
            if command == "level.reset" then item = assert(target.class.properties[name], "Unknown property: " .. name).default else item = value(request) end
            setProperty(project, target, name, item); changed = true
        end
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
                x = true, y = true, output = true, revision = true, request = true, result = true, value = true,
                asset = true, destination = true, source = true, node = true, instances = true, input = true,
                event = true, button = true, dx = true, dy = true, ["events-json"] = true, width = true, height = true, space = true}
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
