-- labo-script: script
local InputEvents = {properties = {
    lastEvent = {type = "string", default = "Ready"},
    eventCount = {type = "number", default = 0},
    pointerX = {type = "number", default = 0},
    pointerY = {type = "number", default = 0},
    inputText = {type = "string", default = ""}
}}
function InputEvents:record(name)
    self.lastEvent = name
    self.eventCount = self.eventCount + 1
end
function InputEvents:keypressed(key, scancode, isrepeat)
    self:record("keypressed: " .. key)
    if key == "right" then self.owner.transform.x = self.owner.transform.x + 20 end
    if key == "left" then self.owner.transform.x = self.owner.transform.x - 20 end
end
function InputEvents:keyreleased(key) self:record("keyreleased: " .. key) end
function InputEvents:textinput(text) self.inputText = self.inputText .. text; self:record("textinput") end
function InputEvents:textedited(text) self.preedit = text; self:record("textedited") end
function InputEvents:mousepressed(x, y, button)
    self.pointerX, self.pointerY = x, y; self:record("mousepressed: " .. button)
end
function InputEvents:mousereleased(x, y, button)
    self.pointerX, self.pointerY = x, y; self:record("mousereleased: " .. button)
end
function InputEvents:wheelmoved(x, y) self:record("wheelmoved: " .. x .. ", " .. y) end
function InputEvents:touchpressed(id, x, y) self.pointerX, self.pointerY = x, y; self:record("touchpressed") end
function InputEvents:touchreleased(id, x, y) self.pointerX, self.pointerY = x, y; self:record("touchreleased") end
function InputEvents:gamepadpressed(joystick, button) self:record("gamepadpressed: " .. button) end
function InputEvents:focus(focused) self:record("focus: " .. tostring(focused)) end
function InputEvents:resize(width, height) self.viewWidth, self.viewHeight = width, height end
function InputEvents:draw()
    love.graphics.setColor(0.2, 0.8, 1, 1)
    love.graphics.rectangle("fill", -20, -20, 40, 40)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.print("Input Events / Left-Right: move / Type: text / Click + wheel: events", -400, -180)
    love.graphics.print(self.lastEvent .. " / count: " .. self.eventCount, -400, -140)
    love.graphics.print("Pointer: " .. self.pointerX .. ", " .. self.pointerY, -400, -100)
    love.graphics.print("Text: " .. self.inputText .. (self.preedit or ""), -400, -60)
end
return InputEvents
