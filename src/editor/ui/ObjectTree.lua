local Scrollbar = require("editor.ui.Scrollbar")
local Widget = require("editor.ui.Widget")
local Ui = require("editor.Ui")
local Theme = require("editor.Theme")
local Tree = setmetatable({}, {__index = Widget})
Tree.__index = Tree
local ROW_HEIGHT = 26
function Tree.new(root, onSelect, onContext)
    local self = setmetatable(Widget.new(), Tree)
    self.object, self.onSelect, self.selected, self.expanded, self.scroll = root, onSelect, "root", {}, 0
    self.onContext = onContext
    self.scrollbar = Scrollbar.new(function() return self.scroll end,
        function(value) self.scroll = math.floor(value + 0.5) end)
    self:rebuild()
    return self
end
function Tree:rebuild()
    self.nodes = {}
    local function visit(object, depth)
        self.nodes[#self.nodes + 1] = {key = object.path, object = object, depth = depth, children = object.children,
            label = object.name or object.reference or "LObject"}
        if self.expanded[object.path] ~= false then for _, child in ipairs(object.children) do visit(child, depth + 1) end end
    end
    visit(self.object, 0); self:clampScroll()
end
function Tree:setBounds(x, y, width, height)
    Widget.setBounds(self, x, y, width, height)
    self:clampScroll()
end

function Tree:clampScroll()
    self.rows = math.max(1, math.floor(self.height / ROW_HEIGHT))
    self.scroll = math.floor(math.max(0, math.min(self.scroll, math.max(0, #self.nodes - self.rows))))
    if self.scrollbar then self.scrollbar:layout({x = self.x + self.width - Scrollbar.WIDTH, y = self.y,
        w = Scrollbar.WIDTH, h = self.height}, #self.nodes, self.rows) end
end
function Tree:nodeAt(x, y)
    if not self:containsPoint(x, y) then return nil end
    return self.nodes[math.floor((y - self.y) / ROW_HEIGHT) + 1 + self.scroll]
end
function Tree:choose(node)
    if not node then return end
    self.selected = node.key
    if self.onSelect then self.onSelect(node.key) end
end
function Tree:reveal(path)
    local parent = path
    while parent do self.expanded[parent] = true; parent = parent:match("^(.*)/[^/]+$") end
    self:rebuild()
    for index, node in ipairs(self.nodes) do
        if node.key == path then
            self.scroll = math.max(0, math.min(math.max(0, #self.nodes - self.rows), math.max(index - self.rows, math.min(self.scroll, index - 1))))
            self.ping = {key = path, remaining = 1.5}; return true
        end
    end
    return false, "Referenced object is missing"
end
function Tree:dispatch(event, ...)
    local handled, capture = self.scrollbar:dispatch(event, ...)
    if handled then return true, capture end
    if event == "mousepressed" then
        local x, y, button = ...
        local node = self:nodeAt(x, y)
        if button == 2 and node and self.onContext then self.onContext(node.key, x, y); return true end
        if button == 1 and node then
            if x < self.x + 24 + node.depth * 14 and #node.children > 0 then
                self.expanded[node.key] = self.expanded[node.key] == false; self:rebuild()
            else self:choose(node) end
        end
    elseif event == "wheelmoved" then
        local _, _, amount = ...; self.scroll = self.scroll - amount * 3; self:clampScroll()
    elseif event == "keypressed" then
        local key, index = ..., 1
        for i, node in ipairs(self.nodes) do if node.key == self.selected then index = i end end
        if key == "up" or key == "down" then self:choose(self.nodes[math.max(1, math.min(#self.nodes, index + (key == "up" and -1 or 1)))])
        elseif key == "left" or key == "right" then self.expanded[self.selected] = key == "right"; self:rebuild() end
    end
    return true
end
function Tree:draw()
    self:clampScroll(); love.graphics.push("all")
    love.graphics.intersectScissor(self.x, self.y, self.width, self.height)
    Theme.setColor("input"); love.graphics.rectangle("fill", self.x, self.y, self.width, self.height, 4, 4)
    for row = 1, self.rows do
        local node = self.nodes[row + self.scroll]; if not node then break end
        local y, x = self.y + (row - 1) * ROW_HEIGHT, self.x + 8 + node.depth * 14
        if node.key == self.selected then Ui.selection(self.x, y, self.width, ROW_HEIGHT) end
        if self.ping and self.ping.key == node.key then
            Theme.setColor("focus"); love.graphics.rectangle("line", self.x + 1, y + 1, self.width - 2 - Scrollbar.WIDTH, ROW_HEIGHT - 2)
        end
        if #node.children > 0 then Ui.chevron(x, y + ROW_HEIGHT / 2, self.expanded[node.key] ~= false) end
        Ui.text(node.label, x + 16, y + 5, math.max(0, self.width - (x - self.x) - 34))
        Ui.hint({x = self.x, y = y, w = self.width, h = ROW_HEIGHT}, "Select " .. node.label .. ". Drop a template or an instance to add children.")
    end
    self.scrollbar:draw()
    love.graphics.pop()
end
return Tree
