local Bounds = require("core.Bounds")
local Pointer = require("core.Script"):extend({scriptType = "Pointer", pointer = true, properties = {
    boundsX = {type = "number", default = -50}, boundsY = {type = "number", default = -50},
    boundsWidth = {type = "number", default = 100}, boundsHeight = {type = "number", default = 100},
    fillParent = {type = "boolean", default = false},
    enabled = {type = "boolean", default = true}, inputPriority = {type = "number", default = 0},
    blockPointer = {type = "boolean", default = false}, boundsSource = {type = "string", default = ""}
}})
Pointer.getBounds = Bounds.getBounds
function Pointer:getLocalBounds() return self.boundsX, self.boundsY, self.boundsWidth, self.boundsHeight end
function Pointer:getBoundsSource()
    local source, visited = self, {}
    while source.pointer and source.boundsSource ~= "" do
        assert(not visited[source], "Cyclic pointer boundsSource"); visited[source] = true
        source = assert(source.owner.scripts[source.boundsSource], "Missing pointer boundsSource")
        assert(source.getLocalBounds, "boundsSource must provide bounds")
    end
    return source
end
function Pointer:hitTest(context, x, y)
    self:getBoundsSource()
    local target = self.boundsSource ~= "" and self.owner.scripts[self.boundsSource]
    if target then return target:hitTest(context, x, y) end
    return Bounds.hitTest(self, context, x, y)
end
function Pointer:drawEditor(context) context:bounds(self:getBoundsSource()) end
return Pointer
