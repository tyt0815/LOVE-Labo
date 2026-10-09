local PropertyData = {}
function PropertyData.copy(values)
    local result = {}
    for key, value in pairs(values or {}) do result[key] = value end
    return result
end
function PropertyData.copyComponents(values)
    local result = {}
    for name, properties in pairs(values or {}) do result[name] = PropertyData.copy(properties) end
    return result
end
function PropertyData.validateComponents(values)
    if values == nil then return {} end
    if type(values) ~= "table" then return nil, "Component overrides must be an object" end
    local result = {}
    for name, properties in pairs(values) do
        if type(name) ~= "string" or not name:match("^[%a_][%w_]*$") then return nil, "Invalid component name" end
        local validated, err = PropertyData.validate(properties)
        if not validated then return nil, err end
        result[name] = validated
    end
    return result
end
function PropertyData.validate(values)
    if values == nil then return {} end
    if type(values) ~= "table" then return nil, "Property overrides must be an object" end
    local result = {}
    for name, value in pairs(values) do
        if type(name) ~= "string" or name == "" or (type(value) ~= "number" and type(value) ~= "string" and type(value) ~= "boolean")
            or type(value) == "number" and (value ~= value or value == math.huge or value == -math.huge) then
            return nil, "Invalid basic property: " .. tostring(name)
        end
        result[name] = value
    end
    return result
end
return PropertyData
