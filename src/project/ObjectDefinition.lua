local LuaClass = require("project.LuaClass")
local Schema = require("core.PropertySchema")
local Transform = require("core.Transform")
local Definition = {}

local function componentForOverrides(object, name, fields)
    local component = object.components[name]
    if component or name ~= "root" then return component end
    -- 기본 root를 다른 이름의 루트로 교체한 프로젝트에도 과거 루트 offset 무시 규칙을 적용한다.
    -- 일반 프로퍼티나 삭제된 다른 컴포넌트까지 새 루트로 연결하지 않는다.
    for field in pairs(fields) do if not Transform.FIELDS[field] then return nil end end
    return object.rootComponent
end

function Definition.resolve(project, reference, loadClass, excludedId)
    loadClass = loadClass or LuaClass.loader(project)
    local properties, components = {}, {}
    local class, classReference
    local visiting, chain = {}, {}
    local function resolve(current, depth)
        if not current then return true end
        if depth > 64 then return nil, "Prefab inheritance is too deep" end
        local reference = current
        local path, err = project:getAssetReference(reference)
        if not path then return nil, err end
        if path:match("^Assets/.+%.prefab$") then
            local key = project:getAssetId(path) or path
            if key == excludedId then return nil, "Prefab inheritance cycle: " .. path end
            if visiting[key] then return nil, "Prefab inheritance cycle: " .. path end
            visiting[key] = true
            local bytes, readError = project:readAsset(reference)
            if not bytes then return nil, readError end
            local prefab, prefabError = require("project.Prefab").decode(bytes)
            if not prefab then return nil, prefabError end
            local ok, parentError = resolve(prefab.definitionReference, depth + 1)
            if not ok then return nil, parentError end
            chain[#chain + 1] = prefab
            for name, value in pairs(prefab.overrides.properties or {}) do properties[name] = value end
            for name, fields in pairs(prefab.overrides.components or {}) do
                components[name] = components[name] or {}
                for field, value in pairs(fields) do components[name][field] = value end
            end
            visiting[key] = nil
        else
            local err
            class, err = loadClass(reference, "lobject")
            if not class then return nil, err end
            classReference = project:getAssetId(path) or path
        end
        return true
    end
    local ok, err = resolve(reference, 0)
    if not ok then return nil, err end
    -- 각 단계의 잘못된 override도 검사한다. 자식 값으로 덮여 오류가 숨겨지지 않게 한다.
    for _, prefab in ipairs(chain) do
        local valid, errorText = LuaClass.values(class, prefab.overrides.properties)
        if not valid then return nil, errorText end
    end
    return {class = class, classReference = classReference, properties = properties, components = components, layers = chain, componentLoader = loadClass}
end

function Definition.configure(object, definition, propertyOverrides, componentOverrides)
    local properties = require("project.PropertyData").copy(definition.properties)
    for name, value in pairs(propertyOverrides or {}) do properties[name] = value end
    local values, err = LuaClass.values(definition.class, properties)
    if not values then return false, err end
    object.luaClass, object.properties = definition.class, values
    object.componentLoader = definition.componentLoader
    if definition.class and definition.class.build then
        local ok, result, buildError = pcall(definition.class.build, object)
        if not ok or result == false then return false, tostring(ok and buildError or result) end
    end
    -- 구성 함수는 한 번만 실행하고 각 부모 단계의 컴포넌트 값도 같은 스키마로 검사한다.
    for _, layer in ipairs(definition.layers or {}) do
        for name, fields in pairs(layer.overrides.components or {}) do
            local component = componentForOverrides(object, name, fields)
            if not component then return false, "Unknown component: " .. name end
            local valid, errorText = Schema.values(getmetatable(component).properties, fields)
            if not valid then return false, errorText end
        end
    end
    local components = require("project.PropertyData").copyComponents(definition.components)
    for name, fields in pairs(componentOverrides or {}) do
        components[name] = components[name] or {}
        for field, value in pairs(fields) do components[name][field] = value end
    end
    for name, fields in pairs(components) do
        local component = componentForOverrides(object, name, fields)
        if not component then return false, "Unknown component: " .. name end
        local valid, validationError = Schema.values(getmetatable(component).properties, fields)
        if not valid then return false, validationError end
        local merged = {}
        for field in pairs(getmetatable(component).properties) do merged[field] = component.properties[field] end
        for field, value in pairs(fields) do
            -- 루트는 배치 Transform만 사용한다. 기존 컴포넌트 override의 루트 offset은 적용하지 않는다.
            if component ~= object.rootComponent or not Transform.FIELDS[field] then merged[field] = value end
        end
        local resolved, fieldError = Schema.values(getmetatable(component).properties, merged)
        if not resolved then return false, fieldError end
        if component:isA(require("core.SceneComponent")) then
            local applied, applyError = pcall(component.setProperties, component, resolved)
            if not applied then return false, tostring(applyError) end
        else component.properties = resolved end
    end
    return true
end

-- 참조는 모든 객체를 구성한 다음 해석한다. 순환·전방 참조도 같은 객체를 가리킨다.
function Definition.resolveReferences(values, schema, objects, project)
    for name, declaration in pairs(schema or {}) do
        local value = values[name]
        if declaration.type == "object" and value ~= false then
            local resolved = false
            if type(value) == "table" then
                for _, object in pairs(objects) do if object == value then resolved = true; break end end
            end
            if not resolved then
            if not objects[value] then return false, "Missing LObject reference: " .. tostring(value) end
            values[name] = objects[value]
            end
        elseif (declaration.type == "image" or Schema.isTemplate(declaration.type)) and value ~= false then
            local path, err
            if Schema.isTemplate(declaration.type) then path, err = require("project.LObjectTemplate").source(project, value)
            else path, err = project:resolveAssetFile(value) end
            if not path then return false, err end
            values[name] = project:getAssetId(value) or value
        end
    end
    return true
end

function Definition.inspectorTarget(project, data, definition, level, label)
    local object = assert(require("core.LObject").new(1, {transform = {x = 0, y = 0}}))
    local ok, err = Definition.configure(object, definition)
    if not ok then return nil, err end
    local schema, componentTypes = {}, {}
    for name, field in pairs(definition.class and definition.class.properties or {}) do
        schema[name] = {type = field.type, default = object.properties[name], group = field.group}
    end
    for _, name in ipairs(object.componentOrder) do
        local component = object.components[name]
        local scene = component:isA(require("core.SceneComponent"))
        componentTypes[name] = component.componentType
        for field, declaration in pairs(getmetatable(component).properties) do
            local rootTransform = component == object.rootComponent and Transform.FIELDS[field]
            if not rootTransform or data.transform then
                schema[name .. "." .. field] = {type = declaration.type, default = component.properties[field], component = name, field = field,
                    sceneTransform = scene and Transform.FIELDS[field] or nil, rootTransform = rootTransform or nil, group = declaration.group}
            end
        end
    end
    return {data = data, kind = "lobject", label = label, hideParent = true, instance = true, level = level,
        class = {properties = schema, componentTypes = componentTypes, className = LuaClass.name(definition.class) or "LObject"}, preview = object,
        getOverrides = function(target)
            local result = require("project.PropertyData").copy(target.data.propertyOverrides)
            for name, fields in pairs(target.data.componentOverrides or {}) do
                for field, value in pairs(fields) do
                    if name ~= object.rootComponent.name or not Transform.FIELDS[field] then result[name .. "." .. field] = value end
                end
            end
            if target.data.transform then
                for field in pairs(Transform.FIELDS) do result[object.rootComponent.name .. "." .. field] = target.data.transform[field] end
            end
            return result
        end,
        setOverrides = function(target, values)
            local properties, components = {}, {}
            local transform = target.data.transform and assert(Transform.copy(target.data.transform))
            for key, value in pairs(values) do
                local name, field = key:match("^([^.]+)%.(.+)$")
                if name == object.rootComponent.name and Transform.FIELDS[field] then
                    if transform then transform[field] = value end
                elseif name then components[name] = components[name] or {}; components[name][field] = value
                else properties[key] = value end
            end
            if transform then
                -- 리셋으로 생략된 루트 필드는 schema 기본값을 사용한다.
                for field in pairs(Transform.FIELDS) do
                    local key = object.rootComponent.name .. "." .. field
                    if values[key] == nil then transform[field] = schema[key].default end
                end
                target.data.transform = assert(Transform.copy(transform))
            end
            target.data.propertyOverrides, target.data.componentOverrides = properties, components
        end}
end
return Definition
