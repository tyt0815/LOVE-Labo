local Schema = {}
-- 조건은 값의 유효성이 아니라 Inspector의 편집 가능 여부만 제한한다.
function Schema.copyEnabledIf(condition, prefix)
    assert(condition == nil or condition == false or type(condition) == "table", "enabledIf must be a table or false")
    if not condition then return condition end
    local copy = {}
    for name, value in pairs(condition) do
        assert(type(name) == "string", "enabledIf keys must be property names")
        copy[(prefix or "") .. name] = value
    end
    return copy
end
function Schema.validateConditions(schema)
    for name, field in pairs(schema) do
        if field.enabledIf then
            if type(field.enabledIf) ~= "table" or next(field.enabledIf) == nil then return false, "enabledIf requires at least one condition: " .. name end
            for dependency, expected in pairs(field.enabledIf) do
                local source = schema[dependency]
                if dependency == name or not source or not ({boolean = true, number = true, string = true})[source.type]
                    or not Schema.validField(source, expected) then
                    return false, "Invalid enabledIf dependency: " .. name .. " -> " .. tostring(dependency)
                end
            end
        end
    end
    return true
end
function Schema.isEditable(field, getValue)
    for name, expected in pairs(field.enabledIf or {}) do
        if getValue(name) ~= expected then return false end
    end
    return true
end
function Schema.isTemplate(kind) return kind == "lobjectTemplate" or kind == "prefab" end
function Schema.isResource(kind) return kind == "image" or kind == "audio" end
function Schema.validValue(kind, value)
    if kind == "script" then
        return value == false or type(value) == "table" and type(value.authoringId) == "number"
            and value.authoringId >= 1 and value.authoringId % 1 == 0 and require("core.ScriptId").isValid(value.script)
    end
    if kind == "object" then return value == false or type(value) == "number" and value >= 1 and value % 1 == 0 and value < math.huge end
    if Schema.isResource(kind) or Schema.isTemplate(kind) then return value == false or type(value) == "string" and value ~= "" end
    if kind ~= "number" and kind ~= "string" and kind ~= "boolean" then return false end
    return type(value) == kind and (kind ~= "number" or value == value and value ~= math.huge and value ~= -math.huge)
end
-- 이전 제공 렌더러의 저장 키를 공통 그리기 순서로 읽는다. 사용자 선언은 보존한다.
function Schema.overrideName(schema, name)
    if name == "sortingOrder" and not schema[name] and schema.drawOrder then return "drawOrder" end
    return name
end
function Schema.validField(field, value)
    if not Schema.validValue(field.type, value) then return false end
    if field.options then
        for _, option in ipairs(field.options) do if option == value then return true end end
        return false
    end
    return true
end
function Schema.values(schema, overrides)
    local result = {}
    for name, declaration in pairs(schema or {}) do
        local value = declaration.default
        result[name] = type(value) == "table" and {authoringId = value.authoringId, script = value.script} or value
    end
    for name, value in pairs(overrides or {}) do
        local original = name
        name = Schema.overrideName(schema, name)
        if not schema[name] or not Schema.validField(schema[name], value) then return nil, "Invalid property override: " .. tostring(name) end
        if original == name or overrides[name] == nil then
            result[name] = type(value) == "table" and {authoringId = value.authoringId, script = value.script} or value
        end
    end
    return result
end
return Schema
