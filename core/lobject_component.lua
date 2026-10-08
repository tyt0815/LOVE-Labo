local Schema = require("core.property_schema")
local Component = {properties = {}, componentType = "LObjectComponent"}
Component.__index = Component

function Component:extend(definition)
    definition = definition or {}
    for _, callback in ipairs({"Load", "Update"}) do
        assert(definition[callback] == nil or type(definition[callback]) == "function", callback .. " must be a function")
    end
    local schema = {}
    for name, field in pairs(self.properties) do schema[name] = {type = field.type, default = field.default} end
    for name, field in pairs(definition.properties or {}) do
        assert(type(name) == "string" and name ~= "" and type(field) == "table" and Schema.validValue(field.type, field.default), "Invalid component property")
        assert(not schema[name] or schema[name].type == field.type, "Inherited component property type cannot change")
        schema[name] = {type = field.type, default = field.default}
    end
    definition.properties, definition.super, definition.__index = schema, self, definition
    return setmetatable(definition, {__index = self})
end

function Component:new(overrides)
    local values, err = Schema.values(self.properties, overrides)
    assert(values, err)
    return setmetatable({properties = values}, self)
end
function Component:Load(world) end
function Component:Update(dt) end
function Component:isA(class)
    local current = getmetatable(self)
    while current do
        if current == class then return true end
        current = current.super
    end
    return false
end
return Component
