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
function Tree:nameRect(path)
    for index, node in ipairs(self.nodes) do if node.key == path then
        return {x = self.x + 24 + node.depth * 14, y = self.y + (index - 1 - self.scroll) * ROW_HEIGHT,
            w = math.max(60, self.width - node.depth * 14 - 76), h = ROW_HEIGHT}
    end end
end
function Tree:prefabGroup(object)
    local current = object
    while current do
        if current == self.object then
            if self.rootReference then return current.path, self.rootReference end
            return nil
        end
        if current.reference then return current.path, current.reference end
        if not current.isInherited then return nil end
        current = current.parent
    end
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
            local _, reference = self:prefabGroup(node.object)
            if reference and x >= self.x + self.width - 44 and self.onLocatePrefab then self.onLocatePrefab(reference)
            elseif x < self.x + 24 + node.depth * 14 and #node.children > 0 then
                self.expanded[node.key] = self.expanded[node.key] == false; self:rebuild()
            else self.drag = {path = node.key, x = x, y = y}; self:choose(node); return true, true end
        end
    elseif event == "mousemoved" and self.drag then
        local x, y = ...
        self.drag.active = self.drag.active or (x - self.drag.x)^2 + (y - self.drag.y)^2 >= 36
        local target = self:nodeAt(x, y)
        local top = target and self:nameRect(target.key).y or self.y
        self.drag.intent = require("editor.ui.TreeDrop").intent(target, y, top, ROW_HEIGHT)
        self.drag.yNow = y
    elseif event == "mousereleased" and self.drag then
        local drag = self.drag; self.drag = nil
        local x, y = ...
        if drag.active and x and y and self:containsPoint(x, y) and self.onDrop then
            local target = self:nodeAt(x, y)
            local intent = require("editor.ui.TreeDrop").intent(target, y, target and self:nameRect(target.key).y or self.y, ROW_HEIGHT)
            self.onDrop(drag.path, target and target.key, intent.mode)
        end
    elseif event == "cancel" then self.drag = nil
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
    local appearance = require("editor.ui.PrefabAppearance")
    local groups = appearance.layout(self.nodes, function(object) return self:prefabGroup(object) end, function(object) return object.path end)
    local selectedGroup
    for _, node in ipairs(self.nodes) do if node.key == self.selected then selectedGroup = self:prefabGroup(node.object) end end
    for row = 1, self.rows do
        local node = self.nodes[row + self.scroll]; if not node then break end
        local y, x = self.y + (row - 1) * ROW_HEIGHT, self.x + 8 + node.depth * 14
        local group = groups[row + self.scroll]
        if node.key == self.selected then Ui.selection(self.x, y, self.width, ROW_HEIGHT) end
        if group.showRange then
            local branchEnd = x + (#node.children > 0 and 0 or 16) - 4
            appearance.range(self.x + 12 + group.depth * 14, y, ROW_HEIGHT, group.key == selectedGroup, group.first, group.last, group.isRoot, branchEnd)
        end
        if self.ping and self.ping.key == node.key then
            Theme.setColor("focus"); love.graphics.rectangle("line", self.x + 1, y + 1, self.width - 2 - Scrollbar.WIDTH, ROW_HEIGHT - 2)
        end
        if #node.children > 0 then Ui.chevron(x, y + ROW_HEIGHT / 2, self.expanded[node.key] ~= false) end
        if group.isRoot then appearance.icon(self.x + self.width - 54, y + ROW_HEIGHT / 2 - 1) end
        Ui.text(node.label, x + 16, y + 5, math.max(0, self.width - (x - self.x) - 76))
        if group.key then Ui.browseButton({x = self.x + self.width - 44, y = y, w = 26, h = ROW_HEIGHT}, true, "Locate source Prefab") end
    end
    self.scrollbar:draw()
    if self.drag and self.drag.active and self.drag.intent and self.drag.intent.target then
        local rect = self:nameRect(self.drag.intent.target.key)
        Theme.setColor("focus")
        if self.drag.intent.mode == "attach" then love.graphics.rectangle("line", self.x + 2, rect.y, self.width - 4, ROW_HEIGHT)
        else love.graphics.line(self.x + 2, rect.y + (self.drag.intent.mode == "after" and ROW_HEIGHT or 0), self.x + self.width - 2, rect.y + (self.drag.intent.mode == "after" and ROW_HEIGHT or 0)) end
    end
    love.graphics.pop()
end
return Tree
