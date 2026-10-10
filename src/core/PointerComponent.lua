local Bounds = require("core.BoundsComponent")
local Pointer = Bounds:extend({componentType = "PointerComponent", properties = {
    boundsX = {type = "number", default = -50, group = "Bounds"},
    boundsY = {type = "number", default = -50, group = "Bounds"},
    boundsWidth = {type = "number", default = 100, group = "Bounds"},
    boundsHeight = {type = "number", default = 100, group = "Bounds"},
    enabled = {type = "boolean", default = true, group = "Pointer"},
    inputPriority = {type = "number", default = 0, group = "Pointer"},
    blockPointer = {type = "boolean", default = false, group = "Pointer"},
    boundsSource = {type = "string", default = "", group = "Pointer"}
}})
function Pointer:getLocalBounds(context)
    local p = self.properties
    return p.boundsX, p.boundsY, p.boundsWidth, p.boundsHeight
end
function Pointer:getBoundsSource()
    local source, target, visited = self, nil, {}
    while source:isA(Pointer) and source.properties.boundsSource ~= "" do
        assert(not visited[source], "Cyclic pointer boundsSource")
        visited[source] = true
        source = assert(source.owner and source.owner.components[source.properties.boundsSource], "Missing pointer boundsSource")
        assert(source:isA(Bounds), "boundsSource must be a BoundsComponent")
        target = source
    end
    return target or self
end
function Pointer:hitTest(context, worldX, worldY)
    local source, target, visited = self, nil, {}
    while source:isA(Pointer) and source.properties.boundsSource ~= "" do
        assert(not visited[source], "Cyclic pointer boundsSource")
        visited[source] = true
        source = assert(source.owner and source.owner.components[source.properties.boundsSource], "Missing pointer boundsSource")
        assert(source:isA(Bounds), "boundsSource must be a BoundsComponent")
        target = target or source
    end
    if target then return target:hitTest(context, worldX, worldY) end
    return Bounds.hitTest(self, context, worldX, worldY)
end
function Pointer:onPointerDown(event) return false end
function Pointer:onPointerUp(event) return false end
function Pointer:onPointerMove(event) return false end
return Pointer
