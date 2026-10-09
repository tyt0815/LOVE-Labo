local LuaClass = require("project.lua_class")
local Schema = require("core.property_schema")
local Definition = {}

function Definition.resolve(project, reference, loadClass)
    local properties, components = {}, {}
    if reference then
        local path, err = project:getAssetReference(reference)
        if not path then return nil, err end
        if path:match("^Assets/.+%.prefab$") then
            local file, fileError = project:resolveAssetFile(reference)
            if not file then return nil, fileError end
            local bytes, readError = project:readAsset(reference)
            if not bytes then return nil, readError end
            local prefab, prefabError = require("project.prefab").decode(bytes)
            if not prefab then return nil, prefabError end
            reference = prefab.definitionReference
            properties, components = prefab.overrides.properties or {}, prefab.overrides.components or {}
        end
    end
    local class, err
    if reference then class, err = (loadClass or LuaClass.loader(project))(reference, "lobject") end
    if reference and not class then return nil, err end
    return {class = class, properties = properties, components = components}
end

function Definition.configure(object, definition, propertyOverrides, componentOverrides)
    local properties = require("project.property_data").copy(definition.properties)
    for name, value in pairs(propertyOverrides or {}) do properties[name] = value end
    local values, err = LuaClass.values(definition.class, properties)
    if not values then return false, err end
    object.luaClass, object.properties = definition.class, values
    if definition.class and definition.class.build then
        local ok, result, buildError = pcall(definition.class.build, object)
        if not ok or result == false then return false, tostring(ok and buildError or result) end
    end
    local components = require("project.property_data").copyComponents(definition.components)
    for name, fields in pairs(componentOverrides or {}) do
        components[name] = components[name] or {}
        for field, value in pairs(fields) do components[name][field] = value end
    end
    for name, fields in pairs(components) do
        local component = object.components[name]
        if not component then return false, "Unknown component: " .. name end
        local merged = require("project.property_data").copy(component.properties)
        for field, value in pairs(fields) do merged[field] = value end
        local resolved, fieldError = Schema.values(getmetatable(component).properties, merged)
        if not resolved then return false, fieldError end
        component.properties = resolved
    end
    return true
end

-- 참조는 모든 객체를 구성한 다음 해석한다. 순환·전방 참조도 같은 객체를 가리킨다.
function Definition.resolveReferences(values, schema, objects, project)
    for name, declaration in pairs(schema or {}) do
        local value = values[name]
        if declaration.type == "object" and value ~= false then
            if not objects[value] then return false, "Missing LObject reference: " .. tostring(value) end
            values[name] = objects[value]
        elseif declaration.type == "image" and value ~= false then
            local path, err = project:resolveAssetFile(value)
            if not path then return false, err end
            values[name] = project:getAssetId(value) or value
        end
    end
    return true
end

function Definition.inspectorTarget(project, data, definition, level, label)
    local object = assert(require("core.lobject").new(1, {transform = {x = 0, y = 0}}))
    local ok, err = Definition.configure(object, definition)
    if not ok then return nil, err end
    local schema, componentTypes = {}, {}
    for name, field in pairs(definition.class and definition.class.properties or {}) do
        schema[name] = {type = field.type, default = object.properties[name]}
    end
    for _, name in ipairs(object.componentOrder) do
        local component = object.components[name]
        componentTypes[name] = component.componentType
        for field, declaration in pairs(getmetatable(component).properties) do
            schema[name .. "." .. field] = {type = declaration.type, default = component.properties[field], component = name, field = field}
        end
    end
    return {data = data, kind = "lobject", label = label, hideParent = true, instance = true, level = level,
        class = {properties = schema, componentTypes = componentTypes, className = LuaClass.name(definition.class) or "LObject"}, preview = object,
        getOverrides = function(target)
            local result = require("project.property_data").copy(target.data.propertyOverrides)
            for name, fields in pairs(target.data.componentOverrides or {}) do
                for field, value in pairs(fields) do result[name .. "." .. field] = value end
            end
            return result
        end,
        setOverrides = function(target, values)
            local properties, components = {}, {}
            for key, value in pairs(values) do
                local name, field = key:match("^([^.]+)%.(.+)$")
                if name then components[name] = components[name] or {}; components[name][field] = value
                else properties[key] = value end
            end
            target.data.propertyOverrides, target.data.componentOverrides = properties, components
        end}
end
return Definition
