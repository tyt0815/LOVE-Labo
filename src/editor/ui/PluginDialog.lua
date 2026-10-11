local Ui = require("editor.Ui")
local Theme = require("editor.Theme")
local Scrollbar = require("editor.ui.Scrollbar")
local Widget = require("editor.ui.Widget")
local Operations = require("editor.PluginOperations")
local Dialog = setmetatable({}, {__index = Widget})
Dialog.__index = Dialog
local ROW_HEIGHT, DEPENDENCY_HEIGHT = 32, 20
function Dialog.new(app, state)
    local self = setmetatable(Widget.new(), Dialog)
    self.app, self.root, self.scroll = app, app.uiRoot, state and state.scroll or 0
    self.expanded, self.errorScroll = state and state.expanded or {}, 0
    local width, height = love.graphics.getDimensions()
    self.box = {x = (width - 560) / 2, y = (height - 420) / 2, w = 560, h = 420}
    self.list = {x = self.box.x + 16, y = self.box.y + 52, w = 528, h = 244}
    self.errorBounds = {x = self.list.x, y = self.box.y + 308, w = self.list.w, h = 54}
    self.close = {x = self.box.x + 460, y = self.box.y + 374, w = 84, h = 30}
    self.create = {x = self.box.x + 16, y = self.close.y, w = 130, h = 30}
    self.names = app.project.plugins:names()
    self.handlers.draw = function() self:draw() end
    self.scrollbar = Scrollbar.new(function() return self.scroll end, function(value) self.scroll = value end)
    self.errorScrollbar = Scrollbar.new(function() return self.errorScroll end, function(value) self.errorScroll = value end)
    self:layoutRows()
    self.root:setPopup(self)
    return self
end
function Dialog:layoutRows()
    self.rows = {}
    local offset = 0
    for _, name in ipairs(self.names) do
        local dependencies = self.app.project.plugins.plugins[name].dependencies
        local height = ROW_HEIGHT + (self.expanded[name] and #dependencies * DEPENDENCY_HEIGHT or 0)
        self.rows[#self.rows + 1] = {name = name, offset = offset, height = height}
        offset = offset + height
    end
    self.scroll = math.max(0, math.min(self.scroll, math.max(0, offset - self.list.h)))
    self.scrollbar:layout({x = self.list.x + self.list.w - Scrollbar.WIDTH, y = self.list.y, w = Scrollbar.WIDTH, h = self.list.h}, offset, self.list.h)
    if self.error ~= self.lastError then self.errorScroll, self.lastError = 0, self.error end
    local _, lines = require("editor.Fonts").get(14):getWrap(tostring(self.error or ""), self.errorBounds.w - 32)
    self.errorLines = lines
    self.errorScrollbar:layout({x = self.errorBounds.x + self.errorBounds.w - Scrollbar.WIDTH, y = self.errorBounds.y,
        w = Scrollbar.WIDTH, h = self.errorBounds.h}, #lines * 18, self.errorBounds.h)
    self.errorScroll = math.max(0, math.min(self.errorScroll, self.errorScrollbar.maximum))
end
function Dialog:dependencyStatus(name)
    local registry, visiting, missing, disabled = self.app.project.plugins, {}, false, false
    local function visit(id)
        if visiting[id] then missing = true; return end
        visiting[id] = true
        for _, dependency in ipairs(registry.plugins[id].dependencies) do
            if not registry.plugins[dependency] then missing = true
            else
                if not registry.enabled[dependency] then disabled = true end
                visit(dependency)
            end
        end
        visiting[id] = nil
    end
    visit(name)
    return missing and "error" or disabled and "pluginDependencyDisabled" or nil
end
function Dialog:hitTest() return self end
function Dialog:toggle(name)
    local project = self.app.project
    local enabled = not project.plugins.enabled[name]
    local plan, err = Operations.plan(project, name, enabled)
    if not plan then self.error = err; return end
    local function apply()
        local ok, result = Operations.apply(project, name, enabled, true, self.app.level)
        if not ok then return false, result end
        self.app.assetBrowser:refresh(); self.app:updateInspectorTarget()
        Dialog.new(self.app, {expanded = self.expanded, scroll = self.scroll}); return true
    end
    if #plan <= 1 then local ok, result = apply(); if not ok then self.error = result end; return end
    local choices = {}; for _, id in ipairs(plan) do choices[#choices + 1] = {label = id} end
    require("editor.ui.Dialog").new(self.root, {title = enabled and "Enable dependencies?" or "Disable dependent plugins?",
        message = name, detail = "These plugins will change together.", choices = choices, listOnly = true,
        choiceLabel = "Plugins", confirmLabel = enabled and "Enable" or "Disable", onConfirm = apply})
end
function Dialog:dispatch(event, ...)
    self:layoutRows()
    local handled, capture = self.scrollbar:dispatch(event, ...)
    if not handled and self.error then handled, capture = self.errorScrollbar:dispatch(event, ...) end
    if handled then return true, capture end
    if event == "keypressed" and (...) == "escape" then self.root:dismissPopup()
    elseif event == "wheelmoved" then
        local x, y, amount = ...
        if Ui.contains(x, y, self.list) then
            self.scroll = math.max(0, math.min(self.scrollbar.maximum, self.scroll - amount * ROW_HEIGHT * 3))
        elseif self.error and Ui.contains(x, y, self.errorBounds) then
            self.errorScroll = math.max(0, math.min(self.errorScrollbar.maximum, self.errorScroll - amount * 18 * 3))
        end
    elseif event == "mousepressed" then
        local x, y, button = ...
        if button ~= 1 then return true end
        if Ui.contains(x, y, self.close) then self.root:dismissPopup()
        elseif Ui.contains(x, y, self.create) then
            require("editor.ui.Dialog").new(self.root, {title = "Create Plugin", input = true, value = "NewPlugin", onConfirm = function(name)
                local ok, err = Operations.create(self.app.project, name)
                if not ok then return false, err end
                Dialog.new(self.app, {expanded = self.expanded, scroll = self.scroll}); return true
            end})
        elseif Ui.contains(x, y, self.list) then
            for _, row in ipairs(self.rows) do
                local top = self.list.y + row.offset - self.scroll
                if y >= top and y < top + ROW_HEIGHT then
                    if x < self.list.x + 24 and #self.app.project.plugins.plugins[row.name].dependencies > 0 then
                        self.expanded[row.name] = not self.expanded[row.name]; self:layoutRows()
                    elseif x >= self.list.x + 24 then self:toggle(row.name) end
                    break
                end
            end
        end
    end
    return true
end
function Dialog:draw()
    self:layoutRows()
    local box, registry = self.box, self.app.project.plugins
    Theme.setColor("overlay"); love.graphics.rectangle("fill", 0, 0, love.graphics.getDimensions())
    Theme.setColor("panel"); love.graphics.rectangle("fill", box.x, box.y, box.w, box.h, 6, 6)
    Ui.text("Plugins", box.x + 16, box.y + 16, box.w - 32)
    Theme.setColor("input"); love.graphics.rectangle("fill", self.list.x, self.list.y, self.list.w, self.list.h, 4, 4)
    love.graphics.push("all"); love.graphics.intersectScissor(self.list.x, self.list.y, self.list.w - Scrollbar.WIDTH, self.list.h)
    for _, row in ipairs(self.rows) do
        local name, y = row.name, self.list.y + row.offset - self.scroll
        if y + row.height >= self.list.y and y < self.list.y + self.list.h then
            local plugin = registry.plugins[name]
            Ui.row({x = self.list.x, y = y, w = self.list.w - Scrollbar.WIDTH, h = ROW_HEIGHT}, false)
            if #plugin.dependencies > 0 then Ui.chevron(self.list.x + 8, y + ROW_HEIGHT / 2, self.expanded[name]) end
            Ui.checkbox({x = self.list.x + 26, y = y + 9, w = 14, h = 14}, registry.enabled[name] == true)
            Ui.text(name, self.list.x + 50, y + 8, self.list.w - 84)
            local status = self:dependencyStatus(name)
            if status then Ui.text("!", self.list.x + self.list.w - 32, y + 8, 16, Theme.color(status), true) end
            if self.expanded[name] then
                local previousFont = love.graphics.getFont(); love.graphics.setFont(require("editor.Fonts").get(12))
                for index, dependency in ipairs(plugin.dependencies) do
                local exists, active = registry.plugins[dependency], registry.enabled[dependency]
                    local label = dependency .. (not exists and " [missing]" or active and " [enabled]" or " [disabled]")
                    Ui.text(label, self.list.x + 50, y + ROW_HEIGHT + (index - 1) * DEPENDENCY_HEIGHT + 3, self.list.w - 76,
                        Theme.color(not exists and "error" or active and "textMuted" or "pluginDependencyDisabled"))
                end
                love.graphics.setFont(previousFont)
            end
        end
    end
    love.graphics.pop(); self.scrollbar:draw()
    Ui.button("Create Plugin", self.create); Ui.button("Close", self.close)
    if self.error then
        love.graphics.push("all"); Theme.setColor("input")
        love.graphics.rectangle("fill", self.errorBounds.x, self.errorBounds.y, self.errorBounds.w, self.errorBounds.h, 4, 4)
        love.graphics.intersectScissor(self.errorBounds.x + 6, self.errorBounds.y, self.errorBounds.w - 24, self.errorBounds.h)
        love.graphics.setFont(require("editor.Fonts").get(14))
        for index, line in ipairs(self.errorLines) do
            Ui.text(line, self.errorBounds.x + 6, self.errorBounds.y + (index - 1) * 18 - self.errorScroll, nil, Theme.color("error"))
        end
        love.graphics.pop(); self.errorScrollbar:draw()
    end
end
return Dialog
