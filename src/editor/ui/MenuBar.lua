local Widget = require("editor.ui.Widget")
local Ui = require("editor.Ui")
local ContextMenu = require("editor.ui.ContextMenu")
local Bar = setmetatable({}, {__index = Widget})
Bar.__index = Bar
Bar.HEIGHT = 32
function Bar.new(app)
    local self = setmetatable(Widget.new(), Bar)
    self.app, self.focusable, self.menu = app, false, ContextMenu.new(app.uiRoot)
    self.menu.menuWidth = 280
    self.menu.hitTest = function(menu, x, y)
        if self:containsPoint(x, y) then return self end
        return ContextMenu.hitTest(menu, x, y)
    end
    self.handlers.draw = function() self:drawButtons() end
    self.handlers.mousepressed = function(_, x, y, button)
        if button == 1 then self:openAt(x, y) end
        return true
    end
    self.handlers.mousemoved = function(_, x, y)
        if app.uiRoot.popup == self.menu then self:openAt(x, y, true) end
        return true
    end
    return self
end
function Bar:buttons()
    return {{label = "File", name = "file", x = self.x + 8, y = self.y + 3, w = 58, h = 26},
        {label = "Run", name = "run", x = self.x + 70, y = self.y + 3, w = 58, h = 26}}
end
function Bar:items(name)
    local app = self.app
    local editable = not app:isPlaying()
    if name == "run" then return {
        {label = "Play", shortcut = "F5", enabled = editable, action = function() app:startPlay() end},
        {label = "Stop", shortcut = "F5", enabled = not editable, action = function() app:stopPlay() end}}
    end
    local project = app.project ~= nil
    local function create(folder, kind) app.assetBrowser:showCreateDialog(folder, kind) end
    return {
        {label = "New", enabled = project and editable, children = {
            {label = "Class...", action = function() create("Sources", "lua") end},
            {label = "Prefab...", action = function() create("Assets", "prefab") end},
            {label = "Level...", action = function() create("Assets", "level") end}}},
        {label = "Save", shortcut = "Ctrl+S", enabled = editable, action = function() app:saveInspectedDocument() end},
        {label = "Save Level As...", enabled = project and editable, action = function() app:showSaveLevelDialog() end},
        {label = "Export Game...", shortcut = "Ctrl+Shift+E", enabled = project and editable, action = function() app:showExportDialog() end}}
end
function Bar:openAt(x, y, hover)
    for _, button in ipairs(self:buttons()) do
        if Ui.contains(x, y, button) then
            if hover and self.active == button.name then return end
            if not hover and self.active == button.name and self.app.uiRoot.popup == self.menu then self.app.uiRoot:dismissPopup(); return end
            self.app.inspector:commitEdit()
            self.app:recordHistory()
            self.active = button.name
            self.menu:show(button.x, self.y + self.height, self:items(button.name))
            return
        end
    end
end
function Bar:drawButtons()
    for _, button in ipairs(self:buttons()) do
        Ui.button(button.label, button, self.app.uiRoot.popup == self.menu and self.active == button.name,
            button.name == "file" and "Create, save or export." or "Play / Stop. F5.", true)
    end
end
return Bar
