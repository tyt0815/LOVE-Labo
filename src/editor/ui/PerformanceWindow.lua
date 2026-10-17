local Widget = require("editor.ui.Widget")
local Ui = require("editor.Ui")
local Theme = require("editor.Theme")
local Window = setmetatable({}, {__index = Widget})
Window.__index = Window
function Window.new(app)
    local self = setmetatable(Widget.new(), Window)
    self.app, self.visible, self.focusable = app, false, true
    self:setBounds(320, 100, 620, 440)
    self.handlers.draw = function() self:render() end
    self.handlers.mousepressed = function(_, x, y, button)
        if button ~= 1 then return true end
        if y < self.y + 32 and x > self.x + self.width - 36 then self.visible = false
        elseif y < self.y + 32 then self.drag = {x = x - self.x, y = y - self.y}; return true, true
        elseif x > self.x + self.width - 18 and y > self.y + self.height - 18 then self.resize = {x = x, y = y, w = self.width, h = self.height}; return true, true
        elseif y < self.y + 70 then
            local index = math.floor((x - self.x - 12) / 100)
            if index == 0 then app.performance.recording = not app.performance.recording
            elseif index == 1 then app.performance.detailed = not app.performance.detailed
            elseif index == 2 then app.performance:clear(); self.selected = nil
            elseif index == 3 then app.performanceOverlay = not app.performanceOverlay
            elseif index == 4 then
                local path = app.project and require("editor.HostFileSystem").join(app.project.rootPath, ".labo/performance.json")
                if path then
                    local Fs = require("editor.HostFileSystem")
                    local directory = Fs.join(app.project.rootPath, ".labo")
                    if not Fs.info(directory) then Fs.mkdir(directory) end
                    local ok, err = Fs.writeAtomic(path, assert(require("project.Json").encode(app.performance:report(), true)))
                    self.message = ok and path or err
                end
            end
        elseif y >= self.y + 82 and y < self.y + 166 then
            self.selected = math.max(1, math.min(#app.performance.frames, math.floor((x - self.x - 16) / (self.width - 32) * #app.performance.frames) + 1))
        end
        return true
    end
    self.handlers.mousemoved = function(_, x, y)
        if self.drag then
            self.x = math.max(0, math.min(love.graphics.getWidth() - 80, x - self.drag.x))
            self.y = math.max(32, math.min(love.graphics.getHeight() - 32, y - self.drag.y))
        elseif self.resize then self.width = math.max(540, self.resize.w + x - self.resize.x); self.height = math.max(320, self.resize.h + y - self.resize.y) end
        if self.slot then self.slot.x, self.slot.y, self.slot.width, self.slot.height = self.x, self.y, self.width, self.height end
        return true
    end
    self.handlers.mousereleased = function() self.drag, self.resize = nil, nil; return true end
    self.handlers.cancel = self.handlers.mousereleased
    self.handlers.keypressed = function(_, key) if key == "escape" then self.visible = false end; return true end
    self.handlers.wheelmoved = function(_, _, _, amount) self.scroll = math.max(0, (self.scroll or 0) - amount * 3); return true end
    return self
end
function Window:render()
    local performance = self.app.performance
    local report = performance:report()
    love.graphics.push("all"); love.graphics.setScissor(self.x, self.y, self.width, self.height)
    Ui.panel(self.x, self.y, self.width, self.height)
    Ui.label("Performance — CPU", self.x + 12, self.y + 8, self.width - 48)
    Theme.setColor("text"); love.graphics.setLineWidth(2)
    love.graphics.line(self.x + self.width - 23, self.y + 10, self.x + self.width - 13, self.y + 20)
    love.graphics.line(self.x + self.width - 23, self.y + 20, self.x + self.width - 13, self.y + 10)
    for index, label in ipairs({performance.recording and "Pause" or "Record", performance.detailed and "Detail: on" or "Detail: off", "Clear", "Overlay", "Export"}) do
        Ui.button(label, {x = self.x + 12 + (index - 1) * 100, y = self.y + 38, w = 94, h = 26}, false)
    end
    local frames = performance.frames
    Theme.setColor("focus")
    for index, frame in ipairs(frames) do
        local x = self.x + 16 + (index - 1) / math.max(1, #frames) * (self.width - 32)
        local height = math.min(80, frame.frameMs / math.max(33.33, report.maxMs) * 80)
        love.graphics.line(x, self.y + 164, x, self.y + 164 - height)
    end
    local frame = frames[self.selected or #frames]
    local text = string.format("Frame avg %.2f ms / max %.2f ms", report.averageMs, report.maxMs)
    if frame then
        text = text .. string.format("\nSelected: %.2f ms | Update %.2f | Draw %.2f | Editor %.2f ms\nObjects %d | Scripts %d | Lua %.2f MB (process) | Texture %.2f MB (shared)",
            frame.frameMs, frame.updateMs or 0, frame.drawMs or 0, frame.editorMs or 0, frame.objects or 0, frame.scripts or 0, (frame.luaKb or 0) / 1024, (frame.textureBytes or 0) / 1048576)
    end
    Ui.label(text, self.x + 16, self.y + 176, self.width - 32)
    local top = self.y + 244
    Ui.label("Script timings: accumulated since Clear (detail recording)", self.x + 16, top, self.width - 32)
    local count = math.floor((self.height - 292) / 22)
    self.scroll = math.min(self.scroll or 0, math.max(0, #report.scripts - count))
    for index = 1, count do
        local entry = report.scripts[index + self.scroll]
        if entry then Ui.label(string.format("%s / %s [%s]   %.2f ms / %d calls / max %.2f", entry.kind, entry.name, tostring(entry.owner or "scope"), entry.totalMs, entry.calls, entry.maxMs), self.x + 16, top + index * 22, self.width - 32) end
    end
    if self.message then Ui.label(self.message, self.x + 16, self.y + self.height - 24, self.width - 32) end
    Theme.setColor("textMuted"); love.graphics.line(self.x + self.width - 14, self.y + self.height - 4, self.x + self.width - 4, self.y + self.height - 14)
    love.graphics.pop()
end
return Window
