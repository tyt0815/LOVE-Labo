-- GUI와 CLI에서 게임 load 없이 같은 배치·참조 그래프를 평가한다.
local Layout = {}
Layout.__index = Layout
function Layout.new(project, level)
    return setmetatable({project = project, level = level, previews = setmetatable({}, {__mode = "k"})}, Layout)
end
function Layout:clear()
    for _, cache in pairs(self.previews) do
        if cache.object then for _, script in pairs(cache.object.scripts) do require("core.Bindings").release(script) end end
    end
    self.previews, self.error = setmetatable({}, {__mode = "k"}), nil
end
function Layout:linkPreview(data, cache)
    local object = cache.object
    if not object or cache.linking then return object end
    cache.linking = true
    local ok, err = pcall(function()
        object.parent = self.level and self.level:getParent(data) and self:preview(self.level:getParent(data)) or nil
        for _, reference in ipairs(cache.references) do
            local target = self.level and self.level:findLObject(reference.authoringId)
            local preview = target and self:preview(target)
            local value = preview
            if preview and reference.targetScript then
                value = preview:getScriptById(reference.targetScript) or preview:getScriptByName(reference.targetScript)
            end
            reference.script.properties[reference.field] = value or false
        end
    end)
    cache.linking = nil
    if not ok then self.error = tostring(err); return nil end
    return object
end
function Layout:preview(data)
    local signature = tostring(self.project.draftRevision or 0) .. require("project.Json").encode(data)
    local cache = self.previews[data]
    if cache and cache.signature == signature then
        return self:linkPreview(data, cache)
    end
    local Definition = require("project.ObjectDefinition")
    local definition, err
    if self.level then definition, err = require("project.PrefabHierarchy").authoringDefinition(self.project, self.level, data)
    else definition, err = Definition.resolve(self.project, data.definitionReference) end
    local object = assert(require("core.LObject").new(1, data))
    local ok, configureError
    if definition then ok, configureError = Definition.configure(object, definition, data.propertyOverrides, data.scriptOverrides) end
    local references = {}
    if ok then for _, script in pairs(object.scripts) do
        for field, declaration in pairs(getmetatable(script).properties) do
            local value = script.properties[field]
            if value ~= false and (declaration.type == "script" or declaration.type == "object") then
                references[#references + 1] = {script = script, field = field,
                    authoringId = declaration.type == "script" and value.authoringId or value,
                    targetScript = declaration.type == "script" and value.script or nil}
            end
        end
    end end
    local cache = {signature = signature, object = ok and object or nil, references = references}
    self.previews[data] = cache
    if not ok then self.error = err or configureError end
    return self:linkPreview(data, cache)
end
return Layout
