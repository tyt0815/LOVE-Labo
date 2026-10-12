local Widget = require("editor.ui.Widget")
local Ui = require("editor.Ui")
local Theme = require("editor.Theme")
local Repair = require("editor.AssetRepair")
local Dialog = setmetatable({}, {__index = Widget})
Dialog.__index = Dialog
function Dialog.new(app, focus)
    local self = setmetatable(Widget.new(), Dialog)
    self.app, self.plan, self.scroll = app, Repair.plan(app.project), 0
    local w, h = love.graphics.getDimensions(); self:setBounds(0, 0, w, h)
    self.box = {x = math.max(8, (w - 760) / 2), y = 40, w = math.min(760, w - 16), h = math.max(260, h - 80)}
    local b = self.box
    self.list = {x = b.x + 16, y = b.y + 72, w = b.w - 32, h = b.h - 180}
    self.apply = {x = b.x + b.w - 174, y = b.y + b.h - 42, w = 74, h = 28}
    self.cancel = {x = b.x + b.w - 90, y = self.apply.y, w = 74, h = 28}
    self.scrollbar = require("editor.ui.Scrollbar").new(function() return self.scroll end, function(value) self.scroll = value end)
    for _, row in ipairs(self.plan.rows) do
        row.expanded = row.id == focus
        row.tree = require("editor.ui.AssetPickerTree").new(row.candidates, row.target, function(target)
            row.target, row.checked, row.delete = target, true, false
        end)
    end
    self:layout(); app.uiRoot:setPopup(self); return self
end
function Dialog:layout()
    local offset = 0
    for _, row in ipairs(self.plan.rows) do
        row.offset, row.height = offset, 54 + (row.expanded and 132 or 0); offset = offset + row.height
    end
    self.scroll = math.max(0, math.min(self.scroll, math.max(0, offset - self.list.h)))
    self.scrollbar:layout({x = self.list.x + self.list.w - 12, y = self.list.y, w = 12, h = self.list.h}, offset, self.list.h)
    for _, row in ipairs(self.plan.rows) do
        row.rect = {x = self.list.x, y = self.list.y + row.offset - self.scroll, w = self.list.w - 16, h = 54}
        row.tree:setBounds(self.list.x + 28, row.rect.y + 54, self.list.w - 48, 132)
    end
end
function Dialog:submit()
    local changes = {}
    for _, row in ipairs(self.plan.rows) do if row.checked then changes[#changes + 1] = {id = row.id, target = row.target, delete = row.delete} end end
    local ok, err = Repair.apply(self.app.project, {revision = self.plan.revision, changes = changes,
        protectedIds = {self.app.documentAssetId}}, self.app.level)
    if not ok then self.error = err; return false end
    self.app.uiRoot:dismissPopup(); self.app:refreshProject(false); return true
end
function Dialog:hitTest() return self end
function Dialog:dispatch(event, ...)
    local handled, capture = self.scrollbar:dispatch(event, ...); if handled then self:layout(); return true, capture end
    if self.capturedTree and (event == "mousemoved" or event == "mousereleased" or event == "cancel") then
        self.capturedTree:dispatch(event, ...); if event ~= "mousemoved" then self.capturedTree = nil end; return true
    end
    if event == "keypressed" and (...) == "escape" then self.app.uiRoot:dismissPopup()
    elseif event == "mousepressed" then
        local x, y, button = ...; if button ~= 1 then return true end
        if Ui.contains(x, y, self.cancel) then self.app.uiRoot:dismissPopup()
        elseif Ui.contains(x, y, self.apply) then self:submit()
        elseif Ui.contains(x, y, self.list) then
            for _, row in ipairs(self.plan.rows) do
                if Ui.contains(x, y, row.rect) then
                    if row.readOnly then self.error = "Restore Labo plugin files from the editor installation"
                    elseif x < row.rect.x + 28 then row.checked = not row.checked
                    elseif x > row.rect.x + row.rect.w - 28 then row.expanded = not row.expanded; self:layout()
                    elseif x > row.rect.x + row.rect.w - 96 then row.delete, row.checked = not row.delete, true end
                    break
                elseif row.expanded and row.tree:containsPoint(x, y) then
                    local _, captured = row.tree:dispatch(event, ...); if captured then self.capturedTree = row.tree end; return true, captured
                end
            end
        end
    elseif event == "wheelmoved" then
        local x, y, amount = ...
        if Ui.contains(x, y, self.list) then
            for _, row in ipairs(self.plan.rows) do if row.expanded and row.tree:containsPoint(x, y) then
                local before = row.tree.scroll; row.tree:dispatch(event, ...); if before ~= row.tree.scroll then return true end
            end end
            self.scroll = self.scroll - amount * 44; self:layout()
        end
    end
    return true
end
function Dialog:draw()
    self:layout(); local b = self.box
    Theme.setColor("overlay"); love.graphics.rectangle("fill", 0, 0, self.width, self.height)
    Theme.setColor("surface"); love.graphics.rectangle("fill", b.x, b.y, b.w, b.h, 6, 6)
    Ui.text("Repair Asset References", b.x + 16, b.y + 16, b.w - 32)
    Ui.text("Review missing assets. Expand a row to select an untracked file.", b.x + 16, b.y + 44, b.w - 32)
    love.graphics.push("all"); love.graphics.intersectScissor(self.list.x, self.list.y, self.list.w, self.list.h)
    for _, row in ipairs(self.plan.rows) do
        local r = row.rect
        Ui.row(r, false)
        Ui.checkbox({x = r.x + 4, y = r.y + 8, w = 20, h = 20}, row.checked)
        Ui.text(row.reference, r.x + 30, r.y + 5, r.w - 140, Theme.color("error"))
        Ui.text(row.delete and "Remove registration" or row.target or row.confidence, r.x + 30, r.y + 28, r.w - 40)
        Ui.button(row.delete and "Undo" or "Delete", {x = r.x + r.w - 96, y = r.y + 4, w = 64, h = 28}, row.delete, "Remove missing registration; referenced assets are protected", true)
        Ui.chevron(r.x + r.w - 18, r.y + 20, row.expanded)
        if row.expanded then row.tree:draw() end
    end
    self.scrollbar:draw(); love.graphics.pop()
    if self.error then Ui.textLines(self.error, b.x + 16, self.list.y + self.list.h + 8, b.w - 32, 3, Theme.color("error")) end
    Ui.button("Apply", self.apply, false, "Apply checked repairs", true); Ui.button("Cancel", self.cancel, false, "Leave registrations unchanged", true)
end
return Dialog
