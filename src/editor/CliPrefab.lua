local Fs = require("editor.HostFileSystem")
local Hierarchy = require("project.PrefabHierarchy")
local Operations = {}

function Operations.execute(project, request, api)
    local reference = api.required(request, "prefab")
    local document = assert(require("editor.PrefabDocument").load(project, reference))
    local path = assert(project:resolveAssetFile(reference))
    local bytes = assert(Fs.read(path)); api.checkRevision(request, bytes)
    project.draftAssets = {[document.assetId] = document}
    local editor = require("editor.PrefabEditor").new(project, document, function() end, function() end)
    local nodePath = request.node or "root"
    local recipe = assert(editor:recipe()); assert(recipe.byPath[nodePath], "Prefab node not found")
    local target = assert(editor:target(nodePath))
    local command, changed = request.command, false
    if command == "prefab.set" or command == "prefab.reset" then
        local name = api.propertyName(target, api.required(request, "property"))
        local declaration = assert(target.class.properties[name], "Unknown property: " .. name)
        local item
        if command == "prefab.reset" then item = declaration.default else item = api.value(request) end
        if declaration.type == "object" and type(item) == "string" then item = assert(target.scopeByPath[item], "Prefab object path not found").authoringId end
        api.setProperty(project, target, name, item); changed = true
    elseif command == "prefab.set-parent" then
        assert(nodePath == "root" or not recipe.byPath[nodePath].isInherited, "Inherited object sources cannot be changed")
        local parent = request.parent
        if parent == "None" or parent == false then parent = nil end
        if parent then parent = assert(project:getAssetId(assert(project:getAssetReference(parent))), "Parent asset is not registered") end
        local defaults = assert(target.parentDefaults(parent))
        target.setParentReference(parent)
        target:setOverrides(require("project.LuaScript").compatibleOverrides(defaults.class, target:getOverrides()), defaults)
        changed = true
    elseif command == "prefab.script.add" then
        local ok, id = editor:addScript(nodePath, api.required(request, "source"), request.script)
        assert(ok, id); changed = true
    elseif command == "prefab.script.rename" then
        local ok, err = editor:renameScript(nodePath, api.required(request, "script"), api.required(request, "name"))
        assert(ok, err); changed = true
    elseif command == "prefab.script.remove" then
        local ok, err = editor:removeScript(nodePath, api.required(request, "script"))
        assert(ok, err); changed = true
    elseif command == "prefab.script.move" then
        local ok, err = editor:moveScript(nodePath, api.required(request, "script"), tonumber(api.required(request, "index")))
        assert(ok, err); changed = true
    elseif command == "prefab.child.add" then
        local ok, err, childPath
        if request.instance then
            local level = assert(require("editor.LevelDocument").load(assert(project:resolveAssetFile(request.level or project.defaultLevelReference)))).level
            local object = assert(level:findLObject(tonumber(request.instance)), "Instance not found")
            ok, err, childPath = editor:addInstance(level, object, nodePath)
        elseif request.template or request.class then ok, err, childPath = editor:add(request.template or request.class, nodePath)
        else ok, err, childPath = editor:insertChild(nil, request.name or "LObject", nodePath) end
        assert(ok, err); nodePath = childPath; changed = true
    elseif command == "prefab.child.move" then
        local ok, err = editor:dropObject(nodePath, request.destination, request.mode or "attach")
        assert(ok, err); nodePath = editor.selected; changed = true
    elseif command == "prefab.child.remove" then
        assert(not recipe.byPath[nodePath].isInherited, "Inherited objects cannot be removed")
        assert(nodePath ~= "root", "Cannot remove the Prefab root")
        document.data.removedPaths = document.data.removedPaths or {}
        document.data.removedPaths[#document.data.removedPaths + 1] = nodePath
        local bindings = {}
        for _, binding in ipairs(document.data.bindings or {}) do
            if not Hierarchy.isRemoved(binding.from, {nodePath}) then bindings[#bindings + 1] = binding end
        end
        document.data.bindings = bindings; document.data.formatVersion = 4
        nodePath = "root"; changed = true
    elseif command == "prefab.child.rename" then
        assert(editor:renameObject(nodePath, api.required(request, "name")))
        document.data.formatVersion = 4; changed = true
    else assert(command == "prefab.get" or command == "prefab.tree", "Unknown command: " .. command) end
    if changed then
        document.data.overrides.properties = document.data.overrides.properties or {}
        document.data.overrides.scripts = document.data.overrides.scripts or {}
        assert(editor:recipe())
        assert(require("runtime.WorldLoader").validate(project, {lobjects = {{authoringId = 1, transform = {x = 0, y = 0}, definitionReference = document.assetId}}}))
        assert(assert(Fs.read(path)) == bytes, "Revision conflict: file changed while editing")
        assert(document:save(project)); bytes = assert(Fs.read(path))
        target = assert(editor:target(nodePath))
    end
    local result = api.properties(target)
    result.revision, result.node, result.data = api.revision(bytes), nodePath, document.data
    result.nodes = {}
    for index, node in ipairs(assert(editor:recipe()).nodes) do
        result.nodes[index] = {id = index, path = node.path, parent = node.parent and node.parent.path,
            reference = node.reference, name = node.name, transform = node.transform}
    end
    return result
end
return Operations
