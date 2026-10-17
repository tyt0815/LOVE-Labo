local Widget = require("editor.ui.Widget")
local Ui = require("editor.Ui")
local Theme = require("editor.Theme")
local Json = require("project.Json")
local Panel = setmetatable({}, {__index = Widget})
Panel.__index = Panel
function Panel.new(app)
    local self = setmetatable(Widget.new(), Panel)
    self.app, self.panelName = app, "preview"
    self.handlers.mousepressed = function(_, x, y, button)
        if app:isPlaying() then return true end
        if button == 1 and Ui.contains(x, y, self:colorButton()) then
            app.inspector:commitEdit(); app:recordHistory()
            self:openBackgroundPicker()
        end
        return true
    end
    self.handlers.wheelmoved = function() return true end
    return self
end
function Panel:descriptor()
    if self.app:isPlaying() then return {} end
    if self.app.inspectorSource == "project" then return {} end
    local app = self.app
    if app.inspectorSource == "assets" then return {reference = app.inspectedAssetReference} end
    local object = app.sceneView.selectedLObject
    if object then return {data = app.level:toData(), instance = object.authoringId} end
    return {}
end
function Panel:openBackgroundPicker()
    return require("editor.ui.ColorPicker").new(self.app.uiRoot, {title = "Preview Background", anchor = self:colorButton(),
        entries = {{label = "Background", color = self:backgroundColor(), defaultColor = require("editor.Color").default(),
            useDefault = self:backgroundSetting() == nil}},
        onChange = function(color) self.backgroundPreview = color end,
        onDismiss = function() self.backgroundPreview = nil end,
        onConfirm = function(color, reset) return self:setBackground(color, reset) end})
end
function Panel:setBackground(value, reset)
    local color, err = require("editor.Preview").color(value)
    if not color then return false, err end
    local descriptor = self:descriptor()
    local doc = self.app.prefabDocument
    if descriptor.reference and doc and self.app.project:getAssetId(self.app.project:getAssetReference(descriptor.reference)) == doc.assetId then
        if self.app.project:isReadOnly(doc.assetId) then return false, "Labo plugin assets are read-only" end
        doc.data.previewBackground = not reset and color or nil
        self.app.project.draftRevision = (self.app.project.draftRevision or 0) + 1
        self.app:recordHistory()
    else self.background = not reset and color or nil end
    self.signature = nil
    return true
end
function Panel:colorButton() return {x = self.x + self.width - 120, y = self.y + 10, w = 104, h = 26} end
function Panel:backgroundSetting()
    local descriptor = self:descriptor()
    local reference = self.app.project and descriptor.reference and self.app.project:getAssetReference(descriptor.reference)
    local doc = self.app.prefabDocument
    if reference and reference:match("%.prefab$") then
        if doc and self.app.project:getAssetId(reference) == doc.assetId then
            return doc.data.previewBackground
        end
        return self.model and self.model.backgroundOverride
    end
    return self.background
end
function Panel:backgroundColor()
    return self.backgroundPreview or self:backgroundSetting() or require("editor.Color").default()
end
function Panel:draw()
    if self.width <= 0 or self.height <= 0 then return end
    Ui.panel(self.x, self.y, self.width, self.height)
    Ui.panelHeading("Preview", self.x, self.y, self.width)
    if self.app:isPlaying() then
        if self.model then self.model:release(); self.model = nil; self.signature = nil end
        Ui.text("Runtime instances are inspected in the viewport.\nStop discards runtime edits.", self.x + 16, self.y + 48, self.width - 32, Theme.color("textMuted"))
        return
    end
    Ui.button("Background", self:colorButton(), false, "Choose the preview background color.", true)
    local descriptor = self:descriptor()
    local project = self.app.project
    local signature = project and tostring(project.assetRevision or 0) .. ":" .. tostring(project.draftRevision or 0) .. ":" .. assert(Json.encode(descriptor))
    if signature ~= self.signature then
        if self.model then self.model:release(); self.model = nil end
        self.signature, self.error = signature, nil
        if project then
            local ok, model = pcall(require("editor.Preview").new, project, descriptor)
            if ok then self.model = model else self.error = tostring(model) end
        end
    end
    local rect = {x = self.x + 12, y = self.y + 44, w = math.max(0, self.width - 24), h = math.max(0, self.height - 56)}
    if rect.h <= 0 then return end
    local drawn, err
    if self.model then
        drawn, err = self.model:draw(rect, self:backgroundColor())
    end
    self.error = err or self.error
    if not drawn then Ui.text(self.error or "No visual preview", rect.x + 8, rect.y + 8, rect.w - 16, Theme.color(self.error and "error" or "textMuted")) end
end
return Panel
