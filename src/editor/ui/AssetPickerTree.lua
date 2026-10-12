local Widget = require("editor.ui.Widget")
local Ui = require("editor.Ui")
local Theme = require("editor.Theme")
local Tree = setmetatable({}, {__index = Widget})
Tree.__index = Tree
local ROW = Ui.METRICS.treeRowHeight
function Tree.new(files, selected, onSelect)
    local self = setmetatable(Widget.new(), Tree)
    self.files, self.selected, self.onSelect, self.expanded, self.scroll = files, selected, onSelect, {Assets = true}, 0
    local parent = selected and selected:match("^(.*)/[^/]+$")
    while parent do self.expanded[parent] = true; parent = parent:match("^(.*)/[^/]+$") end
    self.scrollbar = require("editor.ui.Scrollbar").new(function() return self.scroll end, function(value) self.scroll = math.floor(value + 0.5) end)
    self:rebuild(); return self
end
function Tree:rebuild()
    local root = {children = {}, path = "", name = ""}
    for _, file in ipairs(self.files) do
        local node, path = root, ""
        for part in file:gmatch("[^/]+") do
            path = path == "" and part or path .. "/" .. part
            node.children[part] = node.children[part] or {children = {}, path = path, name = part}
            node = node.children[part]
        end
        node.file = true
    end
    self.nodes = {}
    local function visit(node, depth)
        local children = {}; for _, child in pairs(node.children) do children[#children + 1] = child end
        table.sort(children, function(a, b) if a.file ~= b.file then return not a.file end; return a.name < b.name end)
        for _, child in ipairs(children) do
            child.depth = depth; self.nodes[#self.nodes + 1] = child
            if self.expanded[child.path] then visit(child, depth + 1) end
        end
    end
    visit(root, 0); self:clampScroll()
end
function Tree:clampScroll()
    self.rows = math.max(1, math.floor(self.height / ROW))
    self.scroll = math.floor(math.max(0, math.min(self.scroll, math.max(0, #self.nodes - self.rows))))
    self.scrollbar:layout({x = self.x + self.width - 12, y = self.y, w = 12, h = self.height}, #self.nodes, self.rows)
end
function Tree:setBounds(x, y, w, h) Widget.setBounds(self, x, y, w, h); self:clampScroll() end
function Tree:dispatch(event, ...)
    local handled, capture = self.scrollbar:dispatch(event, ...); if handled then return handled, capture end
    if event == "mousepressed" then
        local _, y, button = ...
        local node = self.nodes[math.floor((y - self.y) / ROW) + 1 + self.scroll]
        if button == 1 and node then
            if node.file then self.selected = node.path; self.onSelect(node.path)
            else self.expanded[node.path] = not self.expanded[node.path]; self:rebuild() end
        end
    elseif event == "wheelmoved" then local _, _, amount = ...; self.scroll = self.scroll - amount * 3; self:clampScroll() end
    return true
end
function Tree:draw()
    love.graphics.push("all"); love.graphics.intersectScissor(self.x, self.y, self.width, self.height)
    Theme.setColor("input"); love.graphics.rectangle("fill", self.x, self.y, self.width, self.height, 4, 4)
    for i = 1, self.rows do
        local node = self.nodes[i + self.scroll]; if not node then break end
        local y, x = self.y + (i - 1) * ROW, self.x + 10 + node.depth * 14
        Ui.treeRow({x = self.x, y = y, w = self.width, h = ROW}, node.path == self.selected)
        if not node.file then Ui.chevron(x, y + ROW / 2, self.expanded[node.path]) end
        Ui.text(node.name, x + 16, y + 4, self.width - (x - self.x) - 34)
    end
    self.scrollbar:draw(); love.graphics.pop()
end
return Tree
