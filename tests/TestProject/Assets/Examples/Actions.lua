local Engine = require("Engine")
local Actions = {extends = "6a3d80b6-38e4-4e0c-92d1-2338a55c2e30", properties = {
    action = {type = "string", default = "Debug", group = "Actions"},
    caption = {type = "string", default = "Click"}, template = {type = "prefab", default = false},
    image = {type = "image", default = false},
    nextLevel = {type = "string", default = ""}, target = {type = "object", default = false},
    boundsX = {type = "number", default = -90}, boundsY = {type = "number", default = -24},
    boundsWidth = {type = "number", default = 180}, boundsHeight = {type = "number", default = 48},
    blockPointer = {type = "boolean", default = true}, inputPriority = {type = "number", default = 10},
    drawOrder = {type = "number", default = 100}
}}
function Actions.draw(self)
    love.graphics.setColor(0.15, 0.35, 0.55, 1)
    love.graphics.rectangle("fill", -90, -24, 180, 48, 5, 5)
    love.graphics.setColor(1, 1, 1, 1); love.graphics.printf(self.caption, -86, -8, 172, "center")
end
function Actions.onPointerDown(self, event)
    local world, spawned = event.world, event.world.exampleSpawn
    world.debug:log(self.action .. " pointer down", {marker = ">"})
    if self.action == "Spawn" then world.exampleSpawn = assert(Engine.spawnLObject(world, self.template, {x = 150, y = 220}))
    elseif self.action == "Raw" then
        world.exampleSpawn = assert(world:addLObject({name = "Empty object", transform = {x = 150, y = 220}}))
    elseif self.action == "Bounds" then
        local x, y = self:getWorldPosition(); local hit = Engine.Bounds.hitTest(self, {}, x, y)
        local width, height = select(3, self:getBounds({}))
        local viewport = Engine.Viewport.new(world, 0, 0, 1280, 720)
        local sx, sy = viewport:worldToScreen(0, 0); local wx, wy = viewport:screenToWorld(sx, sy)
        local space = "world"
        world.debug:log(space .. " bounds " .. width .. "x" .. height .. "; hit=" .. tostring(hit) .. "; origin=" .. wx .. "," .. wy)
    elseif self.action == "Remove" and spawned and spawned.world then world:removeLObject(spawned); world.exampleSpawn = nil
    elseif self.action == "Attach" and spawned and spawned.world then spawned:attachTo(spawned.parent and nil or self.target)
    elseif self.action == "Scripts" and spawned and spawned.world then
        local motion = spawned:getScriptByName("motion")
        if motion then motion.enabled = not motion.enabled end
    elseif self.action == "Camera" then
        local camera = world:getObjects()[1]:getScriptByName("camera") or world:getObjects()[1]:getScriptByName("Camera"); camera.zoom = camera.zoom == 1 and 1.5 or 1
    elseif self.action == "Next" then assert(Engine.openLevel(world, self.nextLevel))
    elseif self.action == "Properties" and self.target then
        local motion = self.target:getScriptByName("motion")
        local class = require("Examples.Motion")
        assert(self.target:getScriptById(motion.id) == motion and self.target:getScriptByClass(class) == motion)
        world.debug:log("Matching scripts: " .. #self.target:getScriptsByClass(class))
        motion.enabled = not motion.enabled
        local t = self.target:getWorldTransform(); local x, y = Engine.Transform.point(t, 10, 10)
        world.debug:log("Property toggled; transformed point " .. x .. ", " .. y)
    else
        world.debug:point(0, 0, 5); world.debug:line(0, 0, 150, 100)
        world.debug:circle(0, 0, 90); world.debug:rect(-100, -60, 200, 120)
        world.debug:polygon({-80, -80, 80, -80, 0, 90})
        world.debug:screenLog("Debug shapes for 3 seconds", {key = "demo"})
    end
    return true
end
function Actions.onPointerUp(self, event) event.world.debug:log(self.action .. " pointer up"); return true end
function Actions.onPointerMove(self, event) self.hovered = event.inside; return true end
function Actions.drawEditor(self, context) context:bounds(self) end
return Actions
