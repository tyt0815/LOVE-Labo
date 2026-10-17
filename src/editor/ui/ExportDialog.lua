local Theme = require("editor.Theme")
local Ui = require("editor.Ui")
local Widget = require("editor.ui.Widget")
local Ime = require("editor.ui.Ime")
local Edit = require("editor.ui.TextEdit")
local Fs = require("editor.HostFileSystem")
local Dialog = setmetatable({}, {__index = Widget})
Dialog.__index = Dialog

function Dialog.new(app)
    local self = setmetatable(Widget.new(), Dialog)
    self.app, self.root, self.active, self.platform = app, app.uiRoot, 1, "windows"
    local width, height = love.graphics.getDimensions()
    self:setBounds(0, 0, width, height)
    self.box = {x = math.max(0, (width - 540) / 2), y = math.max(0, (height - 310) / 2), w = 540, h = 310}
    local box = self.box
    self.fields = {
        {label = "Output folder", text = Fs.join(app.project.rootPath, "Build/Windows"), replace = true},
        {label = "Executable", text = "Game.exe", replace = true},
    }
    for index, field in ipairs(self.fields) do
        field.rect = {x = box.x + 144, y = box.y + 118 + (index - 1) * 48, w = box.w - 160, h = 32}
    end
    self.cancel = {x = box.x + box.w - 90, y = box.y + box.h - 46, w = 74, h = 30}
    self.confirm = {x = self.cancel.x - 84, y = self.cancel.y, w = 76, h = 30}
    self.root:setPopup(self)
    return self
end

function Dialog:finish()
    local field = self.fields[self.active]
    field.text, field.replace = Ime.finish(field, field.text, field.replace)
end

function Dialog:submit()
    self:finish()
    local folder, name = self.fields[1].text, self.fields[2].text
    local valid, err = require("editor.Project").isValidName(name)
    if folder == "" then self.error = "Specify an output folder"; return false end
    if not valid or name:find("/", 1, true) or name:find("\\", 1, true) or not name:lower():match("%.exe$") then
        self.error = err or "Executable must be an .exe filename"; return false
    end
    local ok, result, report = require("editor.ProjectBuild").run(self.app.project, self.app.level, Fs.join(folder, name), {platform = self.platform})
    self.app.lastBuildReport = report
    self.app:showBuildResults(report)
    return ok, result
end

function Dialog:hitTest() return self end
function Dialog:dispatch(event, ...)
    local field = self.fields[self.active]
    if event == "cancel" or event == "dismiss" then
        for _, item in ipairs(self.fields) do Ime.cancel(item); Edit.release(item) end
    elseif event == "textedited" then Ime.edited(field, (...))
    elseif event == "textinput" then
        field.text, field.replace = Ime.input(field, field.text, (...), field.replace); self.error = nil
    elseif event == "keypressed" then
        local key = ...
        if Ime.handlesKey(field, key) then return true end
        if Ime.endsComposition(key) then self:finish() end
        if key == "return" or key == "kpenter" then self:submit()
        elseif key == "escape" then self.root:dismissPopup()
        elseif key == "tab" then self.active = self.active % #self.fields + 1
        else field.text, field.replace = Ui.editKey(field.text, key, field.replace, field) end
    elseif event == "mousepressed" then
        local x, y, button = ...
        if button == 1 then
            self:finish()
            if Ui.contains(x, y, self.cancel) then self.root:dismissPopup()
            elseif Ui.contains(x, y, self.confirm) then self:submit()
            else
                for index, item in ipairs(self.fields) do
                    if Ui.contains(x, y, item.rect) then
                        self.active, item.replace = index, false
                        Edit.press(item, item.text, item.rect, x, false)
                        break
                    end
                end
            end
        end
    elseif event == "mousemoved" then Edit.move(field, (...))
    elseif event == "mousereleased" then Edit.release(field) end
    return true
end

function Dialog:draw()
    local box = self.box
    Theme.setColor("overlay"); love.graphics.rectangle("fill", 0, 0, love.graphics.getDimensions())
    Theme.setColor("surface"); love.graphics.rectangle("fill", box.x, box.y, box.w, box.h, 6, 6)
    Ui.text("Export Game", box.x + 16, box.y + 16, box.w - 32)
    Ui.text("Run Tools/Build.lua", box.x + 16, box.y + 46, box.w - 32)
    Ui.label("Platform", box.x + 16, box.y + 82, 120)
    Ui.text("Windows", box.x + 144, box.y + 82, box.w - 160)
    for index, field in ipairs(self.fields) do
        Ui.label(field.label, box.x + 16, field.rect.y + 7, 120)
        Ui.field(Ime.display(field, field.text, field.replace), field.rect, index == self.active, field.composition, field)
    end
    if self.error then Ui.text(self.error, box.x + 16, box.y + 221, box.w - 32, Theme.color("error")) end
    Ui.button("Cancel", self.cancel); Ui.button("Export", self.confirm)
end
return Dialog
