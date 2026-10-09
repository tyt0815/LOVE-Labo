local Widget = require("editor.ui.Widget")
local Theme = require("editor.Theme")
local Ui = require("editor.Ui")
local FolderTree = setmetatable({}, {__index = Widget})
FolderTree.__index = FolderTree
local ROW = 28

function FolderTree.new(project, root, excluded, selected, onSelect)
    local self = setmetatable(Widget.new(), FolderTree)
    self.project, self.root, self.excluded, self.selected, self.onSelect = project, root, excluded, selected, onSelect
    self.expanded, self.scroll = {[root] = true}, 0
    local parent = selected
    while parent do self.expanded[parent] = true; parent = parent:match("^(.*)/[^/]+$") end
    self:rebuild()
    return self
end

function FolderTree:rebuild()
    self.nodes, self.error = {}, nil
    local function visit(reference, depth)
        if self.excluded and (reference:lower() == self.excluded:lower()
            or reference:lower():sub(1, #self.excluded + 1) == self.excluded:lower() .. "/") then return end
        self.nodes[#self.nodes + 1] = {reference = reference, depth = depth, name = reference:match("[^/]+$")}
        if not self.expanded[reference] then return end
        local entries, err = self.project:listDirectory(reference)
        if not entries then self.error = err; return end
        for _, entry in ipairs(entries) do
            if entry.type == "directory" and not entry.isLink then visit(entry.reference, depth + 1) end
        end
    end
    visit(self.root, 0)
    self:clampScroll()
end

function FolderTree:clampScroll()
    self.rows = math.max(1, math.floor(self.height / ROW))
    self.scroll = math.floor(math.max(0, math.min(self.scroll, math.max(0, #self.nodes - self.rows))))
end

function FolderTree:choose(node)
    self.selected = node.reference
    if self.onSelect then self.onSelect(node.reference) end
end

function FolderTree:dispatch(event, ...)
    if event == "mousepressed" then
        local x, y, button = ...
        if button == 1 then
            local node = self.nodes[math.floor((y - self.y) / ROW) + 1 + self.scroll]
            if node then
                if x < self.x + 28 + node.depth * 16 then
                    self.expanded[node.reference] = not self.expanded[node.reference]
                    self:rebuild()
                else self:choose(node) end
            end
        end
    elseif event == "wheelmoved" then
        local _, _, amount = ...
        self.scroll = self.scroll - amount * 3
        self:clampScroll()
    elseif event == "keypressed" then
        local key = ...
        local index = 1
        for i, node in ipairs(self.nodes) do if node.reference == self.selected then index = i end end
        local node = self.nodes[index]
        if key == "up" or key == "down" then
            index = math.max(1, math.min(#self.nodes, index + (key == "up" and -1 or 1)))
            self:choose(self.nodes[index])
            self.scroll = math.max(math.min(self.scroll, index - 1), index - self.rows)
        elseif key == "right" and node then self.expanded[node.reference] = true; self:rebuild()
        elseif key == "left" and node then self.expanded[node.reference] = false; self:rebuild() end
    end
    return true
end

function FolderTree:draw()
    self:clampScroll()
    love.graphics.push("all")
    love.graphics.intersectScissor(self.x, self.y, self.width, self.height)
    Theme.setColor("input")
    love.graphics.rectangle("fill", self.x, self.y, self.width, self.height)
    for row = 1, self.rows do
        local node = self.nodes[row + self.scroll]
        if not node then break end
        local y = self.y + (row - 1) * ROW
        if node.reference == self.selected then
            Ui.selection(self.x, y, self.width, ROW)
        end
        local x = self.x + 10 + node.depth * 16
        Theme.setColor("textMuted")
        if not node.children or #node.children > 0 then
            if self.expanded[node.reference] then love.graphics.line(x, y + 11, x + 4, y + 15, x + 8, y + 11)
            else love.graphics.line(x + 2, y + 9, x + 6, y + 13, x + 2, y + 17) end
        end
        Ui.text(node.name .. (node.error and " (Invalid)" or ""), x + 16, y + 7, self.width - (x - self.x) - 24,
            node.error and Theme.color("error") or nil)
        Ui.hint({x = self.x, y = y, w = self.width, h = ROW}, node.error or
            ("Select " .. (node.path or node.reference) .. ". Arrows: expand or collapse."))
    end
    love.graphics.pop()
end
return FolderTree
