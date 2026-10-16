local Ui = require("editor.Ui")
local Theme = require("editor.Theme")
local Frame = require("editor.WindowFrame")
local Controls = {}
Controls.__index = Controls

function Controls.new()
    return setmetatable({}, Controls)
end

function Controls:buttons(width)
    return {{name = "minimize", label = "Minimize", x = width - 138, y = 0, w = 46, h = 32},
        {name = "maximize", label = love.window.isMaximized() and "Restore" or "Maximize", x = width - 92, y = 0, w = 46, h = 32},
        {name = "close", label = "Close", x = width - 46, y = 0, w = 46, h = 32}}
end

function Controls:press(x, y, button)
    if not Frame.active or button ~= 1 then return false end
    for _, item in ipairs(self:buttons(love.graphics.getWidth())) do if Ui.contains(x, y, item) then
        if item.name == "minimize" then love.window.minimize()
        elseif item.name == "maximize" then Frame.toggleMaximize()
        else love.event.quit() end
        return true
    end end
    return false
end

function Controls:draw()
    if not Frame.active then return end
    love.graphics.push("all"); love.graphics.setLineWidth(1)
    love.graphics.setScissor()
    for _, item in ipairs(self:buttons(love.graphics.getWidth())) do
        Ui.button("", item, false, item.label, true)
        if item.name == "close" and Ui.hovered(item) then
            Theme.setColor("error"); love.graphics.rectangle("fill", item.x, item.y, item.w, item.h)
        end
        Theme.setColor("text")
        local x, y = item.x + 18, item.y + 11
        if item.name == "minimize" then love.graphics.line(x, y + 5, x + 10, y + 5)
        elseif item.name == "maximize" then
            if love.window.isMaximized() then
                love.graphics.rectangle("line", x + 2.5, y - 1.5, 8, 8)
                Theme.setColor("background"); love.graphics.rectangle("fill", x, y + 1, 8, 8)
                Theme.setColor("text"); love.graphics.rectangle("line", x + 0.5, y + 1.5, 8, 8)
            else love.graphics.rectangle("line", x + 0.5, y + 0.5, 10, 10) end
        else love.graphics.line(x, y, x + 10, y + 10); love.graphics.line(x + 10, y, x, y + 10) end
    end
    love.graphics.pop()
end

return Controls
