local Controls = {properties = {drawOrder = {type = "number", default = 1000}}}
function Controls:update(dt)
    local t, speed = self.owner.transform, 240 * dt
    if love.keyboard.isDown("a", "left") then t.x = t.x - speed end
    if love.keyboard.isDown("d", "right") then t.x = t.x + speed end
    if love.keyboard.isDown("w", "up") then t.y = t.y - speed end
    if love.keyboard.isDown("s", "down") then t.y = t.y + speed end
end
function Controls:keypressed(key)
    local camera = self.owner:getScriptByName("camera")
    if key == "=" then camera.zoom = math.min(8, camera.zoom * 2)
    elseif key == "-" then camera.zoom = math.max(0.25, camera.zoom / 2) end
end
function Controls:draw(context)
    context:withScreen(function()
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.printf("WASD: camera | = / -: zoom | click the anchored buttons", 0, context.viewport.height / 2 + 44, context.viewport.width, "center")
    end)
end
return Controls
