local Transform = require("core.Transform")
local Drag = {}
function Drag.begin(owner, text, x, options)
    local value = tonumber(text)
    if not Transform.finite(value) then return end
    owner.numberDrag = {startX = x, lastX = x, initial = value, value = value, options = options or {}}
end
local function captureMouse(drag)
    local _, y = love.mouse.getPosition()
    drag.mouse = {relative = love.mouse.getRelativeMode(), visible = love.mouse.isVisible(), grabbed = love.mouse.isGrabbed(), y = drag.options.pointerY or y}
    love.mouse.setRelativeMode(true)
    love.mouse.setVisible(false)
end
local function restoreMouse(drag)
    if not drag or not drag.mouse then return end
    love.mouse.setRelativeMode(drag.mouse.relative)
    if not drag.mouse.relative then
        love.mouse.setGrabbed(drag.mouse.grabbed)
        love.mouse.setPosition(drag.startX, drag.mouse.y)
    end
    love.mouse.setVisible(drag.mouse.visible)
end
function Drag.move(owner, x, dx)
    local drag = owner.numberDrag
    if not drag then return false end
    -- 작은 클릭 흔들림은 숫자 변경으로 처리하지 않는다.
    if not drag.active and math.abs(x - drag.startX) < 4 then return true end
    local movement = drag.active and dx or x - drag.lastX
    if not drag.active then captureMouse(drag); drag.active = true end
    if movement == nil then movement = x - drag.lastX end
    local precision = love.keyboard.isDown("lshift", "rshift") and 0.1 or 1
    local value = drag.value + movement * (drag.options.step or 1) * precision
    drag.lastX = x
    if not Transform.finite(value) then return true end
    if drag.options.minimum then value = math.max(drag.options.minimum, value) end
    drag.value = value
    local shown = drag.options.normalize and drag.options.normalize(value) or value
    if drag.options.onChange then drag.options.onChange(shown) end
    return true, tostring(shown)
end
function Drag.finish(owner)
    local drag = owner.numberDrag
    owner.numberDrag = nil
    restoreMouse(drag)
    return drag and drag.active or false
end
function Drag.cancel(owner)
    local drag = owner.numberDrag
    if not drag then return false end
    owner.numberDrag = nil
    restoreMouse(drag)
    if drag.active and drag.options.onChange then drag.options.onChange(drag.initial) end
    return true
end
function Drag.modifier(owner, key)
    return owner.numberDrag ~= nil and (key == "lshift" or key == "rshift")
end
return Drag
