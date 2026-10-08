local UI = require("editor.ui")
local Canvas = require("editor.ui.canvas")
local Widget = require("editor.ui.widget")
local Root = require("editor.ui.root")
local Dropdown = require("editor.ui.dropdown")
local Thumbnail = require("editor.asset_thumbnail")
local Breadcrumb = require("editor.ui.breadcrumb")

local AssetBrowser = setmetatable({}, { __index = Canvas })
AssetBrowser.__index = AssetBrowser
local HEADER = 38
local BREADCRUMB = 30
local ROW = 26
local CARD_WIDTH, CARD_HEIGHT = 112, 126

function AssetBrowser.new(project)
    local self = setmetatable(Canvas.new(), AssetBrowser)
    local state = {
        project = project, folder = "Assets", entries = {}, selectedReference = nil,
        expanded = { Assets = true, Sources = true }, children = {}, tree = {},
        treeScroll = 0, fileScroll = 0, collapsed = false,
        x = 0, y = 0, width = 0, height = 0, error = nil,
        viewMode = "thumbnails", panelName = "assets"
    }
    for key, value in pairs(state) do self[key] = value end
    self.thumbnails = Thumbnail.new(project)
    self.localRoot = Root.new(self)
    self.uiRoot = self.localRoot
    self.viewDropdown = Dropdown.new(self.uiRoot,
        { {value = "thumbnails", label = "Thumbnails"}, {value = "list", label = "List"} },
        self.viewMode, function(mode) self:setViewMode(mode) end)
    self.treeSlot = self:addChild(Widget.new({
        draw = function() self:drawTree() end,
        mousepressed = function(_, ...) self:handleContentMousepressed(...); return true end,
        wheelmoved = function(_, ...) self:wheelmoved(...); return true end
    }))
    self.fileSlot = self:addChild(Widget.new({
        draw = function() self:drawFiles() end,
        mousepressed = function(_, ...) self:handleContentMousepressed(...); return true end,
        wheelmoved = function(_, ...) self:wheelmoved(...); return true end
    }))
    self.dropdownSlot = self:addChild(self.viewDropdown, { z = 1 })
    self.breadcrumb = Breadcrumb.new(function(reference)
        if reference ~= self.folder then self:openFolder(reference) end
    end)
    self.breadcrumbSlot = self:addChild(self.breadcrumb, { z = 1 })
    self.handlers.mousepressed = function(_, x, y, button)
        if button ~= 1 then return true end
        local buttons = self:buttons()
        if UI.contains(x, y, buttons.fold) then self.collapsed = not self.collapsed
        elseif UI.contains(x, y, buttons.refresh) then self:refresh() end
        return true
    end
    self.handlers.keypressed = function(_, key)
        if key == "backspace" then self:goUp()
        elseif key == "r" and love.keyboard.isDown("lctrl", "rctrl") then self:refresh()
        elseif key == "return" then
            for _, entry in ipairs(self.entries) do
                if entry.reference == self.selectedReference and entry.type == "directory" and not entry.isLink then
                    self:openFolder(entry.reference); break
                end
            end
        end
        return true
    end
    self:refresh()
    return self
end

function AssetBrowser:setBounds(x, y, width, height)
    Canvas.setBounds(self, x, y, width, height)
    local contentHeight = self.collapsed and 0 or math.max(0, height - HEADER - 28)
    self:setSlotBounds(self.treeSlot, 0, HEADER, self:treeWidth(), contentHeight)
    self:setSlotBounds(self.fileSlot, self:treeWidth(), HEADER + BREADCRUMB,
        self.width - self:treeWidth(), math.max(0, contentHeight - BREADCRUMB))
    self.breadcrumb.visible = not self.collapsed
    self:setSlotBounds(self.breadcrumbSlot, self:treeWidth(), HEADER,
        self.width - self:treeWidth(), self.collapsed and 0 or BREADCRUMB)
    self:setSlotBounds(self.dropdownSlot, self.width - 218, 8, 116, 26)
    self:clampScroll()
end

function AssetBrowser:setUIRoot(root)
    self.uiRoot, self.viewDropdown.root = root, root
end

function AssetBrowser:setViewMode(mode)
    if mode ~= "list" and mode ~= "thumbnails" then return false end
    self.viewMode, self.viewDropdown.value, self.fileScroll = mode, mode, 0
    self:clampScroll()
    return true
end

function AssetBrowser:columns()
    return math.max(1, math.floor((self.width - self:treeWidth() - 16) / CARD_WIDTH))
end

function AssetBrowser:getEntryAtPosition(x, y)
    local split = self.x + self:treeWidth()
    local top = self.y + HEADER + BREADCRUMB
    if x < split or x >= self.x + self.width or y < top or y >= self.y + self.height - 28 then return nil end
    if self.viewMode == "list" then
        return self.entries[math.floor((y - top) / ROW) + 1 + self.fileScroll]
    end
    local column = math.floor((x - split - 8) / CARD_WIDTH)
    local row = math.floor((y - top - 8) / CARD_HEIGHT)
    if column < 0 or column >= self:columns() or row < 0 then return nil end
    return self.entries[(row + self.fileScroll) * self:columns() + column + 1]
end

function AssetBrowser:containsPoint(x, y)
    return UI.contains(x, y, { x = self.x, y = self.y, w = self.width, h = self.height })
end

function AssetBrowser:treeWidth()
    return math.min(220, self.width * 0.35)
end

function AssetBrowser:rebuildTree()
    self.tree = {}
    local function visit(reference, name, depth)
        self.tree[#self.tree + 1] = { reference = reference, name = name, depth = depth }
        if not self.expanded[reference] then return end
        if not self.children[reference] then
            local entries, err = self.project:listDirectory(reference)
            if not entries then self.error = err; return end
            self.children[reference] = entries
        end
        for _, entry in ipairs(self.children[reference]) do
            if entry.type == "directory" and not entry.isLink then
                visit(entry.reference, entry.name, depth + 1)
            end
        end
    end
    visit("Assets", "Assets", 0)
    visit("Sources", "Sources", 0)
    self:clampScroll()
end

function AssetBrowser:openFolder(reference)
    local entries, err = self.project:listDirectory(reference)
    if not entries then self.error = err; return false, err end
    self.folder, self.entries, self.error = reference, entries, nil
    self.breadcrumb.path = reference
    self.thumbnails:clear()
    self.children[reference] = entries
    self.selectedReference, self.fileScroll = nil, 0
    -- 목록에서 들어간 폴더도 트리에 보이도록 조상만 펼친다.
    local parent = reference:match("^(.*)/[^/]+$")
    while parent do
        self.expanded[parent] = true
        parent = parent:match("^(.*)/[^/]+$")
    end
    self:rebuildTree()
    return true
end

function AssetBrowser:refresh()
    self.uiRoot:dismissPopup()
    self.thumbnails:clear()
    self.children = {}
    local selected = self.selectedReference
    local opened, err = self:openFolder(self.folder)
    if not opened then
        self.entries = {}
        local root = self.folder:match("^[^/]+")
        if self.folder ~= root then self:openFolder(root) end
        self.error = err
        self:rebuildTree()
    elseif selected then
        for _, entry in ipairs(self.entries) do
            if entry.reference == selected then self.selectedReference = selected end
        end
    end
    return opened, err
end

function AssetBrowser:goUp()
    if self.folder == "Assets" or self.folder == "Sources" then return false end
    return self:openFolder(self.folder:match("^(.*)/[^/]+$"))
end

function AssetBrowser:clampScroll()
    local visible = math.max(1, math.floor((self.height - HEADER - 28) / ROW))
    self.treeScroll = math.floor(math.max(0, math.min(self.treeScroll, math.max(0, #self.tree - visible))))
    local fileRows = #self.entries
    visible = math.max(1, math.floor((self.height - HEADER - BREADCRUMB - 28) / ROW))
    if self.viewMode == "thumbnails" then
        visible = math.max(1, math.floor((self.height - HEADER - BREADCRUMB - 36) / CARD_HEIGHT))
        fileRows = math.ceil(#self.entries / self:columns())
    end
    self.fileScroll = math.floor(math.max(0, math.min(self.fileScroll, math.max(0, fileRows - visible))))
end

function AssetBrowser:buttons()
    local function button(x, w) return { x = x, y = self.y + 8, w = w, h = 26 } end
    return {
        fold = button(self.x + 8, 32),
        refresh = button(self.x + self.width - 94, 86)
    }
end

function AssetBrowser:draw()
    if self.width <= 0 or self.height <= 0 then return end
    love.graphics.push("all")
    love.graphics.setScissor(self.x, self.y, self.width, self.height)
    love.graphics.setColor(0.105, 0.12, 0.145, 1)
    love.graphics.rectangle("fill", self.x, self.y, self.width, self.height)
    love.graphics.setColor(0.28, 0.30, 0.35, 1)
    love.graphics.line(self.x, self.y, self.x + self.width, self.y)
    local buttons = self:buttons()
    UI.button(self.collapsed and "+" or "-", buttons.fold)
    UI.text("Project Browser", self.x + 50, self.y + 14, math.max(0, self.width - 280))
    UI.button("Refresh", buttons.refresh)
    if not self.collapsed then
        local split = self.x + self:treeWidth()
        local top, contentHeight = self.y + HEADER, math.max(0, self.height - HEADER - 28)
        love.graphics.setColor(0.28, 0.30, 0.35, 1)
        love.graphics.line(split, top, split, self.y + self.height)
        local status = self.error or self.selectedReference or "Double-click a folder or level. Click the path to go to a parent."
        UI.text(status, self.x + 12, self.y + self.height - 21, self.width - 24,
            self.error and {1, 0.55, 0.5, 1} or nil)
    end
    Canvas.draw(self)
    if self.uiRoot == self.localRoot and self.localRoot.popup then
        love.graphics.push("all")
        love.graphics.setScissor()
        self.localRoot.popup:draw()
        love.graphics.pop()
    end
    love.graphics.pop()
end

function AssetBrowser:mousepressed(x, y, button, presses)
    if button ~= 1 or not self:containsPoint(x, y) then return end
    self.uiRoot:dispatchTo(self:hitTest(x, y), "mousepressed", x, y, button, presses)
    self:setBounds(self.x, self.y, self.width, self.height)
end

function AssetBrowser:handleContentMousepressed(x, y, button, presses)
    if button ~= 1 then return end
    if self.collapsed or y < self.y + HEADER or y >= self.y + self.height - 28 then return end
    local index = math.floor((y - self.y - HEADER) / ROW) + 1
    if x < self.x + self:treeWidth() then
        local node = self.tree[index + self.treeScroll]
        if not node then return end
        if x < self.x + 28 + node.depth * 14 then
            self.expanded[node.reference] = not self.expanded[node.reference]
            self:rebuildTree()
        else self:openFolder(node.reference) end
    else
        local entry = self:getEntryAtPosition(x, y)
        self.selectedReference = entry and entry.reference or nil
        if entry and entry.type == "directory" and not entry.isLink and (presses or 1) >= 2 then
            self:openFolder(entry.reference)
        elseif entry and entry.type == "file" and not entry.isLink and (presses or 1) >= 2 and self.onOpenFile then
            local opened, err = self.onOpenFile(entry.reference)
            if opened == false then self.error = err end
        end
    end
end

function AssetBrowser:drawTree()
    local view = self.treeSlot.widget
    if view.height <= 0 then return end
    love.graphics.push("all")
    love.graphics.intersectScissor(view.x, view.y, view.width, view.height)
    for i, node in ipairs(self.tree) do
        local rowY = view.y + (i - 1 - self.treeScroll) * ROW
        if rowY + ROW > view.y and rowY < view.y + view.height then
            if node.reference == self.folder then
                love.graphics.setColor(0.18, 0.27, 0.38, 1)
                love.graphics.rectangle("fill", view.x, rowY, view.width, ROW)
            end
            local arrowX, arrowY = view.x + 10 + node.depth * 14, rowY + ROW / 2
            love.graphics.setColor(0.8, 0.84, 0.9, 1)
            love.graphics.setLineWidth(1.5)
            if self.expanded[node.reference] then
                love.graphics.line(arrowX, arrowY - 2, arrowX + 4, arrowY + 2, arrowX + 8, arrowY - 2)
            else
                love.graphics.line(arrowX + 2, arrowY - 4, arrowX + 6, arrowY, arrowX + 2, arrowY + 4)
            end
            UI.text(node.name, view.x + 26 + node.depth * 14, rowY + 5, view.width - 36 - node.depth * 14)
        end
    end
    love.graphics.pop()
end

function AssetBrowser:drawIcon(entry, x, y)
    if entry.type == "directory" and not entry.isLink then
        love.graphics.setColor(0.76, 0.57, 0.25, 1)
        love.graphics.rectangle("fill", x + 13, y + 19, 28, 13, 3, 3)
        love.graphics.setColor(0.90, 0.72, 0.34, 1)
        love.graphics.rectangle("fill", x + 13, y + 29, 62, 42, 4, 4)
    else
        love.graphics.push("all")
        love.graphics.setColor(0.24, 0.35, 0.55, 1)
        love.graphics.rectangle("fill", x + 12, y + 12, 64, 64, 6, 6)
        love.graphics.setColor(0.45, 0.61, 0.82, 1)
        love.graphics.rectangle("line", x + 12.5, y + 12.5, 63, 63, 6, 6)
        self.fileIconFont = self.fileIconFont or love.graphics.newFont(26)
        local extension = (entry.name:match("%.([^%.]+)$") or "File"):lower()
        local label = entry.isLink and "Link" or extension == "level" and "Lv"
            or extension == "lua" and "Lua" or extension == "file" and "File" or extension:upper()
        love.graphics.setFont(self.fileIconFont)
        love.graphics.setColor(0.94, 0.97, 1, 1)
        local font = self.fileIconFont
        if font:getWidth(label) > 52 then
            self.smallFileIconFont = self.smallFileIconFont or love.graphics.newFont(16)
            font = self.smallFileIconFont
            love.graphics.setFont(font)
        end
        UI.text(label, x + 44 - math.min(font:getWidth(label), 52) / 2,
            y + 44 - font:getHeight() / 2, 52, { 0.94, 0.97, 1, 1 })
        love.graphics.pop()
    end
end

function AssetBrowser:drawFiles()
    local view = self.fileSlot.widget
    if view.height <= 0 then return end
    love.graphics.push("all")
    love.graphics.intersectScissor(view.x, view.y, view.width, view.height)
    self.thumbnails:beginFrame()
    local columns = self:columns()
    local first, last
    if self.viewMode == "list" then
        first = self.fileScroll + 1
        last = math.min(#self.entries, first + math.ceil(view.height / ROW))
    else
        first = self.fileScroll * columns + 1
        last = math.min(#self.entries, first + (math.ceil(view.height / CARD_HEIGHT) + 1) * columns - 1)
    end
    for i = first, last do
        local entry = self.entries[i]
        if self.viewMode == "list" then
            local rowY = view.y + (i - 1 - self.fileScroll) * ROW
            if rowY + ROW > view.y and rowY < view.y + view.height then
                if entry.reference == self.selectedReference then
                    love.graphics.setColor(0.18, 0.27, 0.38, 1)
                    love.graphics.rectangle("fill", view.x, rowY, view.width, ROW)
                end
                local kind = entry.isLink and "[Link] " or entry.type == "directory" and "[Folder] " or "[File] "
                UI.text(kind .. entry.name, view.x + 12, rowY + 5, view.width - 24)
            end
        else
            local column, row = (i - 1) % columns, math.floor((i - 1) / columns) - self.fileScroll
            local x, y = view.x + 8 + column * CARD_WIDTH, view.y + 8 + row * CARD_HEIGHT
            if y + CARD_HEIGHT > view.y and y < view.y + view.height then
                love.graphics.setColor(entry.reference == self.selectedReference and 0.18 or 0.13,
                    entry.reference == self.selectedReference and 0.30 or 0.15,
                    entry.reference == self.selectedReference and 0.44 or 0.19, 1)
                love.graphics.rectangle("fill", x, y, CARD_WIDTH - 6, CARD_HEIGHT - 6, 4, 4)
                love.graphics.setColor(0.075, 0.085, 0.105, 1)
                love.graphics.rectangle("fill", x + 9, y + 6, 88, 88)
                local thumbnail = self.thumbnails:get(entry)
                if thumbnail then
                    love.graphics.setColor(1, 1, 1, 1)
                    love.graphics.draw(thumbnail, x + 9, y + 6)
                else self:drawIcon(entry, x + 9, y + 6) end
                UI.text(entry.name, x + 7, y + 98, CARD_WIDTH - 20)
            end
        end
    end
    if #self.entries == 0 then UI.text("This folder is empty", view.x + 12, view.y + 8) end
    love.graphics.pop()
end

function AssetBrowser:wheelmoved(x, y, amount)
    if self.collapsed then return end
    if x < self.x + self:treeWidth() then self.treeScroll = self.treeScroll - amount * 3
    else self.fileScroll = self.fileScroll - amount * (self.viewMode == "list" and 3 or 1) end
    self:clampScroll()
end

return AssetBrowser
