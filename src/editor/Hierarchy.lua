local Theme = require("editor.Theme")
local Ui = require("editor.Ui")
local Box = require("editor.ui.SelectionBox")
local Scrollbar = require("editor.ui.Scrollbar")
local Hierarchy = {}
Hierarchy.__index = Hierarchy
local HEADER_HEIGHT = 36 + Ui.METRICS.contentPaddingY
local ROW_HEIGHT = Ui.METRICS.treeRowHeight
function Hierarchy.new(level, width)
    local self = setmetatable({level = level, width = width or 300, collapsed = {}, scroll = 0}, Hierarchy)
    self.scrollbar = Scrollbar.new(function() return self.scroll end, function(value) self.scroll = math.floor(value + 0.5) end)
    return self
end
function Hierarchy:layoutScrollbar()
    local top = (self.y or 0) + HEADER_HEIGHT
    local height = math.max(0, (self.height or love.graphics.getHeight()) - HEADER_HEIGHT - 6)
    local visible = math.max(1, math.floor(height / ROW_HEIGHT))
    self.scroll = math.floor(math.max(0, math.min(self.scroll, math.max(0, #self:rows() - visible))))
    self.scrollbar:layout({x = self.width - 18, y = top, w = Scrollbar.WIDTH, h = height}, #self:rows(), visible)
end
function Hierarchy:containsPoint(x, y)
    return x >= 0 and x < self.width and y >= (self.y or 0) and (not self.height or y < (self.y or 0) + self.height)
end
function Hierarchy:rows() return self.level and self.level:treeRows(self.collapsed) or {} end
function Hierarchy:revealObject(object)
    local parent = object.parentAuthoringId and self.level:findLObject(object.parentAuthoringId)
    while parent do self.collapsed[parent.authoringId] = nil; parent = parent.parentAuthoringId and self.level:findLObject(parent.parentAuthoringId) end
    local visible = math.max(1, math.floor(((self.height or love.graphics.getHeight()) - HEADER_HEIGHT) / ROW_HEIGHT))
    for index, row in ipairs(self:rows()) do if row.object == object then self.scroll = math.max(0, index - visible) end end
end
function Hierarchy:nameRect(object)
    for index, row in ipairs(self:rows()) do if row.object == object then
        return {x = Ui.METRICS.contentPaddingX + row.depth * 16 + 18, y = (self.y or 0) + HEADER_HEIGHT + (index - 1 - self.scroll) * ROW_HEIGHT,
            w = math.max(60, self.width - row.depth * 16 - 76), h = ROW_HEIGHT}
    end end
end
function Hierarchy:prefabGroup(object)
    if not object then return nil end
    local current = object
    while current do
        local path = self.project and self.project:getAssetReference(current.definitionReference)
        if path and path:match("%.prefab$") then return current.authoringId, current.definitionReference end
        local parent = current.parentAuthoringId and self.level:findLObject(current.parentAuthoringId)
        if not current.prefabRootId or not parent or parent.authoringId ~= current.prefabRootId and parent.prefabRootId ~= current.prefabRootId then return nil end
        current = parent
    end
end
function Hierarchy:rowAt(x, y)
    if not self:containsPoint(x, y) or y < (self.y or 0) + HEADER_HEIGHT then return nil end
    return self:rows()[math.floor((y - (self.y or 0) - HEADER_HEIGHT) / ROW_HEIGHT) + 1 + self.scroll]
end
function Hierarchy:getLObjectAtPosition(x, y) local row = self:rowAt(x, y); return row and row.object end
function Hierarchy:mousepressed(x, y, button)
    self:layoutScrollbar()
    local handled, capture = self.scrollbar:dispatch("mousepressed", x, y, button)
    if handled then return true, capture end
    local view, row = self.sceneView, self:rowAt(x, y)
    if button == 1 and row and x >= self.width - 44 and x < self.width - 18 then
        local _, reference = self:prefabGroup(row.object)
        if reference and self.onLocatePrefab then self.onLocatePrefab(reference); return true end
    end
    if button == 2 then if self.onContextMenu then self.onContextMenu(x, y, row and row.object) end; return true end
    if button ~= 1 then return true end
    if row and row.children and x < Ui.METRICS.contentPaddingX + row.depth * 16 + 16 then
        self.collapsed[row.object.authoringId] = not self.collapsed[row.object.authoringId]; return true
    end
    local toggle = love.keyboard.isDown("lctrl", "rctrl")
    if row then
        if love.keyboard.isDown("lshift", "rshift") and self.anchor == row.object then
            view:setSelection({row.object})
        elseif love.keyboard.isDown("lshift", "rshift") and self.anchor then
            local selecting, objects = false, {}
            for _, current in ipairs(self:rows()) do
                if current.object == row.object or current.object == self.anchor then
                    if selecting then objects[#objects + 1] = current.object; break end
                    selecting = true
                end
                if selecting then objects[#objects + 1] = current.object end
            end
            view:setSelection(objects)
        else view:selectLObject(row.object, toggle) end
        self.anchor = row.object
        self.drag = {x = x, y = y, startX = x, startY = y, objects = view:getSelection()}
    else
        local previous = toggle and view:getSelection() or {}; view:setSelection(previous)
        self.drag = {x = x, y = y, startX = x, startY = y, marquee = true, previous = previous}
    end
    return true, true
end
function Hierarchy:mousemoved(x, y)
    if self.scrollbar:dispatch("mousemoved", x, y) then return true end
    local drag = self.drag; if not drag then return true end
    drag.x, drag.y = x, y
    drag.active = drag.active or (x - drag.startX)^2 + (y - drag.startY)^2 >= 36
    if drag.marquee then
        local rect, objects = Box.rect(drag.startX, drag.startY, x, y), {}
        for _, object in ipairs(drag.previous) do objects[#objects + 1] = object end
        for i, row in ipairs(self:rows()) do
            local rowY = (self.y or 0) + HEADER_HEIGHT + (i - 1 - self.scroll) * ROW_HEIGHT
            if rowY >= (self.y or 0) + HEADER_HEIGHT and rowY < (self.y or 0) + (self.height or love.graphics.getHeight()) and
                Box.intersects(rect, {x = 0, y = rowY, w = self.width, h = ROW_HEIGHT}) then
                local found = false; for _, object in ipairs(objects) do if object == row.object then found = true end end
                if not found then objects[#objects + 1] = row.object end
            end
        end
        self.sceneView:setSelection(objects)
    else
        local row = self:rowAt(x, y); drag.target = row and row.object
        local rows = self:rows()
        drag.intent = require("editor.ui.TreeDrop").tree(rows, row, y,
            row and self:nameRect(row.object).y or (self.y or 0) + HEADER_HEIGHT + (#rows - self.scroll) * ROW_HEIGHT, ROW_HEIGHT)
        drag.target = drag.intent.target and drag.intent.target.object
    end
    return true
end
function Hierarchy:dropParent(objects, target)
    local roots = self.level:selectionRoots(objects)
    if target and #roots > 0 then
        local sameParent = true
        for _, object in ipairs(roots) do
            if object.parentAuthoringId ~= target.authoringId then sameParent = false; break end
        end
        if sameParent then return nil, true end
    end
    return target, false
end
function Hierarchy:mousereleased(x, y, button)
    if self.scrollbar:dispatch("mousereleased", x, y, button) then return true end
    local drag = self.drag; self.drag = nil
    if button == 1 and drag and drag.active and not drag.marquee and self:containsPoint(x, y) then
        local row = self:rowAt(x, y)
        local top = row and self:nameRect(row.object).y or 0
        local rows = self:rows()
        local intent = require("editor.ui.TreeDrop").tree(rows, row, y,
            row and top or (self.y or 0) + HEADER_HEIGHT + (#rows - self.scroll) * ROW_HEIGHT, ROW_HEIGHT)
        local ok, err = self.level:dropObjects(drag.objects, intent.target and intent.target.object, intent.mode)
        self.error = not ok and err or nil
        if ok and row then self.collapsed[row.object.authoringId] = nil end
    end
    return true
end
function Hierarchy:wheelmoved(amount)
    local visible = math.max(1, math.floor(((self.height or love.graphics.getHeight()) - HEADER_HEIGHT) / ROW_HEIGHT))
    self.scroll = math.max(0, math.min(math.max(0, #self:rows() - visible), math.floor(self.scroll - amount * 3)))
end
function Hierarchy:draw(selected)
    self:layoutScrollbar()
    local top, height = self.y or 0, self.height or love.graphics.getHeight()
    local visible = math.max(1, math.floor((height - HEADER_HEIGHT) / ROW_HEIGHT))
    self.scroll = math.max(0, math.min(self.scroll, math.max(0, #self:rows() - visible)))
    love.graphics.push("all"); love.graphics.setScissor(0, top, self.width, height)
    Ui.panel(0, top, self.width, height); Ui.panelHeading("Hierarchy", 0, top, self.width)
    love.graphics.intersectScissor(6, top + HEADER_HEIGHT, self.width - 12, math.max(0, height - HEADER_HEIGHT - 6))
    local rows = self:rows()
    local appearance = require("editor.ui.PrefabAppearance")
    local highlights = Ui.treeLineHighlights(rows, function(row)
        return self.sceneView and self.sceneView:isSelected(row.object) or not self.sceneView and row.object == selected
    end)
    local groups = appearance.layout(rows, function(object) return self:prefabGroup(object) end, function(object) return object.authoringId end)
    for i, row in ipairs(rows) do
        local rowY = top + HEADER_HEIGHT + (i - 1 - self.scroll) * ROW_HEIGHT
        if rowY + ROW_HEIGHT > top + HEADER_HEIGHT and rowY < top + height then
            local object = row.object
            local group = groups[i]
            local x = Ui.METRICS.contentPaddingX + row.depth * 16
            Ui.treeRow({x = 6, y = rowY, w = self.width - 12, h = ROW_HEIGHT}, self.sceneView and self.sceneView:isSelected(object) or not self.sceneView and object == selected)
            Ui.treeLines(Ui.METRICS.contentPaddingX + 7, rowY, ROW_HEIGHT, row.depth, 16, highlights[i])
            Theme.setColor("text")
            if row.children then Ui.chevron(x + 7, rowY + ROW_HEIGHT / 2, not self.collapsed[object.authoringId]) end
            if group.isRoot then appearance.icon(self.width - 54, rowY + ROW_HEIGHT / 2 - 1) end
            Ui.text(object.name or "LObject " .. object.authoringId, x + 18, rowY + 4, self.width - x - 78, appearance.textColor(group))
            if group.key then Ui.browseButton({x = self.width - 44, y = rowY, w = 26, h = ROW_HEIGHT}, true, "Locate source Prefab") end
            if self.drag and self.drag.active and not self.drag.marquee and self.drag.target == object then
                Theme.setColor("focus")
                local mode = self.drag.intent and self.drag.intent.mode or "attach"
                if mode == "attach" then love.graphics.rectangle("line", 6, rowY, self.width - 12, ROW_HEIGHT)
                end
                local _, detach = self:dropParent(self.drag.objects, object)
                Ui.hint({x = 6, y = rowY, w = self.width - 12, h = ROW_HEIGHT},
                    detach and "Release to detach from parent." or "Release to attach to this object.")
            end
        end
    end
    if self.drag and self.drag.active and not self.drag.marquee and self.drag.intent and self.drag.intent.mode ~= "attach" and self.drag.intent.target then
        local intent = self.drag.intent; Theme.setColor("focus")
        love.graphics.line(Ui.METRICS.contentPaddingX + intent.depth * 16, intent.lineY, self.width - 12, intent.lineY)
    end
    if self.drag and self.drag.marquee then Box.draw(Box.rect(self.drag.startX, self.drag.startY, self.drag.x, self.drag.y)) end
    self.scrollbar:draw()
    love.graphics.pop()
end
return Hierarchy
