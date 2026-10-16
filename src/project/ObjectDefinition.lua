local LuaScript = require("project.LuaScript")
local Transform = require("core.Transform")
local Attachments = require("project.ScriptAttachments")
local Copy = require("project.PropertyData")
local Schema = require("core.PropertySchema")
local Definition = {}
-- 키 호환은 각 계층을 합치기 전에 적용해야 자식의 이전 키가 부모의 새 키를 덮어쓴다.
local function mergeOverrides(target, values, attachment, loader)
    local schema = {}
    if attachment then
        local class, err = loader(attachment.source, "script")
        if not class then return false, err end
        schema = class.properties
    end
    for name, value in pairs(values) do
        local normalized = Schema.overrideName(schema, name)
        if normalized == name or values[normalized] == nil then target[normalized] = value end
    end
    return true
end
function Definition.mergeScriptOverrides(target, layer, attachments, loader)
    for id, values in pairs(layer or {}) do
        local attachment = Attachments.find(attachments, id)
        id = attachment and attachment.id or id
        target[id] = target[id] or {}
        local ok, err = mergeOverrides(target[id], values, attachment, loader)
        if not ok then return false, err end
    end
    return true
end
function Definition.resolve(project, reference, loader, excludedId)
    loader = loader or LuaScript.loader(project)
    local layers, visiting = {}, {}
    local function visit(current, depth)
        if not current or current == false then return true end
        if depth > 64 then return nil, "Prefab inheritance is too deep" end
        local path, err = project:getAssetReference(current)
        if not path then return nil, err end
        if not path:match("^Assets/.+%.prefab$") then return nil, "Object sources must be Prefabs; attach Lua scripts separately" end
        local id = project:getAssetId(path) or path
        if visiting[id] or id == excludedId then return nil, "Prefab inheritance cycle" end
        visiting[id] = true
        local bytes, readError = project:readAsset(id)
        if not bytes then return nil, readError end
        local data, decodeError = require("project.Prefab").decode(bytes)
        if not data then return nil, decodeError end
        local ok, parentError = visit(data.definitionReference, depth + 1)
        if not ok then return nil, parentError end
        layers[#layers + 1] = data; visiting[id] = nil
        return true
    end
    local ok, err = visit(reference, 0)
    if not ok then return nil, err end
    local result = {properties = {}, scripts = {}, attachments = {}, removedScripts = {}, layers = layers, scriptLoader = loader}
    for _, layer in ipairs(layers) do
        result.attachments = Attachments.merge(result.attachments, layer.scripts, layer.removedScripts)
        result.attachments = Attachments.reorder(result.attachments, layer.scriptOrder)
        local merged, mergeError = Definition.mergeScriptOverrides(result.scripts, layer.overrides.scripts, result.attachments, loader)
        if not merged then return nil, mergeError end
        for _, id in ipairs(layer.removedScripts or {}) do result.scripts[id] = nil; result.removedScripts[id] = true end
        for _, attachment in ipairs(layer.scripts or {}) do result.removedScripts[attachment.id] = nil end
    end
    return result
end
function Definition.withAttachments(definition, scripts, removed)
    local result = {}
    for key, value in pairs(definition) do result[key] = value end
    result.attachments = Attachments.merge(definition.attachments, scripts, removed)
    result.scripts = Copy.copyScripts(definition.scripts)
    result.removedScripts = Copy.copy(definition.removedScripts)
    for _, id in ipairs(removed or {}) do result.scripts[id] = nil; result.removedScripts[id] = true end
    for _, attachment in ipairs(scripts or {}) do result.removedScripts[attachment.id] = nil end
    return result
end
function Definition.configure(object, definition, propertyOverrides, scriptOverrides, attachments)
    object.scriptLoader = definition.scriptLoader
    local list = Attachments.merge(definition.attachments, attachments)
    local fields, present = {}, {}
    local ok, err = pcall(function()
        for _, layer in ipairs({definition.scripts or {}, scriptOverrides or {}}) do
            local merged, mergeError = Definition.mergeScriptOverrides(fields, layer, list, definition.scriptLoader)
            assert(merged, mergeError)
        end
        for _, attachment in ipairs(list) do
            local class, loadError = definition.scriptLoader(attachment.source, "script")
            assert(class, loadError)
            local script = require("core.ScriptRuntime").attach(object, attachment.id, class, fields[attachment.id], attachment.name or attachment.label or attachment.id)
            script.source, script.label = attachment.source, attachment.label
            present[attachment.id] = true
        end
        for id in pairs(fields) do assert(present[id], "Unknown script: " .. id) end
    end)
    if not ok then return false, tostring(err) end
    return true
end
function Definition.resolveReferences(values, schema, objects, project)
    for name, declaration in pairs(schema or {}) do
        local value = values[name]
        if declaration.type == "script" and value ~= false then
            if not value.owner then
                local object = objects[value.authoringId]
                local script = object and (object:getScriptById(value.script) or object:getScriptByName(value.script))
                if not script then return false, "Missing script reference" end
                values[name] = script
            end
        elseif declaration.type == "object" and value ~= false then
            local resolved = false
            if type(value) == "table" then
                for _, object in pairs(objects) do if object == value then resolved = true; break end end
            end
            if not resolved then
            if not objects[value] then return false, "Missing LObject reference: " .. tostring(value) end
            values[name] = objects[value]
            end
        elseif (Schema.isResource(declaration.type) or Schema.isTemplate(declaration.type)) and value ~= false then
            local path, err
            if Schema.isTemplate(declaration.type) then path, err = require("project.LObjectTemplate").source(project, value)
            else path, err = project:resolveAssetFile(value) end
            if not path then return false, err end
            if declaration.type == "audio" then
                local valid, audioError = require("project.AssetData").validateAudio(project, value)
                if not valid then return false, audioError end
            end
            values[name] = project:getAssetId(value) or value
        end
    end
    return true
end

function Definition.inspectorTarget(project, data, definition, level, label)
    local object = assert(require("core.LObject").new(1, {transform = data.transform or {x = 0, y = 0}}))
    local ok, err = Definition.configure(object, definition, nil, nil, data.scripts)
    if not ok then return nil, err end
    local schema, scriptTypes = {}, {}
    if data.transform then
        local defaults = assert(Transform.copy({x = 0, y = 0}))
        for field in pairs(Transform.FIELDS) do
            schema["$transform." .. field] = {type = "number", default = defaults[field], field = field, rootTransform = true, sceneTransform = true, group = "Transform"}
        end
    end
    for _, id in ipairs(object.scriptOrder) do
        local script = object.scripts[id]
        scriptTypes[id] = script.label or script.scriptType or LuaScript.name(getmetatable(script)) or "Script"
        for field, declaration in pairs(getmetatable(script).properties) do
            schema[id .. "." .. field] = {type = declaration.type, default = script.properties[field], script = id, field = field, group = declaration.group}
        end
    end
    local target = {data = data, kind = "lobject", label = label, hideParent = true, instance = true, level = level,
        class = {properties = schema, scriptTypes = scriptTypes, className = "LObject"}, preview = object,
        resolveScriptReference = function(_, value)
            if type(value) ~= "table" or not level then return value end
            local referenced = level:findLObject(value.authoringId)
            local referencedDefinition = referenced and require("project.PrefabHierarchy").authoringDefinition(project, level, referenced)
            local attachment = referencedDefinition and Attachments.find(referencedDefinition.attachments, value.script)
            return attachment and {authoringId = value.authoringId, script = attachment.id} or value
        end,
        getOverrides = function(target)
            local values = {}
            for id, fields in pairs(target.data.scriptOverrides or {}) do
                local script = target.preview:getScriptById(id) or target.preview:getScriptByName(id)
                id = script and script.id or id
                for field, value in pairs(fields) do
                    local normalized = script and Schema.overrideName(getmetatable(script).properties, field) or field
                    if normalized == field or fields[normalized] == nil then values[id .. "." .. normalized] = value end
                end
            end
            if target.data.transform then
                for field in pairs(Transform.FIELDS) do values["$transform." .. field] = target.data.transform[field] end
            end
            return values
        end,
        setOverrides = function(target, values)
            local scripts = {}
            local transform = target.data.transform and assert(Transform.copy(target.data.transform))
            for name, value in pairs(values) do
                local id, field = name:match("^(.*)%.([^.]+)$")
                local script = id and (target.preview:getScriptById(id) or target.preview:getScriptByName(id))
                id = script and script.id or id
                local declaration = id and schema[id .. "." .. field]
                if declaration and declaration.type == "script" and type(value) == "table" and level and not level.prefabScope then
                    value = target:resolveScriptReference(value)
                end
                if id == "$transform" then if transform then transform[field] = value end
                elseif id then scripts[id] = scripts[id] or {}; scripts[id][field] = value end
            end
            if transform then
                for field in pairs(Transform.FIELDS) do
                    local key = "$transform." .. field
                    if values[key] == nil then transform[field] = schema[key].default end
                end
                target.data.transform = assert(Transform.copy(transform))
            end
            target.data.propertyOverrides, target.data.scriptOverrides = {}, scripts
        end}
    if level and not level.prefabScope then require("project.InstanceScripts").bind(project, target) end
    return target
end
return Definition
