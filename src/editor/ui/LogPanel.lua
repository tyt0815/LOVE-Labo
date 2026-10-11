local Widget = require("editor.ui.Widget")
local Ui = require("editor.Ui")
local Panel = setmetatable({}, {__index = Widget})
Panel.__index = Panel
Panel.HEIGHT = 36
function Panel.new(app)
    local self = setmetatable(Widget.new(), Panel)
    self.app, self.scroll, self.expanded, self.focusable = app, 0, false, false
    self.scrollbar = require("editor.ui.Scrollbar").new(function() return self.scroll end, function(value) self.scroll = value end)
    self.handlers = {
        draw = function() self:render() end,
        mousepressed = function(_, x, y, button)
            if button == 1 and y >= self:summaryY() then self:toggle(); return true end
            return self.scrollbar:dispatch("mousepressed", x, y, button)
        end,
        mousemoved = function(_, ...) return self.scrollbar:dispatch("mousemoved", ...) end,
        mousereleased = function(_, ...) return self.scrollbar:dispatch("mousereleased", ...) end,
        cancel = function() return self.scrollbar:dispatch("cancel") end,
        wheelmoved = function(_, _, _, amount)
            if not self.expanded then return true end
            self.scroll = math.max(0, math.min(self.scrollbar.maximum or 0, self.scroll - amount * 40)); return true
        end
    }
    return self
end
function Panel:summaryY() return self.y + self.height - Panel.HEIGHT end
function Panel:toggle()
    self.expanded = not self.expanded
    self.app:updateSceneViewport()
    return true
end
function Panel:render()
    local session = self.app.debugSession
    local rows, height = #session.history, math.max(0, self.height - Panel.HEIGHT - 16)
    local maximum = math.max(0, rows * 22 - height)
    if self.revision ~= session.revision then self.scroll = maximum; self.revision = session.revision end
    self.scroll = math.max(0, math.min(maximum, self.scroll))
    self.scrollbar:layout({x = self.x + self.width - 18, y = self.y + 8, w = 12, h = height}, rows * 22, height)
    love.graphics.push("all"); love.graphics.setScissor(self.x, self.y, self.width, self.height)
    Ui.panel(self.x, self.y, self.width, self.height, "input")
    local summaryY = self:summaryY()
    love.graphics.push(); love.graphics.translate(self.x + 17, summaryY + Panel.HEIGHT / 2)
    if not self.expanded then love.graphics.rotate(math.pi) end
    Ui.chevron(-4, 0, true); love.graphics.pop()
    local latest = session.latest
    if latest then
        Ui.text(latest.text, self.x + 32, summaryY + 10, self.width - 46,
            {latest.color[1] / 255, latest.color[2] / 255, latest.color[3] / 255, 1})
    end
    if self.expanded then
        love.graphics.intersectScissor(self.x + 12, self.y + 8, self.width - 34, height)
        for index, entry in ipairs(session.history) do
            local y = self.y + 8 + (index - 1) * 22 - self.scroll
            if y + 22 >= self.y + 8 and y < summaryY - 8 then
                Ui.text(entry.text, self.x + 14, y, self.width - 40,
                    {entry.color[1] / 255, entry.color[2] / 255, entry.color[3] / 255, 1})
            end
        end
        love.graphics.setScissor(self.x, self.y, self.width, self.height); self.scrollbar:draw()
    end
    love.graphics.pop()
end
return Panel
