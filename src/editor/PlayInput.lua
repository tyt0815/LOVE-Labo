local Input = {}
Input.__index = Input

-- 게임 Lua에는 요청 상태를 보이고, OS에는 에디터 포커스에 맞는 상태를 적용한다.
function Input.new()
    local self = setmetatable({active = false, visible = true, relative = false, grabbed = false, held = {}}, Input)
    self.original = {visible = love.mouse.isVisible(), relative = love.mouse.getRelativeMode(), grabbed = love.mouse.isGrabbed(), cursor = love.mouse.getCursor()}
    local mouse = setmetatable({}, {__index = love.mouse})
    local keyboard = setmetatable({}, {__index = love.keyboard})
    for field, names in pairs({visible = {"setVisible", "isVisible"}, relative = {"setRelativeMode", "getRelativeMode"}, grabbed = {"setGrabbed", "isGrabbed"}}) do
        mouse[names[1]] = function(value) self[field] = not not value; self:apply() end
        mouse[names[2]] = function() return self[field] end
    end
    keyboard.isDown = function(...) return self.active and love.keyboard.isDown(...) or false end
    keyboard.isScancodeDown = function(...) return self.active and love.keyboard.isScancodeDown(...) or false end
    mouse.isDown = function(...) return self.active and love.mouse.isDown(...) or false end
    mouse.getPosition = function() if self.active then return love.mouse.getPosition() end; return 0, 0 end
    mouse.getX = function() local x = mouse.getPosition(); return x end
    mouse.getY = function() local _, y = mouse.getPosition(); return y end
    mouse.setPosition = function(...) if self.active then love.mouse.setPosition(...) end end
    mouse.setX = function(x) if self.active then love.mouse.setX(x) end end
    mouse.setY = function(y) if self.active then love.mouse.setY(y) end end
    mouse.setCursor = function(cursor) self.cursor = cursor; if self.active then love.mouse.setCursor(cursor) end end
    mouse.getCursor = function() return self.cursor end
    local joysticks = setmetatable({}, {__mode = "k"})
    function self:joystick(value)
        if joysticks[value] then return joysticks[value] end
        local proxy = setmetatable({}, {__index = function(_, name)
            return function(_, ...)
                if not self.active then
                    if name == "isDown" or name == "isGamepadDown" or name == "setVibration" then return false end
                    if name == "getAxis" or name == "getGamepadAxis" then return 0 end
                    if name == "getHat" then return "c" end
                    if name == "getAxes" then
                        local values = {}; for index = 1, value:getAxisCount() do values[index] = 0 end
                        return unpack(values)
                    end
                end
                return value[name](value, ...)
            end
        end})
        joysticks[value] = proxy
        return proxy
    end
    local joystick = setmetatable({}, {__index = love.joystick})
    joystick.getJoysticks = function()
        local values = {}; for index, value in ipairs(love.joystick.getJoysticks()) do values[index] = self:joystick(value) end
        return values
    end
    self.love = setmetatable({mouse = mouse, keyboard = keyboard, joystick = joystick}, {__index = love})
    -- require("love.mouse")도 같은 입력 경계를 사용한다.
    self.modules = {["love"] = self.love, ["love.mouse"] = mouse, ["love.keyboard"] = keyboard, ["love.joystick"] = joystick}
    return self
end
function Input:track(name, arguments)
    if name == "touchmoved" then
        local held = self.held["touchreleased:" .. tostring(arguments[1])]
        if held then held.args = arguments end
        return
    end
    local pairs = {keypressed = "keyreleased", mousepressed = "mousereleased", gamepadpressed = "gamepadreleased", joystickpressed = "joystickreleased", touchpressed = "touchreleased"}
    local releases = {keyreleased = true, mousereleased = true, gamepadreleased = true, joystickreleased = true, touchreleased = true}
    local release = pairs[name] or releases[name] and name
    if not release then return end
    local key = release .. ":" .. tostring(arguments[1])
    if name:match("^mouse") then key = release .. ":" .. tostring(arguments[3])
    elseif name:match("^gamepad") or name:match("^joystick") then key = key .. ":" .. tostring(arguments[2]) end
    if pairs[name] then
        local args = arguments
        if name == "keypressed" then args = {arguments[1], arguments[2]} end
        self.held[key] = {name = release, args = args}
    else self.held[key] = nil end
end
function Input:releaseHeld()
    local events = self.held; self.held = {}
    for _, event in pairs(events) do
        if event.name == "mousereleased" then
            event.args[1], event.args[2] = love.mouse.getPosition()
        elseif event.name == "touchreleased" then
            local ok, x, y = pcall(love.touch.getPosition, event.args[1])
            if ok then event.args[2], event.args[3] = x, y end
        end
    end
    return events
end
function Input:apply()
    -- 에디터가 숫자 드래그 등에 사용하는 상대 모드를 게임 요청으로 덮어쓰지 않는다.
    if not self.active and not self.lastActive then return end
    love.mouse.setRelativeMode(self.active and self.relative or false)
    love.mouse.setGrabbed(self.active and self.grabbed or false)
    love.mouse.setVisible(not self.active or self.visible)
    if self.active then love.mouse.setCursor(self.cursor)
    elseif self.lastActive then love.mouse.setCursor(self.original.cursor) end
    self.lastActive = self.active
end
function Input:setActive(active) self.active = not not active; self:apply() end
function Input:dispose()
    self.active = false
    love.mouse.setRelativeMode(self.original.relative)
    love.mouse.setGrabbed(self.original.grabbed)
    love.mouse.setVisible(self.original.visible)
    love.mouse.setCursor(self.original.cursor)
end
return Input
