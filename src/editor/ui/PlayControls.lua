local Widget = require("editor.ui.Widget")
local Ui = require("editor.Ui")
local Theme = require("editor.Theme")
local Controls = setmetatable({}, {__index = Widget})
Controls.__index = Controls
function Controls.new(app)
    local self = setmetatable(Widget.new(), Controls)
    self.app, self.focusable = app, false
    self.handlers.draw = function() self:render() end
    self.handlers.hitTest = function(_, x, y)
        for _, button in ipairs(self:buttons()) do if Ui.contains(x, y, button) then return true end end
        return false
    end
    self.handlers.mousepressed = function(_, x, y, button)
        if button == 1 then for _, item in ipairs(self:buttons()) do if Ui.contains(x, y, item) and item.enabled then
            if item.name == "play" then app:startPlay() elseif item.name == "pause" then app:pausePlay() else app:stopPlay() end
        end end end
        return true
    end
    return self
end
function Controls:buttons()
    local app = self.app
    local x, y = self.x + (self.width - 92) / 2, self.y + (self.height - 26) / 2
    return {{name = "play", label = app.paused and "Resume" or "Play", enabled = not app:isPlaying() or app.paused, x = x, y = y, w = 28, h = 26},
        {name = "pause", label = "Pause", enabled = app:isPlaying() and not app.paused, x = x + 32, y = y, w = 28, h = 26},
        {name = "stop", label = "Stop", enabled = app:isPlaying(), x = x + 64, y = y, w = 28, h = 26}}
end
function Controls:render()
    for _, item in ipairs(self:buttons()) do
        if item.enabled then Ui.button("", item, false, item.label, true) else Ui.hint(item, item.label .. " (unavailable)") end
        Theme.setColor(item.enabled and "text" or "textDisabled")
        local x, y = item.x + 9, item.y + 7
        if item.name == "play" then love.graphics.polygon("fill", x, y, x + 11, y + 6, x, y + 12)
        elseif item.name == "pause" then love.graphics.rectangle("fill", x, y, 4, 12); love.graphics.rectangle("fill", x + 7, y, 4, 12)
        else love.graphics.rectangle("fill", x, y, 11, 12) end
    end
end
return Controls
