local Project = require("editor.project")
local FileSystem = require("editor.host_filesystem")
local UI = require("editor.ui")
local FolderDialog = require("editor.folder_dialog")

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
    -- 입력 출처와 OS에 관계없이 시작 화면의 경로 표기는 '/'로 통일한다.
    self.path = path:gsub("\\", "/")
end

function ProjectStart:layout()
    local w, h = love.graphics.getDimensions()
    local left, top = math.max(16, (w - 680) / 2), math.max(16, (h - 460) / 2)
    local width = math.min(680, w - 32)
    local form = {
        panel = rect(left, top, width, 460),
        create = rect(left + 24, top + 80, 150, 36),
        open = rect(left + 184, top + 80, 150, 36),
        name = rect(left + 24, top + 158, width - 48, 38),
        path = rect(left + 24, top + 234, width - 148, 38),
        browse = rect(left + width - 114, top + 234, 90, 38),
        submit = rect(left + 24, top + 352, width - 48, 42)
    }
    return form
end

function ProjectStart:submit()
    self:setPath(self.path)
    -- 경로/파일 오류는 프로젝트 시작 화면에 남겨, 실패 시 반쯤 열린 에디터를 만들지 않는다.
    local ok, project, err = pcall(function()
        if self.mode == "create" then return Project.create(self.path, self.name) end
        return Project.open(self.path)
    end)
    if not ok then self.error = tostring(project); return false, self.error end
    if not project then self.error = err; return false, err end
    local opened, openError = self.onOpen(project)
    if opened == false then self.error = openError; return false, openError end
    self.error = nil
    return true
end

function ProjectStart:browse()
    local title = self.mode == "create" and "새 프로젝트의 부모 폴더 선택" or "프로젝트 폴더 열기"
    local ok, path, err = pcall(self.selectFolder, self.path, title)
    if not ok then self.error = tostring(path); return end
    if err then self.error = err; return end
    if path then self:setPath(path); self.error = nil end
    self.activeField, self.replace = "path", true
end

function ProjectStart:draw()
    local layout = self:layout()
    local p = layout.panel
    love.graphics.push("all")
    love.graphics.clear(0.065, 0.075, 0.095, 1)
    love.graphics.setColor(0.105, 0.12, 0.15, 1)
    love.graphics.rectangle("fill", p.x, p.y, p.w, p.h, 8, 8)
    UI.text("LOVE Labo", p.x + 24, p.y + 22)
    UI.text("Create or open a project to start editing.", p.x + 24, p.y + 48)
    UI.button("New project", layout.create, self.mode == "create")
    UI.button("Open project", layout.open, self.mode == "open")
    if self.mode == "create" then
        UI.text("Project name", p.x + 24, p.y + 136)
        UI.field(self.name, layout.name, self.activeField == "name")
    else
        UI.text("Select a folder containing " .. Project.FILE_NAME .. ".", p.x + 24, p.y + 158, p.w - 48)
    end
    UI.text(self.mode == "create" and "Parent folder" or "Project folder", p.x + 24, p.y + 212)
    UI.field(self.path, layout.path, self.activeField == "path")
    UI.button("Browse", layout.browse)
    if self.mode == "create" then
        UI.text("Create: " .. FileSystem.join(self.path, self.name), p.x + 24, p.y + 290, p.w - 48)
    end
    if self.error then UI.text(self.error, p.x + 24, p.y + 316, p.w - 48, {1, 0.55, 0.5, 1}) end
    UI.button(self.mode == "create" and "Create project" or "Open project", layout.submit, true)
    UI.text("Tab: next field    Enter: confirm    Ctrl+V: paste path", p.x + 24, p.y + 412, p.w - 48)
    love.graphics.pop()
end

function ProjectStart:mousepressed(x, y, button)
    if button ~= 1 then return end
    local r = self:layout()
    if UI.contains(x, y, r.create) then self.mode = "create"; self.activeField = "name"; self.error = nil
    elseif UI.contains(x, y, r.open) then self.mode = "open"; self.activeField = "path"; self.error = nil
    elseif self.mode == "create" and UI.contains(x, y, r.name) then self.activeField = "name"
    elseif UI.contains(x, y, r.path) then self.activeField = "path"
    elseif UI.contains(x, y, r.browse) then
        self:browse()
    elseif UI.contains(x, y, r.submit) then self:submit()
    else self.activeField = nil end
    self.replace = true
end

function ProjectStart:textinput(text)
    if not self.activeField then return end
    self[self.activeField] = (self.replace and "" or self[self.activeField]) .. text
    if self.activeField == "path" then self:setPath(self.path) end
    self.replace = false
end

function ProjectStart:keypressed(key)
    if key == "return" or key == "kpenter" then
        self:submit()
        return
    end
    if key == "tab" then
        self.activeField = self.mode == "create" and self.activeField == "path" and "name" or "path"
        self.replace = true
        return
    end
    if self.activeField then
        self[self.activeField], self.replace = UI.editKey(self[self.activeField], key, self.replace)
        if self.activeField == "path" then self:setPath(self.path) end
    end
end

return ProjectStart
