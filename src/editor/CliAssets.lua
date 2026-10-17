local Fs = require("editor.HostFileSystem")
local Json = require("project.Json")
local Operations = {}

function Operations.execute(project, request, api)
    local command = request.command
    if command == "project.validate" then
        return require("editor.ProjectValidation").run(project)
    end
    if command == "asset.list" then return {entries = assert(project:listDirectory(request.folder or "Assets"))} end
    if command == "class.list" then return {classes = assert(project:listScripts(request.type or "script"))} end
    if command == "folder.create" then
        local ok, reference = project:createEntry(api.required(request, "folder"), "folder", api.required(request, "name"))
        assert(ok, reference); return api.basicResult(project, reference)
    end
    if command == "asset.import" or command == "asset.copy" then
        local source
        if command == "asset.import" then source = api.absolute(api.required(request, "input"))
        else source = assert(project:resolveProjectFile(assert(project:getAssetReference(api.required(request, "asset"))))) end
        if command == "asset.import" then
            local ok, reference = require("editor.AssetImport").copy(project, source, request.folder or "Assets", request.name)
            assert(ok, reference); return api.basicResult(project, reference)
        end
        local info = assert(Fs.info(source)); assert(info.type == "file" and not info.isLink, "Expected a regular file")
        local folder = request.folder or "Assets"
        assert(not project:isReadOnly(folder), "Labo plugin assets are read-only")
        if command == "asset.copy" then
            local original = assert(project:getAssetReference(request.asset))
            assert(original:match("^[^/]+") == folder:match("^[^/]+"), "Keep the copy in its Assets root")
        end
        assert(project:listDirectory(folder))
        local name = request.name or source:match("([^/\\]+)$")
        assert(type(name) == "string" and not name:find("[/\\]"), "Name must not contain a path")
        local reference = folder .. "/" .. name
        assert(not require("editor.AssetRegistry").isInternal(reference), "Metadata cannot be imported separately")
        local destination = assert(project:resolvePath(reference))
        assert(require("editor.AssetCatalog").checkDestination(project, reference))
        local metadata, metadataError = Fs.info(destination .. ".meta")
        assert(not metadata and not metadataError, metadataError or "Destination metadata already exists")
        assert(Fs.createFile(destination, assert(Fs.read(source))))
        local metadata = {}
        for key, value in pairs(project.assetMetadata[assert(project:getAssetReference(request.asset))] or {}) do metadata[key] = value end
        metadata.id, metadata.scriptName = require("project.AssetId").new(), nil
        local saved, saveError = require("editor.AssetCatalog").update(project, {[reference] = metadata})
        if not saved then Fs.removeFile(destination); error(saveError) end
        local indexed, err = project:rebuildAssetIndex()
        if not indexed then
            require("editor.AssetCatalog").remove(project, reference); Fs.removeFile(destination); error(err)
        end
        return api.basicResult(project, reference)
    end
    if command:match("^class%.") and command ~= "class.create" then
        local reference = assert(project:getAssetReference(api.required(request, "class")))
        local path = assert(project:resolveSourceFile(reference))
        local bytes = assert(Fs.read(path)); api.checkRevision(request, bytes)
        local kind = assert(project:getScriptKind(reference))
        if command == "class.set-source" then
            assert(not project:isReadOnly(reference), "Labo plugin assets are read-only")
            local text = api.required(request, "source")
            assert(type(text) == "string", "Source must be a string")
            local view = setmetatable({readSource = function(_, requested)
                if project:getAssetReference(requested) == reference then return text end
                return project:readSource(requested)
            end}, {__index = project})
            assert(require("project.LuaScript").load(view, reference, kind))
            assert(assert(Fs.read(path)) == bytes, "Revision conflict: file changed while editing")
            assert(Fs.writeAtomic(path, text)); bytes = text
        else assert(command == "class.get", "Unknown command: " .. command) end
        local class = assert(require("project.LuaScript").load(project, reference, kind))
        local result = api.basicResult(project, reference)
        result.source, result.kind, result.schema, result.parent, result.revision = bytes, kind, class.properties, class.extends, api.revision(bytes)
        return result
    end
    if not command:match("^asset%.") then return nil end
    local reference = assert(project:getAssetReference(api.required(request, "asset")))
    local missing
    for _, entry in ipairs(project.missingAssets or {}) do if entry.reference == reference then missing = entry end end
    if command == "asset.delete" and missing then
        assert(not request.revision, "Missing files have no content revision")
        local ok, err = project:deleteEntry(reference)
        assert(ok, err)
        return {deleted = reference}
    end
    local path, info = project:checkedEntry(reference); assert(path, info)
    local bytes = info.type == "file" and assert(Fs.read(path))
    if request.revision then assert(bytes, "Folder revisions are not supported"); api.checkRevision(request, bytes) end
    if command == "asset.get" then
        local result = api.basicResult(project, reference)
        result.type, result.metadata, result.revision = info.type, project.assetMetadata[reference], bytes and api.revision(bytes)
        return result
    end
    if command == "asset.delete" then
        local ok, err = project:deleteEntry(reference); assert(ok, err)
        return {deleted = reference}
    end
    local destination
    if command == "asset.move" then destination = api.required(request, "destination")
    elseif command == "asset.rename" then
        local name = api.required(request, "name")
        assert(type(name) == "string" and not name:find("[/\\]"), "Name must not contain a path")
        local extension = info.type == "file" and reference:match("(%.[^/.]+)$") or ""
        if extension ~= "" and name:sub(-#extension) ~= extension then name = name .. extension end
        destination = reference:match("^(.*)/[^/]+$") .. "/" .. name
    else error("Unknown command: " .. command) end
    local ok, result = project:moveEntry(reference, destination); assert(ok, result)
    return api.basicResult(project, destination)
end
return Operations
