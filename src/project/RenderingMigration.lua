-- 과거 제공 스크립트의 저장 데이터만 명시적으로 변환한다. Runtime에서는 역할을 자동 추론하지 않는다.
local Migration = {}
function Migration.run(project, dryRun)
    local Json, Fs = require("project.Json"), require("editor.HostFileSystem")
    local Attachments = require("project.ScriptAttachments")
    local Definition = require("project.ObjectDefinition")
    local loader = require("project.LuaScript").loader(project)
    local classes = {}
    for _, name in ipairs({"Camera", "Canvas", "View"}) do
        local entry = project.plugins.scripts[name]
        if entry then classes[name] = assert(loader(entry.id, "script")) end
    end
    local function isA(attachment, name)
        local class = assert(loader(attachment.source, "script"))
        while class do if class == classes[name] then return true end; class = class.super end
        return false
    end
    local function attachments(data)
        local definition = assert(Definition.resolve(project, data.definitionReference))
        return Attachments.merge(definition.attachments, data.scripts, data.removedScripts)
    end
    local function fields(data, list, prefab)
        local values = prefab and data.overrides and data.overrides.scripts or data.scriptOverrides
        for key, value in pairs(values or {}) do
            local script = Attachments.find(list, key)
            if script and isA(script, "Canvas") and value.matchViewport ~= nil then
                if value.matchCamera == nil then value.matchCamera = value.matchViewport end
                value.matchViewport = nil
            end
            if script and isA(script, "View") then value.includeWorld, value.includeScreen = nil, nil end
        end
    end
    local changes = {}
    local paths = {}; for path in pairs(project.assetMetadata) do if path:match("%.level$") or path:match("%.prefab$") then paths[#paths + 1] = path end end
    table.sort(paths)
    for _, path in ipairs(paths) do
        local original = assert(project:readAsset(path))
        local data = assert(Json.decode(original))
        local before = assert(Json.encode(data))
        if path:match("%.level$") then
            local cameras, canvases, hasView = {}, {}, false
            for _, object in ipairs(data.lobjects or {}) do
                local list = attachments(object); fields(object, list)
                for _, script in ipairs(list) do
                    if isA(script, "Camera") then cameras[#cameras + 1] = {object = object, script = script} end
                    if isA(script, "Canvas") then canvases[#canvases + 1] = {object = object, script = script} end
                    hasView = hasView or isA(script, "View")
                end
            end
            for _, script in ipairs(data.scripts or {}) do hasView = hasView or isA(script, "View") end
            fields(data, data.scripts or {})
            local selected
            for _, camera in ipairs(cameras) do
                if data.mainCamera and data.mainCamera.authoringId == camera.object.authoringId
                    and (data.mainCamera.script == camera.script.id or data.mainCamera.script == camera.script.name) then selected = camera; break end
            end
            if not selected and (data.mainCamera or #canvases > 0) then selected = cameras[1] end
            if selected then
                if not hasView then
                    local id = require("project.AssetId").new()
                    selected.object.scripts = selected.object.scripts or {}
                    local name, suffix = "Migrated View", 1
                    while Attachments.find(attachments(selected.object), name) do suffix = suffix + 1; name = "Migrated View " .. suffix end
                    selected.object.scripts[#selected.object.scripts + 1] = {id = id, name = name, source = project.plugins.scripts.View.id}
                    selected.object.scriptOverrides = selected.object.scriptOverrides or {}
                    selected.object.scriptOverrides[id] = {cameraSource = {authoringId = selected.object.authoringId, script = selected.script.id}}
                end
                for _, canvas in ipairs(canvases) do
                    local object = canvas.object
                    local values = object.scriptOverrides or {}
                    local existing = values[canvas.script.id] and values[canvas.script.id].cameraSource
                    local parent, cameraParent = object, false
                    while parent.parentAuthoringId do
                        local nextParent
                        for _, item in ipairs(data.lobjects) do if item.authoringId == parent.parentAuthoringId then nextParent = item; break end end
                        if not nextParent then break end
                        parent = nextParent
                        for _, camera in ipairs(cameras) do if camera.object == parent then cameraParent = true end end
                    end
                    if not cameraParent and (existing == nil or existing == false) then
                        object.scriptOverrides = values
                        values[canvas.script.id] = values[canvas.script.id] or {}
                        values[canvas.script.id].cameraSource = {authoringId = selected.object.authoringId, script = selected.script.id}
                    end
                    if object ~= selected.object and not object.parentAuthoringId and (not object.prefabRootId or object.prefabRootId == object.authoringId) then
                        object.parentAuthoringId = selected.object.authoringId
                    end
                end
            end
            data.mainCamera = nil
        else
            fields(data, attachments(data), true)
            local recipe = assert(require("project.PrefabHierarchy").resolve(project, path))
            local function children(records, prefix)
                for _, record in ipairs(records or {}) do
                    local current = prefix .. "/" .. record.id
                    local node = recipe.byPath[current]
                    if node then fields(record, node.definition.attachments, true) end
                    children(record.children, current)
                end
            end
            children(data.children, "root")
        end
        if assert(Json.encode(data)) ~= before then changes[#changes + 1] = {path = path, original = original, bytes = assert(Json.encode(data, true)) .. "\n"} end
    end
    if not dryRun then
        for _, change in ipairs(changes) do assert(assert(project:readAsset(change.path)) == change.original, "Migration revision conflict") end
        for _, change in ipairs(changes) do assert(Fs.writeAtomic(assert(project:resolveAssetFile(change.path)), change.bytes)) end
        assert(project:rebuildAssetIndex())
    end
    local paths = {}; for _, change in ipairs(changes) do paths[#paths + 1] = change.path end
    return {changed = paths, dryRun = dryRun == true}
end
return Migration
