local Canvas = require("editor.ui.Canvas")
local Ui = require("editor.Ui")
local Widget = require("editor.ui.Widget")
local Toolbar = setmetatable({}, {__index = Canvas})
Toolbar.__index = Toolbar

function Toolbar.new(app)
    local self = setmetatable(Canvas.new(), Toolbar)
    self.playControls, self.snapControls = app.playControls, app.viewportControls
    self.snapControls.embedded = true
    self.playSlot = self:addChild(self.playControls)
    self.snapSlot = self:addChild(self.snapControls, {z = 1})
    self.backgroundControl = Widget.new({
        draw = function(widget)
            local rect = {x = widget.x, y = widget.y, w = widget.width, h = widget.height}
            Ui.button("Colors", rect, false, app:isPlaying() and "Editor color settings are unavailable during Play."
                or "Choose the Scene View background and grid line colors.")
            if app:isPlaying() then
                local color = require("editor.Theme").color("panel")
                love.graphics.setColor(color[1], color[2], color[3], 0.55)
                love.graphics.rectangle("fill", rect.x, rect.y, rect.w, rect.h)
            end
        end,
        mousepressed = function(_, _, _, button)
            if button == 1 and not app:isPlaying() then self:openBackgroundPicker(app) end
            return true
        end,
    })
    self.backgroundSlot = self:addChild(self.backgroundControl, {z = 1})
    self.handlers.draw = function() Ui.panel(self.x, self.y, self.width, self.height) end
    self.handlers.bounds = function(_, _, _, width) self:arrangeControls(width) end
    return self
end

function Toolbar:openBackgroundPicker(app)
    local view = app.sceneView
    local theme = require("editor.Theme").color("grid")
    return require("editor.ui.ColorPicker").new(app.uiRoot, {title = "Scene Colors",
        entries = {{label = "Background", color = view:backgroundColor(), defaultColor = require("editor.Color").default(), useDefault = not view.background},
            {label = "Grid lines", color = view:gridColor(), defaultColor = {theme[1] * 255, theme[2] * 255, theme[3] * 255}, useDefault = not view.gridColorOverride}},
        anchor = {x = self.backgroundControl.x, y = self.backgroundControl.y, w = self.backgroundControl.width, h = self.backgroundControl.height},
        onChange = function(color, _, index)
            view.colorPreview = view.colorPreview or {}; view.colorPreview[index] = color
        end,
        onDismiss = function() view.colorPreview = nil end,
        onConfirm = function(_, _, entries)
            assert(view:setBackground(entries[1].color, entries[1].useDefault))
            return view:setGridColor(entries[2].color, entries[2].useDefault)
        end})
end

function Toolbar:singleRow(width)
    return width >= 2 * (math.max(self.snapControls:preferredWidth(), 104) + 16) + 156
end

function Toolbar:preferredHeight(width)
    if self:singleRow(width) then return Ui.METRICS.playBarHeight end
    local height = Ui.METRICS.playBarHeight + self.snapControls:preferredHeight(math.max(0, width - 32)) + 12
    return height + (width < self.snapControls:preferredWidth() + 152 and 40 or 0)
end

function Toolbar:arrangeControls(width)
    local rowHeight = Ui.METRICS.playBarHeight
    self.playSlot.width, self.playSlot.height = width, rowHeight
    local snapWidth = math.min(self.snapControls:preferredWidth(), math.max(0, width - 32))
    local snapHeight = self.snapControls:preferredHeight(snapWidth)
    self.snapSlot.width, self.snapSlot.height = snapWidth, snapHeight
    self.snapSlot.x = 16
    self.backgroundSlot.x, self.backgroundSlot.width, self.backgroundSlot.height = math.max(16, width - 120), 104, 28
    if self:singleRow(width) then
        self.snapSlot.y = (rowHeight - snapHeight) / 2
        self.backgroundSlot.y = (rowHeight - 28) / 2
    else
        self.snapSlot.y = rowHeight
        self.backgroundSlot.y = width < self.snapControls:preferredWidth() + 152 and rowHeight + snapHeight + 8 or rowHeight
    end
end

return Toolbar
