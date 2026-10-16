local Engine = require("Engine")
local Bounds = Engine.Bounds
local Pointer = Engine.Script:extend({scriptType = "Pointer", properties = {
    boundsX = {type = "number", default = -50}, boundsY = {type = "number", default = -50},
    boundsWidth = {type = "number", default = 100}, boundsHeight = {type = "number", default = 100},
    fillParent = {type = "boolean", default = false}, inputPriority = {type = "number", default = 0},
    blockPointer = {type = "boolean", default = false}, boundsSource = {type = "string", default = ""}
}})
function Pointer:getLocalBounds(context)
    local x, y, w, h = Bounds.of(self.owner, context)
    if x then return x, y, w, h end
    if self.fillParent then
        x, y, w, h = Bounds.parent(self.owner, context)
        if x then return x, y, w, h end
    end
    return self.boundsX, self.boundsY, self.boundsWidth, self.boundsHeight
end
function Pointer:getBoundsSource()
    local source, visited = self, {}
    while source.boundsSource and source.boundsSource ~= "" do
        assert(not visited[source], "Cyclic pointer boundsSource"); visited[source] = true
        source = source.owner:getScriptById(source.boundsSource) or source.owner:getScriptByName(source.boundsSource)
        if not source then return nil end
        assert(source.getBounds, "boundsSource must provide bounds")
    end
    return source
end
function Pointer:hitTest(context, x, y)
    local source = self:getBoundsSource()
    if not source then return false end
    if source ~= self then return source:hitTest(context, x, y) end
    return Bounds.hitTest(self, context, x, y)
end
function Pointer:load(world)
    for _, name in ipairs({"onPointerDown", "onPointerUp", "onPointerMove"}) do
        assert(self[name] == nil or type(self[name]) == "function", "Pointer callback must be a function: " .. name)
    end
    self.region = Engine.Input.registerRegion(world, {owner = self,
        hitTest = function(context, x, y) return self:hitTest(context, x, y) end,
        filterSource = function() return self:getBoundsSource() end,
        order = function() local source = self:getBoundsSource(); return source and source.drawOrder or 0 end,
        priority = function() return self.inputPriority end, block = function() return self.blockPointer end,
        onDown = function(event) if self.onPointerDown then return self:onPointerDown(event) end end,
        onUp = function(event) if self.onPointerUp then return self:onPointerUp(event) end end,
        onMove = function(event) if self.onPointerMove then return self:onPointerMove(event) end end})
end
function Pointer:drawEditor(context) local source = self:getBoundsSource(); if source then context:bounds(source) end end
return Pointer
