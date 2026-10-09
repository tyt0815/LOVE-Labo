local Widget = require("editor.ui.Widget")
local Panel = require("editor.ui.Panel")
local Canvas = setmetatable({}, { __index = Panel })
Canvas.__index = Canvas

function Canvas.new()
    return setmetatable(Panel.new(), Canvas)
end

function Canvas:setBounds(x, y, width, height)
    Widget.setBounds(self, x, y, width, height)
    for _, slot in ipairs(self.slots) do slot:arrange(self) end
end

function Canvas:setSlotBounds(slot, x, y, width, height)
    assert(slot.widget.parent == self, "slot belongs to another panel")
    slot.x, slot.y, slot.width, slot.height = x, y, width, height
    slot:arrange(self)
end

return Canvas
