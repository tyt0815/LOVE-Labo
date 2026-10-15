local Widget = require("editor.ui.Widget")
local Ui = require("editor.Ui")
local Theme = require("editor.Theme")
local Json = require("project.Json")
local Panel = setmetatable({}, {__index = Widget})
Panel.__index = Panel
function Panel.new(app)
    local self = setmetatable(Widget.new(), Panel)
    self.app, self.background, self.panelName = app, {255, 255, 255}, "preview"
    self.handlers.mousepressed = function(_, x, y, button)
        if button == 1 and Ui.contains(x, y, self:colorButton()) then
            app.inspector:commitEdit(); app:recordHistory()
            require("editor.ui.Dialog").new(app.uiRoot, {title = "Preview Background", message = "RGB values: 0–255",
                input = true, value = table.concat(self:backgroundColor(), ", "), confirmLabel = "Apply",
                onConfirm = function(text)
                    local channels = {}; for channel in text:gmatch("[^,%s]+") do channels[#channels + 1] = tonumber(channel) or false end
                    return self:setBackground(channels)
                end})
        end
        return true
    end
    self.handlers.wheelmoved = function() return true end
    return self
end
function Panel:descriptor()
    if self.app.inspector.tab == "Project" then return {} end
    local app = self.app
    if app.inspectorSource == "assets" then return {reference = app.inspectedAssetReference} end
    local object = app.sceneView.selectedLObject
    if object then return {data = app.level:toData(), instance = object.authoringId} end
    return {}
end
function Panel:setBackground(value)
    local color, err = require("editor.Preview").color(value)
    if not color then return false, err end
    local descriptor = self:descriptor()
    local doc = self.app.prefabDocument
    if descriptor.reference and doc and self.app.project:getAssetId(self.app.project:getAssetReference(descriptor.reference)) == doc.assetId then
        if self.app.project:isReadOnly(doc.assetId) then return false, "Labo plugin assets are read-only" end
        doc.data.previewBackground = color
        self.app.project.draftRevision = (self.app.project.draftRevision or 0) + 1
        self.app:recordHistory()
    else self.background = color end
    self.signature = nil
    return true
end
function Panel:colorButton() return {x = self.x + self.width - 70, y = self.y + 10, w = 54, h = 26} end
function Panel:backgroundColor()
    local descriptor = self:descriptor()
    local reference = self.app.project and descriptor.reference and self.app.project:getAssetReference(descriptor.reference)
    return reference and reference:match("%.prefab$") and self.model and self.model.background or self.background
end
function Panel:draw()
    if self.width <= 0 or self.height <= 0 then return end
    Ui.panel(self.x, self.y, self.width, self.height)
    Ui.panelHeading("Preview", self.x, self.y, self.width)
    Ui.button("RGB", self:colorButton(), false, "Change the preview background RGB values.", true)
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
