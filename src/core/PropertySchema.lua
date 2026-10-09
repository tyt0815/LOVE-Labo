local Schema = {}
function Schema.isTemplate(kind) return kind == "lobjectTemplate" or kind == "prefab" end
function Schema.validValue(kind, value)
    if kind == "object" then return value == false or type(value) == "number" and value >= 1 and value % 1 == 0 and value < math.huge end
    if kind == "image" or Schema.isTemplate(kind) then return value == false or type(value) == "string" and value ~= "" end
    if kind ~= "number" and kind ~= "string" and kind ~= "boolean" then return false end
    return type(value) == kind and (kind ~= "number" or value == value and value ~= math.huge and value ~= -math.huge)
end
function Schema.values(schema, overrides)
    local result = {}
    for name, declaration in pairs(schema or {}) do result[name] = declaration.default end
    for name, value in pairs(overrides or {}) do
        if not schema[name] or not Schema.validValue(schema[name].type, value) then return nil, "Invalid property override: " .. tostring(name) end
        result[name] = value
    end
    return result
end
return Schema
