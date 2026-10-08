local UI = require("editor.ui")

local AssetBrowser = {}
AssetBrowser.__index = AssetBrowser
local HEADER = 38
local ROW = 26

function AssetBrowser.new(project)
    local self = setmetatable({
        project = project, folder = "Assets", entries = {}, selectedReference = nil,
        expanded = { Assets = true }, children = {}, tree = {},
        treeScroll = 0, fileScroll = 0, collapsed = false,
        x = 0, y = 0, width = 0, height = 0, error = nil
    }, AssetBrowser)
    self:refresh()
    return self
end

function AssetBrowser:setBounds(x, y, width, height)
    self.x, self.y, self.width, self.height = x, y, width, height
    self:clampScroll()
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
            local entries, err = self.project:listAssets(reference)
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
    self:clampScroll()
end

function AssetBrowser:openFolder(reference)
    local entries, err = self.project:listAssets(reference)
    if not entries then self.error = err; return false, err end
    self.folder, self.entries, self.error = reference, entries, nil
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
    self.children = {}
    local selected = self.selectedReference
    local opened, err = self:openFolder(self.folder)
    if not opened then
        self.entries = {}
        if self.folder ~= "Assets" then self:openFolder("Assets") end
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
    if self.folder == "Assets" then return false end
    return self:openFolder(self.folder:match("^(.*)/[^/]+$"))
end

function AssetBrowser:clampScroll()
    local visible = math.max(1, math.floor((self.height - HEADER - 28) / ROW))
    self.treeScroll = math.floor(math.max(0, math.min(self.treeScroll, math.max(0, #self.tree - visible))))
    self.fileScroll = math.floor(math.max(0, math.min(self.fileScroll, math.max(0, #self.entries - visible))))
end

function AssetBrowser:buttons()
    local function button(x, w) return { x = x, y = self.y + 8, w = w, h = 26 } end
    return {
        fold = button(self.x + 8, 32),
        up = button(self.x + self.width - 154, 52),
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
    UI.text("Asset Browser  /  " .. self.folder, self.x + 50, self.y + 14, math.max(0, self.width - 216))
    UI.button("Up", buttons.up)
    UI.button("Refresh", buttons.refresh)
    if not self.collapsed then
        local split = self.x + self:treeWidth()
        local top, contentHeight = self.y + HEADER, math.max(0, self.height - HEADER - 28)
        love.graphics.setColor(0.28, 0.30, 0.35, 1)
        love.graphics.line(split, top, split, self.y + self.height)
        love.graphics.setScissor(self.x, top, self:treeWidth(), contentHeight)
        for i, node in ipairs(self.tree) do
            local rowY = top + (i - 1 - self.treeScroll) * ROW
            if rowY + ROW > top and rowY < top + contentHeight then
                if node.reference == self.folder then
                    love.graphics.setColor(0.18, 0.27, 0.38, 1)
                    love.graphics.rectangle("fill", self.x, rowY, self:treeWidth(), ROW)
                end
                UI.text((self.expanded[node.reference] and "- " or "+ ") .. node.name,
                    self.x + 10 + node.depth * 14, rowY + 5, self:treeWidth() - 20 - node.depth * 14)
            end
        end
        love.graphics.setScissor(split, top, self.width - self:treeWidth(), contentHeight)
        for i, entry in ipairs(self.entries) do
            local rowY = top + (i - 1 - self.fileScroll) * ROW
            if rowY + ROW > top and rowY < top + contentHeight then
                if entry.reference == self.selectedReference then
                    love.graphics.setColor(0.18, 0.27, 0.38, 1)
                    love.graphics.rectangle("fill", split, rowY, self.width - self:treeWidth(), ROW)
                end
                local kind = entry.isLink and "[Link] " or entry.type == "directory" and "[Folder] " or "[File] "
                UI.text(kind .. entry.name, split + 12, rowY + 5, self.width - self:treeWidth() - 24)
            end
        end
        if #self.entries == 0 then UI.text("This folder is empty", split + 12, top + 8) end
        love.graphics.setScissor(self.x, self.y, self.width, self.height)
        local status = self.error or self.selectedReference or "Double-click a folder to open it. Files are listed without importing."
        UI.text(status, self.x + 12, self.y + self.height - 21, self.width - 24,
            self.error and {1, 0.55, 0.5, 1} or nil)
    end
    love.graphics.pop()
end

function AssetBrowser:mousepressed(x, y, button, presses)
    if button ~= 1 or not self:containsPoint(x, y) then return end
    local buttons = self:buttons()
    if UI.contains(x, y, buttons.fold) then self.collapsed = not self.collapsed; return end
    if UI.contains(x, y, buttons.up) then self:goUp(); return end
    if UI.contains(x, y, buttons.refresh) then self:refresh(); return end
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
        local entry = self.entries[index + self.fileScroll]
        self.selectedReference = entry and entry.reference or nil
        if entry and entry.type == "directory" and not entry.isLink and (presses or 1) >= 2 then
            self:openFolder(entry.reference)
        end
    end
end

function AssetBrowser:wheelmoved(x, y, amount)
    if self.collapsed then return end
    if x < self.x + self:treeWidth() then self.treeScroll = self.treeScroll - amount * 3
    else self.fileScroll = self.fileScroll - amount * 3 end
    self:clampScroll()
end

return AssetBrowser
