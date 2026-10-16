local Transform = require("core.Transform")
local LObject = {}
LObject.__index = LObject
function LObject.new(runtimeId, initial)
    if type(runtimeId) ~= "number" or runtimeId < 1 or runtimeId % 1 ~= 0 then return nil, "Invalid runtime ID" end
    if type(initial) ~= "table" then return nil, "Invalid LObject state" end
    local transform, err = Transform.copy(initial.transform)
    if not transform then return nil, err end
    return setmetatable({runtimeId = runtimeId, authoringId = initial.authoringId, name = initial.name,
        definitionReference = initial.definitionReference, transform = transform, children = {},
        scripts = {}, scriptOrder = {}, updateScripts = {}, drawScripts = {}, properties = {}}, LObject)
end
local ScriptHost = require("core.ScriptHost")
LObject.getScriptOrder = ScriptHost.getScriptOrder
LObject.getScriptById = ScriptHost.getScriptById
LObject.getScriptByName = ScriptHost.getScriptByName
LObject.getScriptByClass = ScriptHost.getScriptByClass
LObject.getScriptsByClass = ScriptHost.getScriptsByClass
LObject.load = ScriptHost.load
LObject.unload = ScriptHost.unload
LObject.update = ScriptHost.update
LObject.getWorld = ScriptHost.getWorld
LObject.getProject = ScriptHost.getProject
function LObject:getWorldTransform(context)
    local value = Transform.localValue(self, context)
    return self.parent and Transform.compose(self.parent:getWorldTransform(context), value) or value
end
function LObject:attachTo(parent)
    assert(parent == nil or getmetatable(parent) == LObject, "Parent must be an LObject")
    assert(not parent or not self.world or not parent.world or self.world == parent.world, "Objects must belong to the same World")
    local ancestor = parent
    while ancestor do assert(ancestor ~= self, "Object attachment cycle"); ancestor = ancestor.parent end
    if self.parent then
        for index, child in ipairs(self.parent.children) do if child == self then table.remove(self.parent.children, index); break end end
    end
    self.parent = parent
    if parent then parent.children[#parent.children + 1] = self end
    return self
end
return LObject
