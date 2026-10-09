local Slot = {}
Slot.__index = Slot

function Slot.new(widget, layout)
    local self = setmetatable({ widget = widget, x = 0, y = 0,
        width = 0, height = 0, z = 0, fill = false }, Slot)
    for key, value in pairs(layout or {}) do self[key] = value end
    return self
end

function Slot:arrange(parent)
    if self.fill then
        self.widget:setBounds(parent.x, parent.y, parent.width, parent.height)
    else
        self.widget:setBounds(parent.x + self.x, parent.y + self.y, self.width, self.height)
    end
end

return Slot
