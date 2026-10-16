local Scoped = require("project.ScopedScripts")
local Inspector = {}
Inspector.__index = Inspector
function Inspector.new(app)
    local self = setmetatable({app = app, levels = {}}, Inspector)
    if app.documentAssetId then self:rememberLevelDocument(app.document, app.documentAssetId) end
    app.project.draftLevelAssets = self.levels
    self.projectDocument = require("editor.ScopeDocument").new(app.project)
    app.histories[self.projectDocument] = require("editor.History").new(self.projectDocument:snapshot())
    return self
end
function Inspector:target(document, label, id)
    if self.document == document and self.cachedTarget then return self.cachedTarget end
    local data = document.level or document.data
    local level = document.level
    local target, err = Scoped.inspectorTarget(self.app.project, data, level, label)
    if not target then self.app.runtimeError = err; return nil end
    target.documentKey, target.scopeDocument = document, document
    target.readOnly = id and self.app.project:isReadOnly(id) or false
    target.isDirty = function() return document:isDirty() end
    target.label = level and "Level" or "Project"
    target.getDisplayName = function() return level and label or self.app.project.name end
    if level then
        local baseGet, baseSet = target.getOverrides, target.setOverrides
        target.getOverrides = function(current)
            local values = baseGet(current)
            for name, value in pairs(level.propertyOverrides or {}) do values[name] = value end
            return values
        end
        target.setOverrides = function(current, values)
            local scoped, legacy = {}, {}
            for name, value in pairs(values) do
                if name:find(".", 1, true) then scoped[name] = value
                elseif name ~= "$mainCamera" then legacy[name] = value end
            end
            baseSet(current, scoped); level.propertyOverrides = legacy
        end
        if level.scriptReference then
            local class = require("project.LuaScript").load(self.app.project, level.scriptReference, "level")
            for name, declaration in pairs(class and class.properties or {}) do target.class.properties[name] = declaration end
        end
        target.setMainCamera = function(_, value)
            if value ~= nil then
                local valid, errorText = require("project.MainCamera").copy(value)
                if errorText then return false, errorText end
                level.mainCamera = valid
            else level.mainCamera = nil end
            return true
        end
    end
    -- 부착 변경 뒤에도 문서·카메라·저장 정보가 같은 대상에 유지되도록 다시 합성한다.
    target.reloadTarget = function()
        local stable = self.cachedTarget or target
        self.cachedTarget = nil
        local fresh, reloadError = self:target(document, label, id)
        if not fresh then return nil, reloadError end
        for key, value in pairs(fresh) do stable[key] = value end
        self.cachedTarget = stable
        return stable
    end
    if target.readOnly then
        target.addScript, target.removeScript, target.moveScript, target.renameScript = nil, nil, nil, nil
    end
    self.document, self.cachedTarget = document, target
    return target
end
function Inspector:projectTarget() return self:target(self.projectDocument, "Project") end

function Inspector:rememberLevelDocument(document, id)
    local oldPath = document.path
    local ok, err = document:bindAsset(self.app.project, id)
    if not ok then return nil, err end
    -- Save As 후 같은 문서가 이전 에셋 ID에도 남지 않도록 연결을 옮긴다.
    for otherId, cached in pairs(self.levels) do
        if cached == document and otherId ~= id then self.levels[otherId] = nil end
    end
    self.levels[id] = document
    if oldPath ~= document.path and self.document == document then self.cachedTarget = nil end
    return document
end

function Inspector:syncPaths()
    for _, document in pairs(self.levels) do
        local oldPath = document.path
        document:refreshPath()
        if oldPath ~= document.path and self.document == document then self.cachedTarget = nil end
    end
end

function Inspector:getLevelDocument(id, reloadClean)
    local app = self.app
    local path, err = app.project:resolveAssetFile(id)
    if not path then return nil, err end
    local document = id == app.documentAssetId and app.document or self.levels[id]
    if not document or reloadClean and not document:isDirty() then
        local fresh, loadError = require("editor.LevelDocument").load(path)
        if not fresh then return nil, loadError end
        if not document then document = fresh
        elseif fresh.savedSnapshot ~= document.savedSnapshot then
            -- 외부 변경 전의 Undo가 새 파일 내용을 되돌리지 않도록 기록도 새로 시작한다.
            document.level, document.savedSnapshot, document.path = fresh.level, fresh.savedSnapshot, path
            app.histories[document] = nil
            if self.document == document then self.cachedTarget = nil end
            if app.document == document then app:setDocument(document) end
        end
    end
    if not app.histories[document] then
        app.histories[document] = require("editor.History").new(assert(require("editor.LevelFile").encode(document.level)))
    end
    return self:rememberLevelDocument(document, id)
end

function Inspector:levelTarget(id)
    local app = self.app
    local document, err = self:getLevelDocument(id)
    if not document then app.runtimeError = err; return nil end
    local path = app.project:getAssetReference(id)
    return self:target(document, path:match("([^/]+)%.level$"), id)
end
function Inspector:pickReference(target, field, kind)
    local choices = {{label = "None", value = false}}
    for _, object in ipairs(target.level.lobjects) do
        local label = object.name or "LObject " .. object.authoringId
        if kind == "camera" then
            local cameras, err = require("project.MainCamera").choices(self.app.project, target.level, object, true)
            if not cameras then return false, err end
            for _, camera in ipairs(cameras) do choices[#choices + 1] = {label = label .. " / " .. camera.name, value = camera} end
        elseif kind == "object" then choices[#choices + 1] = {label = label, value = object.authoringId}
        else
            local definition, err = require("project.PrefabHierarchy").authoringDefinition(self.app.project, target.level, object)
            if not definition then return false, err end
            for _, item in ipairs(definition.attachments) do
                choices[#choices + 1] = {label = label .. " / " .. item.name, value = {authoringId = object.authoringId, script = item.id}}
            end
        end
    end
    self.app.inspector:commitEdit(); self.app:recordHistory()
    require("editor.ui.Dialog").new(self.app.uiRoot, {title = "Choose a reference in this level", choices = choices, confirmLabel = "Select",
        message = "This level is not open in Scene View.", onConfirm = function(_, value)
            local ok, err
            if kind == "camera" then ok, err = target:setMainCamera(value ~= false and value or nil)
            else ok, err = self.app.inspector.classInspector:applyPicked(field, value) end
            if ok then self.app.inspector.classInspector:reload(); self.app:recordHistory() end
            return ok, err
        end})
    return true
end
return Inspector
