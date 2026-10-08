local Widget = require("editor.ui.widget")
local Slot = require("editor.ui.slot")
local Panel = setmetatable({}, { __index = Widget })
Panel.__index = Panel

function Panel.new()
    local self = setmetatable(Widget.new(), Panel)
    self.slots = {}
    self.clip = true
    return self
end

function Panel:addChild(widget, layout)
    assert(not widget.parent, "widget already has a parent")
    local ancestor = self
    while ancestor do
        assert(ancestor ~= widget, "widget tree cannot contain a cycle")
        ancestor = ancestor.parent
    end
    local slot = Slot.new(widget, layout)
    widget.parent, widget.slot = self, slot
    self.slots[#self.slots + 1] = slot
    slot.order = #self.slots
    slot:arrange(self)
    return slot
end

function Panel:orderedSlots()
    local slots = {}
    for _, slot in ipairs(self.slots) do slots[#slots + 1] = slot end
    table.sort(slots, function(a, b)
        if a.z == b.z then return a.order < b.order end
        return a.z < b.z
    end)
    return slots
end

function Panel:hitTest(x, y)
    if not self.visible or not self.enabled then return nil end
    if self.clip and not self:containsPoint(x, y) then return nil end
    local slots = self:orderedSlots()
    for index = #slots, 1, -1 do
        local target = slots[index].widget:hitTest(x, y)
        if target then return target end
    end
    if self:containsPoint(x, y) and self.handlers.mousepressed then return self end
end

function Panel:draw()
    if not self.visible or self.width <= 0 or self.height <= 0 then return end
    love.graphics.push("all")
    if self.clip then love.graphics.intersectScissor(self.x, self.y, self.width, self.height) end
    Widget.draw(self)
    for _, slot in ipairs(self:orderedSlots()) do
        -- 자식의 렌더링 상태가 형제나 부모로 새지 않게 각 경계에서 복원한다.
        love.graphics.push("all")
        slot.widget:draw()
        love.graphics.pop()
    end
    love.graphics.pop()
end

return Panel
