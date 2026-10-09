local Theme = require("editor.Theme")
local Project = require("editor.Project")
local FileSystem = require("editor.HostFileSystem")
local Ui = require("editor.Ui")
local FolderDialog = require("editor.FolderDialog")
local Ime = require("editor.ui.Ime")
local Edit = require("editor.ui.TextEdit")

local ProjectStart = {}
ProjectStart.__index = ProjectStart

local function rect(x, y, w, h) return { x = x, y = y, w = w, h = h } end

function ProjectStart.new(onOpen, selectFolder)
    local self = setmetatable({
        onOpen = onOpen, mode = "create", name = "New Project",
        path = "", activeField = "name",
        replace = true, error = nil, selectFolder = selectFolder or FolderDialog.selectFolder
    }, ProjectStart)
    self:setPath(love.filesystem.getUserDirectory())
    return self
end

function ProjectStart:setPath(path)
    local previous = self.path
    -- 입력 출처와 OS에 관계없이 시작 화면의 경로 표기는 '/'로 통일한다.
    self.path = path:gsub("\\", "/")
    if self.editState and self.editState.text == previous then self.editState.text = self.path end
end

function ProjectStart:layout()
    local w, h = love.graphics.getDimensions()
    local left, top = math.max(16, (w - 680) / 2), math.max(16, (h - 460) / 2)
    local width = math.min(680, w - 32)
    local createWidth = Ui.buttonWidth("New project")
    local browseWidth = Ui.buttonWidth("Browse")
    local form = {
        panel = rect(left, top, width, 460),
        create = rect(left + 24, top + 80, createWidth, 36),
        open = rect(left + 24 + createWidth + Ui.METRICS.buttonGap, top + 80, Ui.buttonWidth("Open project"), 36),
        name = rect(left + 24, top + 158, width - 48, 38),
        path = rect(left + 24, top + 234, width - 48 - browseWidth - Ui.METRICS.buttonGap, 38),
        browse = rect(left + width - 24 - browseWidth, top + 234, browseWidth, 38),
        submit = rect(left + 24, top + 352, Ui.buttonWidth(self.mode == "create" and "Create project" or "Open project"), 42)
    }
    return form
end

function ProjectStart:submit()
    self:finishComposition()
    self:setPath(self.path)
    -- 경로/파일 오류는 프로젝트 시작 화면에 남겨, 실패 시 반쯤 열린 에디터를 만들지 않는다.
    local ok, project, err = pcall(function()
        if self.mode == "create" then return Project.create(self.path, self.name) end
        return Project.open(self.path)
    end)
    if not ok then self.error = tostring(project); return false, self.error end
    if not project then self.error = err; return false, err end
    local called, opened, openError = pcall(self.onOpen, project)
    if not called then self.error = tostring(opened); return false, self.error end
    if opened == false then self.error = openError; return false, openError end
    self.error = nil
    return true
end

function ProjectStart:browse()
    self:finishComposition()
    local title = self.mode == "create" and "새 프로젝트의 부모 폴더 선택" or "프로젝트 폴더 열기"
    local ok, path, err = pcall(self.selectFolder, self.path, title)
    if not ok then self.error = tostring(path); return end
    if err then self.error = err; return end
    if path then self:setPath(path); self.error = nil end
    self.activeField, self.replace = "path", true
    Edit.begin(self, self.path, true)
end

function ProjectStart:draw()
    local layout = self:layout()
    local p = layout.panel
    love.graphics.push("all")
    Theme.clear("background")
    Theme.setColor("panel")
    love.graphics.rectangle("fill", p.x, p.y, p.w, p.h, 8, 8)
    Ui.text("LOVE Labo", p.x + 24, p.y + 22)
    Ui.text("Create or open a project to start editing.", p.x + 24, p.y + 48)
    Ui.button("New project", layout.create, self.mode == "create")
    Ui.button("Open project", layout.open, self.mode == "open")
    if self.mode == "create" then
        Ui.text("Project name", p.x + 24, p.y + 136)
        Ui.field(self.activeField == "name" and Ime.display(self, self.name, self.replace) or self.name,
            layout.name, self.activeField == "name", self.activeField == "name" and self.composition, self)
    else
        Ui.text("Select a folder containing " .. Project.FILE_NAME .. ".", p.x + 24, p.y + 158, p.w - 48)
    end
    Ui.text(self.mode == "create" and "Parent folder" or "Project folder", p.x + 24, p.y + 212)
    Ui.field(self.activeField == "path" and Ime.display(self, self.path, self.replace) or self.path,
        layout.path, self.activeField == "path", self.activeField == "path" and self.composition, self)
    Ui.button("Browse", layout.browse)
    if self.mode == "create" then
        Ui.text("Create: " .. FileSystem.join(self.path, self.name), p.x + 24, p.y + 290, p.w - 48)
    end
    if self.error then Ui.text(self.error, p.x + 24, p.y + 316, p.w - 48, Theme.color("error")) end
    Ui.button(self.mode == "create" and "Create project" or "Open project", layout.submit, true)
    Ui.text("Tab: next field    Enter: confirm    Ctrl+V: paste path", p.x + 24, p.y + 412, p.w - 48)
    love.graphics.pop()
end

function ProjectStart:mousepressed(x, y, button)
    if button ~= 1 then return end
    local r = self:layout()
    local sameField = self.activeField and Ui.contains(x, y, r[self.activeField])
    if sameField then
        self:finishComposition()
        Edit.press(self, self[self.activeField], r[self.activeField], x, false)
        self.replace = false
        return
    end
    self:finishComposition()
    if Ui.contains(x, y, r.create) then self.mode = "create"; self.activeField = "name"; self.error = nil
    elseif Ui.contains(x, y, r.open) then self.mode = "open"; self.activeField = "path"; self.error = nil
    elseif self.mode == "create" and Ui.contains(x, y, r.name) then self.activeField = "name"
    elseif Ui.contains(x, y, r.path) then self.activeField = "path"
    elseif Ui.contains(x, y, r.browse) then
        self:browse()
    elseif Ui.contains(x, y, r.submit) then self:submit()
    else self.activeField = nil end
    self.replace = true
    if self.activeField then
        Edit.begin(self, self[self.activeField], true)
        if Ui.contains(x, y, r[self.activeField]) then Edit.press(self, self[self.activeField], r[self.activeField], x, true) end
    end
end

function ProjectStart:mousemoved(x) return Edit.move(self, x) end
function ProjectStart:mousereleased() Edit.release(self) end

function ProjectStart:textinput(text)
    if Ime.consume(text) then return end
    if not self.activeField then return end
    self[self.activeField], self.replace = Ime.input(self, self[self.activeField], text, self.replace)
    if self.activeField == "path" then self:setPath(self.path) end
    self.replace = false
end

function ProjectStart:textedited(text)
    if self.activeField then Ime.edited(self, text) end
end

function ProjectStart:finishComposition()
    if not self.activeField then return end
    self[self.activeField], self.replace = Ime.finish(self, self[self.activeField], self.replace)
    if self.activeField == "path" then self:setPath(self.path) end
end

function ProjectStart:keypressed(key)
    if Ime.handlesKey(self, key) then return end
    if key == "escape" then Ime.cancel(self); return end
    if Ime.endsComposition(key) then self:finishComposition() end
    if key == "return" or key == "kpenter" then
        self:submit()
        return
    end
    if key == "tab" then
        self:finishComposition()
        self.activeField = self.mode == "create" and self.activeField == "path" and "name" or "path"
        self.replace = true
        Edit.begin(self, self[self.activeField], true)
        return
    end
    if self.activeField then
        self[self.activeField], self.replace = Ui.editKey(self[self.activeField], key, self.replace, self)
        if self.activeField == "path" then self:setPath(self.path) end
    end
end

return ProjectStart
