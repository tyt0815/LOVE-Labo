local Canvas = require("editor.ui.Canvas")
local Ui = require("editor.Ui")
local Toolbar = setmetatable({}, {__index = Canvas})
Toolbar.__index = Toolbar

function Toolbar.new(app)
    local self = setmetatable(Canvas.new(), Toolbar)
    self.playControls, self.snapControls = app.playControls, app.viewportControls
    self.snapControls.embedded = true
    self.playSlot = self:addChild(self.playControls)
    self.snapSlot = self:addChild(self.snapControls, {z = 1})
    self.handlers.draw = function() Ui.panel(self.x, self.y, self.width, self.height) end
    self.handlers.bounds = function(_, _, _, width) self:arrangeControls(width) end
    return self
end

function Toolbar:singleRow(width)
    return width >= 2 * (self.snapControls:preferredWidth() + 16) + 92
end

function Toolbar:preferredHeight(width)
    if self:singleRow(width) then return Ui.METRICS.playBarHeight end
    return Ui.METRICS.playBarHeight + self.snapControls:preferredHeight(math.max(0, width - 32)) + 12
end

function Toolbar:arrangeControls(width)
    local rowHeight = Ui.METRICS.playBarHeight
    self.playSlot.width, self.playSlot.height = width, rowHeight
    local snapWidth = math.min(self.snapControls:preferredWidth(), math.max(0, width - 32))
    local snapHeight = self.snapControls:preferredHeight(snapWidth)
    self.snapSlot.width, self.snapSlot.height = snapWidth, snapHeight
    if self:singleRow(width) then
        self.snapSlot.x, self.snapSlot.y = width - 16 - snapWidth, (rowHeight - snapHeight) / 2
    else
        self.snapSlot.x, self.snapSlot.y = (width - snapWidth) / 2, rowHeight
    end
end

return Toolbar
