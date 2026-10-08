local Theme = require("editor.theme")
local UI = require("editor.ui")
local Canvas = require("editor.ui.canvas")
local Widget = require("editor.ui.widget")
local Root = require("editor.ui.root")
local Dropdown = require("editor.ui.dropdown")
local Thumbnail = require("editor.asset_thumbnail")
local Breadcrumb = require("editor.ui.breadcrumb")
local ContextMenu = require("editor.ui.context_menu")
local Dialog = require("editor.ui.dialog")

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
        mousepressed = function(_, ...) return self:handleContentMousepressed(...) end,
        mousemoved = function(_, x, y) return self:dragMoved(x, y) end,
        mousereleased = function(_, x, y, button) return self:dragReleased(x, y, button) end,
        cancel = function() self:cancelDrag(); return true end,
        drawOverlay = function() self:drawDragOverlay() end,
        wheelmoved = function(_, ...) self:wheelmoved(...); return true end
    }))
    self.fileSlot = self:addChild(Widget.new({
        draw = function() self:drawFiles() end,
        mousepressed = function(_, ...) return self:handleContentMousepressed(...) end,
        mousemoved = function(_, x, y) return self:dragMoved(x, y) end,
        mousereleased = function(_, x, y, button) return self:dragReleased(x, y, button) end,
        cancel = function() self:cancelDrag(); return true end,
        drawOverlay = function() self:drawDragOverlay() end,
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
        if key == "escape" then self:cancelDrag()
        elseif key == "backspace" then self:goUp()
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
    self.handlers.update = function(_, dt) self:updateDrag(dt) end
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
    if (x - split - 8) % CARD_WIDTH >= CARD_WIDTH - 6
        or (y - top - 8) % CARD_HEIGHT >= CARD_HEIGHT - 6 then return nil end
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
    if self.drag and self.drag.active then return false, "Finish or cancel the drag first" end
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

function AssetBrowser:refresh(keepPopup)
    self:cancelDrag()
    if not keepPopup then self.uiRoot:dismissPopup() end
    local rebuilt, rebuildError = self.project:rebuildAssetIndex()
    if not rebuilt then self.error = rebuildError; return false, rebuildError end
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
    if opened and self.project.assetIndexError then self.error = self.project.assetIndexError end
    if opened and not keepPopup and self.onRefresh then self.onRefresh() end
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
    Theme.setColor("panel")
    love.graphics.rectangle("fill", self.x, self.y, self.width, self.height)
    Theme.setColor("border")
    love.graphics.line(self.x, self.y, self.x + self.width, self.y)
    local buttons = self:buttons()
    UI.button(self.collapsed and "+" or "-", buttons.fold)
    UI.text("Project Browser", self.x + 50, self.y + 14, math.max(0, self.width - 280))
    UI.button("Refresh", buttons.refresh)
    if not self.collapsed then
        local split = self.x + self:treeWidth()
        local top, contentHeight = self.y + HEADER, math.max(0, self.height - HEADER - 28)
        Theme.setColor("border")
        love.graphics.line(split, top, split, self.y + self.height)
        local status = self.error or self.selectedReference or "Double-click a folder or level. Click the path to go to a parent."
        UI.text(status, self.x + 12, self.y + self.height - 21, self.width - 24,
            self.error and Theme.color("error") or nil)
    end
    Canvas.draw(self)
    if self.uiRoot == self.localRoot then self:drawDragOverlay() end
    if self.uiRoot == self.localRoot and self.localRoot.popup then
        love.graphics.push("all")
        love.graphics.setScissor()
        self.localRoot.popup:draw()
        love.graphics.pop()
    end
    love.graphics.pop()
end

function AssetBrowser:mousepressed(x, y, button, presses)
    if self.uiRoot == self.localRoot then
        self.localRoot:mousepressed(x, y, button, presses)
        self:setBounds(self.x, self.y, self.width, self.height)
        return
    end
    if not self:containsPoint(x, y) then return end
    self.uiRoot:dispatchTo(self:hitTest(x, y), "mousepressed", x, y, button, presses)
    self:setBounds(self.x, self.y, self.width, self.height)
end

function AssetBrowser:handleContentMousepressed(x, y, button, presses)
    if self.collapsed or y < self.y + HEADER or y >= self.y + self.height - 28 then return true end
    self:cancelDrag()
    if button == 2 then self:showContextMenu(x, y); return true end
    if button ~= 1 then return true end
    local index = math.floor((y - self.y - HEADER) / ROW) + 1
    if x < self.x + self:treeWidth() then
        local node = self.tree[index + self.treeScroll]
        if not node then return true end
        if x < self.x + 28 + node.depth * 14 then
            self.expanded[node.reference] = not self.expanded[node.reference]
            self:rebuildTree()
        elseif node.reference == "Assets" or node.reference == "Sources" then self:openFolder(node.reference)
        else
            -- 트리 탐색은 release까지 미뤄 이동 중에 현재 폴더가 바뀌지 않게 한다.
            self.drag = {entry = {reference = node.reference, name = node.name, type = "directory"},
                x = x, y = y, startX = x, startY = y, tree = true}
            return true, true
        end
    else
        local entry = self:getEntryAtPosition(x, y)
        if self.onSelect then
            local ok, err = self.onSelect(entry and entry.reference)
            if ok == false then self.error = err; return true end
        end
        self.selectedReference = entry and entry.reference or nil
        if entry and entry.type == "directory" and not entry.isLink and (presses or 1) >= 2 then
            self:openFolder(entry.reference)
        elseif entry and entry.type == "file" and not entry.isLink and (presses or 1) >= 2 and self.onOpenFile then
            local opened, err = self.onOpenFile(entry.reference)
            if opened == false then self.error = err end
        elseif entry and not entry.isLink and (presses or 1) == 1 then
            self.drag = {entry = entry, x = x, y = y, startX = x, startY = y}
            return true, true
        end
    end
    return true
end

function AssetBrowser:cancelDrag()
    self.drag = nil
    if self.uiRoot.captured == self.fileSlot.widget or self.uiRoot.captured == self.treeSlot.widget then
        self.uiRoot.captured, self.uiRoot.captureButton = nil, nil
    end
end

function AssetBrowser:dropTargetAt(x, y)
    local folder, rect, treeNode
    local tree = self.treeSlot.widget
    if tree:containsPoint(x, y) then
        local index = math.floor((y - tree.y) / ROW) + 1 + self.treeScroll
        treeNode = self.tree[index]
        if treeNode then
            folder = treeNode.reference
            rect = {x = tree.x, y = tree.y + (index - 1 - self.treeScroll) * ROW, w = tree.width, h = ROW}
        end
    elseif self.fileSlot.widget:containsPoint(x, y) then
        local entry = self:getEntryAtPosition(x, y)
        local view = self.fileSlot.widget
        if entry and entry.type == "directory" and not entry.isLink then
            folder = entry.reference
            for i, candidate in ipairs(self.entries) do
                if candidate == entry then
                    if self.viewMode == "list" then
                        rect = {x = view.x, y = view.y + (i - 1 - self.fileScroll) * ROW, w = view.width, h = ROW}
                    else
                        rect = {x = view.x + 8 + (i - 1) % self:columns() * CARD_WIDTH,
                            y = view.y + 8 + (math.floor((i - 1) / self:columns()) - self.fileScroll) * CARD_HEIGHT,
                            w = CARD_WIDTH - 6, h = CARD_HEIGHT - 6}
                    end
                    break
                end
            end
        elseif not entry then
            folder, rect = self.folder, {x = view.x, y = view.y, w = view.width, h = view.height}
        end
    end
    if not folder then return nil, nil, "Drop on a folder or empty file area" end
    local source = self.drag.entry.reference
    local destination = folder .. "/" .. self.drag.entry.name
    local errorText
    if source:match("^[^/]+") ~= folder:match("^[^/]+") then errorText = "Keep Assets and Sources separate"
    elseif destination:lower() == source:lower() then errorText = "Already in this folder"
    elseif self.drag.entry.type == "directory" and (folder:lower() == source:lower()
        or folder:lower():sub(1, #source + 1) == source:lower() .. "/") then errorText = "Cannot move into itself"
    else
        local parentPath, parentInfo = self.project:checkedEntry(folder)
        if not parentPath or parentInfo.type ~= "directory" then errorText = "Destination folder is unavailable"
        else
            local path = self.project:resolvePath(destination)
            local fs = require("editor.host_filesystem")
            for _, candidate in ipairs({path, path .. ".meta"}) do
                local info, err = fs.info(candidate)
                if info or err then errorText = err or "Destination already exists"; break end
            end
        end
    end
    return not errorText and destination or nil, rect, errorText, treeNode
end

function AssetBrowser:dragMoved(x, y)
    local drag = self.drag
    if not drag then return true end
    drag.x, drag.y = x, y
    if not drag.active and (x - drag.startX)^2 + (y - drag.startY)^2 >= 36 then drag.active = true end
    if drag.active then
        drag.destination, drag.rect, drag.error, drag.node = self:dropTargetAt(x, y)
        local hover = drag.node and drag.node.reference
        if drag.hover ~= hover then drag.hover, drag.hoverTime = hover, 0 end
    end
    return true
end

function AssetBrowser:dragReleased(x, y, button)
    if button ~= 1 or not self.drag then return true end
    local drag = self.drag
    local destination, _, err
    if drag.active then destination, _, err = self:dropTargetAt(x, y) end
    self:cancelDrag()
    if drag.active then
        if destination then
            local moved, moveError = self:moveEntry(drag.entry, destination)
            self.error = not moved and moveError or nil
        else self.error = err end
    elseif drag.tree then self:openFolder(drag.entry.reference) end
    return true
end

function AssetBrowser:updateDrag(dt)
    local drag = self.drag
    if not drag or not drag.active then return end
    if drag.destination and drag.hover and not self.expanded[drag.hover] then
        drag.hoverTime = (drag.hoverTime or 0) + dt
        if drag.hoverTime >= 0.6 then self.expanded[drag.hover] = true; self:rebuildTree() end
    end
    local view = self.treeSlot.widget:containsPoint(drag.x, drag.y) and self.treeSlot.widget
        or self.fileSlot.widget:containsPoint(drag.x, drag.y) and self.fileSlot.widget
    if view then
        local direction = drag.y < view.y + 18 and -1 or drag.y > view.y + view.height - 18 and 1 or 0
        drag.scrollTime = (drag.scrollTime or 0) + dt
        if direction ~= 0 and drag.scrollTime >= 0.15 then
            self:wheelmoved(drag.x, drag.y, -direction)
            drag.scrollTime = 0
        end
    end
    self:dragMoved(drag.x, drag.y)
end

function AssetBrowser:drawDragOverlay()
    local drag = self.drag
    if not drag or not drag.active then return end
    love.graphics.push("all")
    love.graphics.setScissor()
    if drag.rect then
        Theme.setColor(drag.destination and "focus" or "error")
        love.graphics.setLineWidth(2)
        love.graphics.rectangle("line", drag.rect.x + 1, drag.rect.y + 1, math.max(0, drag.rect.w - 2), math.max(0, drag.rect.h - 2))
    end
    local width = 260
    local x = math.max(0, math.min(drag.x + 16, love.graphics.getWidth() - width))
    local y = math.max(0, math.min(drag.y + 18, love.graphics.getHeight() - 54))
    Theme.setColor("surface")
    love.graphics.rectangle("fill", x, y, width, 54, 4, 4)
    Theme.setColor("border")
    love.graphics.rectangle("line", x, y, width, 54, 4, 4)
    UI.label(drag.entry.name, x + 8, y + 7, width - 16)
    UI.text(drag.error or "Move to " .. (drag.destination or ""), x + 8, y + 29, width - 16,
        Theme.color(drag.destination and "textMuted" or "error"))
    love.graphics.pop()
end

function AssetBrowser:showContextMenu(x, y)
    local entry, folder = nil, self.folder
    if x < self.x + self:treeWidth() then
        local index = math.floor((y - self.y - HEADER) / ROW) + 1 + self.treeScroll
        local node = self.tree[index]
        if node then
            entry = { reference = node.reference, name = node.name, type = "directory" }
            folder = node.reference
        end
    else
        entry = self:getEntryAtPosition(x, y)
        self.selectedReference = entry and entry.reference or nil
    end
    local newItems = {}
    for _, option in ipairs({ {"Folder", "folder"}, {"Level", "level"}, {"Prefab", "prefab"}, {"Lua Class", "lua"} }) do
        local label, kind = option[1], option[2]
        local root = folder:match("^[^/]+")
        if kind == "folder" or (kind == "level" or kind == "prefab") and root == "Assets" or kind == "lua" and root == "Sources" then
            newItems[#newItems + 1] = { label = label,
                action = function() self:showCreateDialog(folder, kind) end }
        end
    end
    local items = { { label = "New", children = newItems } }
    if entry and entry.reference ~= "Assets" and entry.reference ~= "Sources" then
        items[#items + 1] = { label = "Move", enabled = not entry.isLink,
            action = function() self:showMoveDialog(entry) end }
        items[#items + 1] = { label = "Rename", enabled = not entry.isLink,
            action = function() self:showRenameDialog(entry) end }
        items[#items + 1] = { label = "Delete", enabled = not entry.isLink,
            action = function() self:showDeleteDialog(entry) end }
    end
    ContextMenu.new(self.uiRoot):show(x, y, items)
end

function AssetBrowser:showMoveDialog(entry)
    local folder = entry.reference:match("^(.*)/[^/]+$")
    local name = entry.reference:match("[^/]+$")
    local dialog
    local tree = require("editor.ui.folder_tree").new(self.project, entry.reference:match("^[^/]+"),
        entry.type == "directory" and entry.reference or nil, folder, function(selected)
            dialog.text, dialog.replace, dialog.error = selected, true, nil
        end)
    dialog = Dialog.new(self.uiRoot, {title = "Move", message = entry.reference,
        input = true, value = folder, content = tree, confirmLabel = "Move", onConfirm = function(destination)
            destination = destination:gsub("\\", "/"):gsub("/+$", "")
            return self:moveEntry(entry, destination .. "/" .. name)
        end})
    dialog.error = tree.error
end

function AssetBrowser:showRenameDialog(entry)
    local folder, name = entry.reference:match("^(.*)/([^/]+)$")
    local extension = entry.type == "file" and (name:match("%.[^%.]+$") or "") or ""
    local stem = extension ~= "" and name:sub(1, -#extension - 1) or name
    Dialog.new(self.uiRoot, {title = "Rename", message = entry.reference, input = true,
        value = stem, confirmLabel = "Rename", onConfirm = function(newName)
            if extension ~= "" and newName:sub(-#extension):lower() == extension:lower() then
                newName = newName:sub(1, -#extension - 1)
            end
            local valid, err = self.project.isValidName(newName)
            if not valid then return false, err end
            return self:moveEntry(entry, folder .. "/" .. newName .. extension)
        end})
end

function AssetBrowser:moveEntry(entry, destination)
    if self.onBeforeMove then self.onBeforeMove() end
    local moved, err = self.project:moveEntry(entry.reference, destination)
    if not moved then return false, err end
    if self.onMove then self.onMove(entry.reference, destination) end
    if self.folder == entry.reference or self.folder:sub(1, #entry.reference + 1) == entry.reference .. "/" then
        self.folder = destination .. self.folder:sub(#entry.reference + 1)
    end
    self:refresh(true)
    self.selectedReference = destination
    return true
end

function AssetBrowser:showCreateDialog(folder, kind)
    local defaults = { folder = "NewFolder", level = "NewLevel", prefab = "NewPrefab", lua = "NewClass" }
    local choices, listError
    if kind == "lua" then
        choices = { {label = "Level Class", value = "level"}, {label = "LObject Class", value = "lobject"} }
    elseif kind == "level" or kind == "prefab" then
        choices = {{label = "None", value = false}}
        local scripts
        scripts, listError = self.project:listScripts(kind == "level" and "level" or "lobject")
        for _, reference in ipairs(scripts or {}) do choices[#choices + 1] = {label = reference, value = reference} end
    end
    local titles = {folder = "Folder", level = "Level", prefab = "Prefab", lua = "Lua Class"}
    local dialog = Dialog.new(self.uiRoot, { title = "New " .. titles[kind],
        message = folder, input = true, value = defaults[kind], choices = choices,
        choiceLabel = kind == "lua" and "Class type" or "Parent Class",
        onConfirm = function(name, choice)
            if listError then return false, listError end
            local options = kind == "lua" and {scriptKind = choice} or {scriptReference = choice or nil}
            local ok, reference = self.project:createEntry(folder, kind, name, options)
            if not ok then return false, reference end
            self:refresh(true)
            if self.folder ~= folder then self:openFolder(folder) end
            self.selectedReference = reference
            return true
        end })
    dialog.error = listError
end

function AssetBrowser:showDeleteDialog(entry)
    Dialog.new(self.uiRoot, { title = "Delete " .. (entry.type == "directory" and "Folder" or "File"),
        message = entry.reference,
        detail = "Permanently delete" .. (entry.type == "directory" and " this folder and all its contents?" or " this file?"),
        confirmLabel = "Delete", onConfirm = function()
            if self.canDelete then
                local allowed, err = self.canDelete(entry.reference)
                if not allowed then return false, err end
            end
            local ok, err = self.project:deleteEntry(entry.reference)
            -- 삭제 도중 파일 잠금 등으로 실패해도 실제 남은 항목을 다시 읽는다.
            self:refresh(true)
            if not ok then return false, err end
            return true
        end })
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
                Theme.setColor("selection")
                love.graphics.rectangle("fill", view.x, rowY, view.width, ROW)
            end
            local arrowX, arrowY = view.x + 10 + node.depth * 14, rowY + ROW / 2
            Theme.setColor("textMuted")
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
        Theme.setColor("folderTab")
        love.graphics.rectangle("fill", x + 13, y + 19, 28, 13, 3, 3)
        Theme.setColor("folderBody")
        love.graphics.rectangle("fill", x + 13, y + 29, 62, 42, 4, 4)
    else
        love.graphics.push("all")
        Theme.setColor("iconBackground")
        love.graphics.rectangle("fill", x + 12, y + 12, 64, 64, 6, 6)
        self.fileIconFont = self.fileIconFont or love.graphics.newFont(26)
        local label, color, badge = self:iconStyle(entry)
        Theme.setColor(color)
        love.graphics.rectangle("line", x + 12.5, y + 12.5, 63, 63, 6, 6)
        love.graphics.setFont(self.fileIconFont)
        local font = self.fileIconFont
        if font:getWidth(label) > 52 then
            self.smallFileIconFont = self.smallFileIconFont or love.graphics.newFont(16)
            font = self.smallFileIconFont
            love.graphics.setFont(font)
        end
        UI.text(label, x + 44 - math.min(font:getWidth(label), 52) / 2,
            y + (badge and 38 or 44) - font:getHeight() / 2, 52, Theme.color(color))
        if badge then
            self.badgeFont = self.badgeFont or love.graphics.newFont(11)
            love.graphics.setFont(self.badgeFont)
            UI.text(badge, x + 72 - self.badgeFont:getWidth(badge), y + 59, 40, Theme.color(color), true)
        end
        love.graphics.pop()
    end
end

function AssetBrowser:iconStyle(entry)
    if entry.isLink then return "Link", "iconText" end
    local extension = (entry.name:match("%.([^%.]+)$") or "file"):lower()
    if extension == "level" then return "Lv", "assetLevel" end
    if extension == "prefab" then return "Pf", "assetPrefab" end
    if extension == "lua" then
        local meta = self.project.assetMetadata and self.project.assetMetadata[entry.reference]
        local kind = meta and meta.scriptKind
        if kind == "level" then return "Lv", "classLevel", "Lua" end
        if kind == "lobject" then return "LO", "classLObject", "Lua" end
        if kind == "component" then return "Cp", "classComponent", "Lua" end
        return "?", "iconText", "Lua"
    end
    return extension == "file" and "File" or extension:upper(), "iconText"
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
                    Theme.setColor("selection")
                    love.graphics.rectangle("fill", view.x, rowY, view.width, ROW)
                end
                local kind = entry.isLink and "[Link] " or entry.type == "directory" and "[Folder] " or "[File] "
                UI.text(kind .. entry.name, view.x + 12, rowY + 5, view.width - 24)
            end
        else
            local column, row = (i - 1) % columns, math.floor((i - 1) / columns) - self.fileScroll
            local x, y = view.x + 8 + column * CARD_WIDTH, view.y + 8 + row * CARD_HEIGHT
            if y + CARD_HEIGHT > view.y and y < view.y + view.height then
                Theme.setColor(entry.reference == self.selectedReference and "selection" or "surface")
                love.graphics.rectangle("fill", x, y, CARD_WIDTH - 6, CARD_HEIGHT - 6, 4, 4)
                Theme.setColor("thumbnailBackground")
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
    if self.drag and self.drag.active then self:dragMoved(self.drag.x, self.drag.y) end
end

return AssetBrowser
