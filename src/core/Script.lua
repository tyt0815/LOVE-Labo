local Schema = require("core.PropertySchema")
local Script = {properties = {
    enabled = {type = "boolean", default = true, group = "Script"},
    updateOrder = {type = "number", default = 0, group = "Script"},
    drawOrder = {type = "number", default = 0, group = "Script"}
}, scriptType = "Script"}
local RESERVED = {owner = true, properties = true, id = true, name = true, label = true, source = true, hasLoaded = true, hasUnloaded = true,
    load = true, unload = true, update = true, draw = true, drawScreen = true, drawEditor = true, onPointerDown = true, onPointerUp = true, onPointerMove = true,
    pointer = true, camera = true, canvas = true, super = true, scriptType = true}
for _, name in ipairs(require("core.ScriptEvents").names) do RESERVED[name] = true end
Script.__index = function(instance, name)
    if Script.properties[name] then return instance.properties[name] end
    return Script[name]
end
Script.__newindex = function(instance, name, value)
    if Script.properties[name] then
        assert(Schema.validValue(Script.properties[name].type, value), "Invalid script property")
        instance.properties[name] = value
    else rawset(instance, name, value) end
end
function Script:extend(definition)
    definition = definition or {}
    local schema = {}
    for name, field in pairs(self.properties) do schema[name] = field end
    for name, field in pairs(definition.properties or {}) do
        assert(type(name) == "string" and name:match("^[%a_][%w_]*$") and not RESERVED[name] and type(self[name]) ~= "function" and type(definition[name]) ~= "function" and name:sub(1, 2) ~= "__" and type(field) == "table"
            and Schema.validValue(field.type, field.default), "Invalid script property")
        assert(not schema[name] or schema[name].type == field.type, "Inherited property type cannot change")
        assert(field.group == nil or type(field.group) == "string" and field.group ~= "", "Invalid property group")
        schema[name] = {type = field.type, default = field.default, group = Script.properties[name] and "Script" or field.group}
    end
    for _, callback in ipairs({"load", "unload", "update", "draw", "drawScreen", "drawEditor", "getLocalBounds", "hitTest", "onPointerDown", "onPointerUp", "onPointerMove"}) do
        assert(definition[callback] == nil or type(definition[callback]) == "function", callback .. " must be a function")
    end
    for _, name in ipairs(require("core.ScriptEvents").names) do
        assert(definition[name] == nil or type(definition[name]) == "function", name .. " must be a function")
    end
    definition.properties, definition.super = schema, self
    definition.pointer = definition.pointer or self.pointer or definition.onPointerDown ~= nil or definition.onPointerUp ~= nil or definition.onPointerMove ~= nil
    definition.__index = function(instance, name)
        if schema[name] then return instance.properties[name] end
        return definition[name]
    end
    definition.__newindex = function(instance, name, value)
        if schema[name] then
            assert(Schema.validValue(schema[name].type, value) or (schema[name].type == "object" or schema[name].type == "script") and type(value) == "table", "Invalid script property: " .. name)
            instance.properties[name] = value
        else rawset(instance, name, value) end
    end
    return setmetatable(definition, {__index = self})
end
function Script:new(overrides)
    return setmetatable({properties = assert(Schema.values(self.properties, overrides))}, self)
end
function Script:isA(class)
    local current = getmetatable(self)
    while current do if current == class then return true end; current = current.super end
    return false
end
function Script:getWorldTransform() return self.owner:getWorldTransform() end
function Script:getWorld() return self.owner and self.owner:getWorld() end
function Script:getProject() return self.owner and self.owner:getProject() end
function Script:getWorldPosition()
    local transform = self:getWorldTransform()
    return transform.x, transform.y
end
function Script:getBounds(context)
    if self.getLocalBounds then return require("core.Bounds").getBounds(self, context) end
end
function Script:hitTest(context, x, y) return require("core.Bounds").hitTest(self, context, x, y) end
function Script:getBoundsSource() return self end
return Script
