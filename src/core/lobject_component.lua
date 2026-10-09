local Schema = require("core.property_schema")
local Component = {properties = {}, componentType = "LObjectComponent"}
Component.__index = Component

function Component:extend(definition)
    definition = definition or {}
    for _, callback in ipairs({"BeginPlay", "Load", "Update", "Draw", "GetLocalBounds"}) do
        assert(definition[callback] == nil or type(definition[callback]) == "function", callback .. " must be a function")
    end
    local schema = {}
    for name, field in pairs(self.properties) do schema[name] = {type = field.type, default = field.default, group = field.group} end
    for name, field in pairs(definition.properties or {}) do
        assert(type(name) == "string" and name ~= "" and type(field) == "table" and Schema.validValue(field.type, field.default), "Invalid component property")
        assert(not schema[name] or schema[name].type == field.type, "Inherited component property type cannot change")
        assert(field.group == nil or type(field.group) == "string" and field.group ~= "", "Property group must be a non-empty string")
        schema[name] = {type = field.type, default = field.default, group = field.group or schema[name] and schema[name].group}
    end
    definition.properties, definition.super, definition.__index = schema, self, definition
    return setmetatable(definition, {__index = self})
end

function Component:new(overrides)
    local values, err = Schema.values(self.properties, overrides)
    assert(values, err)
    return setmetatable({properties = values, children = {}}, self)
end
function Component:attachTo(parent) return self.owner:attachComponent(self, parent) end
function Component:addComponent(name, class, overrides) return self.owner:addComponent(name, class, overrides, self) end
function Component:BeginPlay(world) end
Component.Load = Component.BeginPlay
function Component.beginPlayCallback(component)
    -- 자식이 기존 Load만 재정의했다면 부모의 BeginPlay보다 그 선언을 우선한다.
    local current = component
    while current do
        local callback = rawget(current, "BeginPlay") or rawget(current, "Load")
        if callback then return callback end
        current = current == component and getmetatable(component) or rawget(current, "super")
    end
end
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
