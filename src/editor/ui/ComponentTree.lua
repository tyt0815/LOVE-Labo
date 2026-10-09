local Scrollbar = require("editor.ui.Scrollbar")
local Widget = require("editor.ui.Widget")
local Ui = require("editor.Ui")
local Theme = require("editor.Theme")
local Tree = setmetatable({}, {__index = Widget})
Tree.__index = Tree
local ROW = 26

function Tree.new(object, label, onSelect, componentsOnly)
    local self = setmetatable(Widget.new(), Tree)
    self.object, self.label, self.onSelect = object, label, onSelect
    self.componentsOnly = componentsOnly
    self.selected, self.expanded, self.scroll = false, {}, 0
    self.scrollbar = Scrollbar.new(function() return self.scroll end,
        function(value) self.scroll = math.floor(value + 0.5) end)
    self:rebuild()
    return self
end
function Tree:rebuild()
    self.nodes = self.componentsOnly and {} or {{key = false, label = self.label, depth = 0, children = {self.object.rootComponent}}}
    local function visit(component, depth)
        self.nodes[#self.nodes + 1] = {key = component.name, label = component.name .. " (" .. component.componentType .. ")",
            depth = depth, children = component.children}
        if self.expanded[component.name] ~= false then
            for _, child in ipairs(component.children) do visit(child, depth + 1) end
        end
    end
    if self.componentsOnly or self.expanded[false] ~= false then visit(self.object.rootComponent, self.componentsOnly and 0 or 1) end
    self:clampScroll()
end
function Tree:setBounds(x, y, width, height)
    Widget.setBounds(self, x, y, width, height)
    self:clampScroll()
end

function Tree:clampScroll()
    self.rows = math.max(1, math.floor(self.height / ROW))
    self.scroll = math.floor(math.max(0, math.min(self.scroll, #self.nodes - self.rows)))
    if self.scrollbar then self.scrollbar:layout({x = self.x + self.width - Scrollbar.WIDTH, y = self.y,
        w = Scrollbar.WIDTH, h = self.height}, #self.nodes, self.rows) end
end
function Tree:choose(node)
    if not node then return end
    self.selected = node.key
    if self.onSelect then self.onSelect(node.key or nil) end
end
function Tree:reveal(name)
    local component = name and self.object.components[name]
    while component and component.parent do
        self.expanded[component.parent.name] = true
        component = component.parent
    end
    self.expanded[false] = true
    self.selected = name or false
    self:rebuild()
    for index, node in ipairs(self.nodes) do
        if node.key == self.selected then
            self.scroll = math.max(math.min(self.scroll, index - 1), index - self.rows)
            break
        end
    end
end
function Tree:dispatch(event, ...)
    local handled, capture = self.scrollbar:dispatch(event, ...)
    if handled then return true, capture end
    if event == "mousepressed" then
        local x, y, button = ...
        local node = self.nodes[math.floor((y - self.y) / ROW) + 1 + self.scroll]
        if button == 1 and node then
            if x < self.x + 24 + node.depth * 14 and #node.children > 0 then
                local key = node.key
                self.expanded[key] = self.expanded[key] == false
                self:rebuild()
            else self:choose(node) end
        end
    elseif event == "wheelmoved" then local _, _, amount = ...; self.scroll = self.scroll - amount * 3; self:clampScroll()
    elseif event == "keypressed" then
        local key, index = ..., 1
        for i, node in ipairs(self.nodes) do if node.key == self.selected then index = i end end
        if key == "up" or key == "down" then
            index = math.max(1, math.min(#self.nodes, index + (key == "up" and -1 or 1)))
            self:choose(self.nodes[index]); self.scroll = math.max(math.min(self.scroll, index - 1), index - self.rows)
        elseif key == "left" or key == "right" then
            self.expanded[self.nodes[index].key] = key == "right"; self:rebuild()
        end
    end
    return true
end
function Tree:draw()
    self:clampScroll()
    love.graphics.push("all")
    love.graphics.intersectScissor(self.x, self.y, self.width, self.height)
    Theme.setColor("input"); love.graphics.rectangle("fill", self.x, self.y, self.width, self.height, 4, 4)
    for row = 1, self.rows do
        local node = self.nodes[row + self.scroll]
        if not node then break end
        local y, x = self.y + (row - 1) * ROW, self.x + 8 + node.depth * 14
        if node.key == self.selected then Ui.selection(self.x, y, self.width, ROW) end
        if #node.children > 0 then Ui.chevron(x, y + ROW / 2, self.expanded[node.key] ~= false) end
        Ui.text(node.label, x + 16, y + 5, math.max(0, self.width - (x - self.x) - 34))
        Ui.hint({x = self.x, y = y, w = self.width, h = ROW}, "Select " .. node.label .. " properties.")
    end
    self.scrollbar:draw()
    love.graphics.pop()
end
return Tree
