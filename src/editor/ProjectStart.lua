local Theme = require("editor.Theme")
local Project = require("editor.Project")
local FileSystem = require("editor.HostFileSystem")
local Ui = require("editor.Ui")
local FolderDialog = require("editor.FolderDialog")
local Ime = require("editor.ui.Ime")
local Edit = require("editor.ui.TextEdit")
local RecentProjects = require("editor.RecentProjects")

local ProjectStart = {}
ProjectStart.__index = ProjectStart

local function rect(x, y, w, h) return { x = x, y = y, w = w, h = h } end

function ProjectStart.new(onOpen, selectFolder, options)
    options = options or {}
    local self = setmetatable({
        onOpen = onOpen, mode = "open", name = "",
        path = "", activeField = "path", scroll = 0,
        entries = options.entries or RecentProjects.load(), saveRecent = options.saveRecent or RecentProjects.save,
        cancel = options.cancel or love.event.quit,
        replace = true, error = nil, selectFolder = selectFolder or FolderDialog.selectFolder
    }, ProjectStart)
    self.windowControls = require("editor.ui.WindowControls").new()
    love.window.setTitle("LÖVE Labo - Project Browser")
    self:setPath(love.filesystem.getUserDirectory())
    return self
end

function ProjectStart:setPath(path)
    local previous = self.path
    -- 입력 출처와 OS에 관계없이 시작 화면의 경로 표기는 '/'로 통일한다.
    self.path = path:gsub("\\", "/")
    if self.selected and self.selected > 1 and self.entries[self.selected - 1].path ~= self.path then self.selected = nil end
    if self.editState and self.editState.text == previous then self.editState.text = self.path end
    if self.mode == "open" then
        local ok, bytes = pcall(FileSystem.read, FileSystem.join(self.path, Project.FILE_NAME))
        local data = ok and bytes and require("editor.Json").decode(bytes)
        self.name = type(data) == "table" and type(data.name) == "string" and data.name or ""
    end
end

function ProjectStart:layout()
    local w, h = love.graphics.getDimensions()
    local left, width, bottom = 24, w - 48, h - 156
    local nameWidth = math.min(280, width * 0.32)
    local openWidth = Ui.buttonWidth("Open Existing")
    local form = {panel = rect(left, 24, width, h - 48),
        openExisting = rect(left + width - openWidth - 16, 40, openWidth, 32),
        grid = rect(left + 16, 96, width - 32, bottom - 112),
        path = rect(left + 16, bottom + 32, width - nameWidth - 48, 34),
        name = rect(left + width - nameWidth - 16, bottom + 32, nameWidth, 34),
        cancel = rect(left + width - 104, h - 74, 88, 34),
        submit = rect(left + width - 204, h - 74, 88, 34),
        browse = rect(left + width - 316, h - 74, 100, 34)}
    form.columns = math.max(1, math.floor((form.grid.w + 16) / 196))
    if require("editor.WindowFrame").active then
        form.panel.y, form.panel.h = form.panel.y + 16, form.panel.h - 16
        form.openExisting.y, form.grid.y, form.grid.h = form.openExisting.y + 16, form.grid.y + 16, form.grid.h - 16
    end
    form.cardWidth, form.cardHeight = 180, 190
    local rows = math.ceil((#self.entries + 1) / form.columns)
    self.maxScroll = math.max(0, rows * 206 - 16 - form.grid.h)
    self.scroll = math.max(0, math.min(self.scroll, self.maxScroll))
    form.cards = {}
    for index = 1, #self.entries + 1 do
        form.cards[index] = rect(form.grid.x + ((index - 1) % form.columns) * 196,
            form.grid.y + math.floor((index - 1) / form.columns) * 206 - self.scroll, 180, 190)
    end
    return form
end

function ProjectStart:selectEntry(index)
    self:finishComposition()
    self.selected, self.error = index, nil
    if index == 1 then
        self.mode, self.name, self.activeField = "create", "New Project", "name"
        self:setPath(love.filesystem.getUserDirectory())
    else
        local entry = self.entries[index - 1]
        self.mode, self.name, self.activeField = "open", entry.name, "path"
        self:setPath(entry.path)
    end
    self.replace = true
    Edit.begin(self, self[self.activeField], true)
end

function ProjectStart:useOpenMode()
    self:finishComposition()
    self.mode, self.selected, self.error = "open", nil, nil
    self:setPath(self.path)
    self.activeField, self.replace = "path", true
    Edit.begin(self, self.path, true)
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
    self.entries = RecentProjects.remember(self.entries, project)
    -- 최근 목록 저장 실패는 이미 성공한 프로젝트 열기를 취소하지 않는다.
    pcall(self.saveRecent, self.entries)
    return true
end

function ProjectStart:browse()
    self:finishComposition()
    local title = self.mode == "create" and "새 프로젝트의 부모 폴더 선택" or "프로젝트 폴더 열기"
    local ok, path, err = pcall(self.selectFolder, self.path, title)
    if not ok then self.error = tostring(path); return end
    if err then self.error = err; return end
    if path then
        self:setPath(path); self.error = nil; self.selected = nil
    end
    self.activeField, self.replace = "path", true
    Edit.begin(self, self.path, true)
end

function ProjectStart:draw()
    local layout = self:layout()
    local p = layout.panel
    love.graphics.push("all")
    Theme.clear("background")
    require("editor.WindowFrame").setHeader(0, false)
    Ui.panel(p.x, p.y, p.w, p.h)
    Ui.label("Project Browser", p.x + 16, p.y + 18)
    Ui.text("Recent projects", p.x + 16, p.y + 46, p.w - 32, Theme.color("textMuted"))
    if self.mode == "create" then Ui.button("Open Existing", layout.openExisting) end
    love.graphics.push("all")
    local grid = layout.grid
    love.graphics.intersectScissor(grid.x, grid.y, grid.w, grid.h)
    for index, card in ipairs(layout.cards) do
        if card.y + card.h >= grid.y and card.y < grid.y + grid.h then
            local selected = self.selected == index
            Ui.row(card, selected)
            Theme.setColor("surface")
            love.graphics.rectangle("fill", card.x + 8, card.y + 8, card.w - 16, 126, 4, 4)
            Theme.setColor(index == 1 and "textMuted" or "iconBorder")
            if index == 1 then
                local cx, cy = card.x + card.w / 2, card.y + 70
                love.graphics.setLineWidth(2)
                love.graphics.line(cx - 16, cy, cx + 16, cy)
                love.graphics.line(cx, cy - 16, cx, cy + 16)
            else
                local cx, cy = card.x + card.w / 2, card.y + 70
                love.graphics.setLineWidth(2)
                love.graphics.rectangle("line", cx - 35, cy - 27, 70, 54, 4, 4)
                love.graphics.line(cx - 35, cy + 12, cx - 12, cy - 7, cx + 3, cy + 7, cx + 17, cy - 12, cx + 35, cy + 12)
                love.graphics.circle("line", cx - 15, cy - 13, 5)
            end
            local entry = self.entries[index - 1]
            Ui.label(entry and entry.name or "New Project", card.x + 10, card.y + 145, card.w - 20)
            Ui.text(entry and "Labo project" or "Create a project", card.x + 10, card.y + 167, card.w - 20, Theme.color("textMuted"))
            Theme.setColor(selected and "iconBorder" or "border")
            love.graphics.setLineWidth(selected and 2 or 1)
            love.graphics.rectangle("line", card.x + 0.5, card.y + 0.5, card.w - 1, card.h - 1, 4, 4)
        end
    end
    love.graphics.pop()
    Theme.setColor("border")
    love.graphics.line(p.x, layout.path.y - 30, p.x + p.w, layout.path.y - 30)
    Ui.text(self.mode == "create" and "Project Location (parent folder)" or "Project Location", layout.path.x, layout.path.y - 22)
    Ui.text("Project Name", layout.name.x, layout.name.y - 22)
    Ui.field(self.activeField == "path" and Ime.display(self, self.path, self.replace) or self.path,
        layout.path, self.activeField == "path", self.activeField == "path" and self.composition, self)
    Ui.field(self.activeField == "name" and Ime.display(self, self.name, self.replace) or self.name,
        layout.name, self.activeField == "name", self.activeField == "name" and self.composition, self)
    if self.error then Ui.text(self.error, layout.path.x, layout.path.y + 43, p.w - 360, Theme.color("error")) end
    Ui.button("Browse", layout.browse)
    Ui.button(self.mode == "create" and "Create" or "Open", layout.submit, true)
    Ui.button("Cancel", layout.cancel)
    self.windowControls:draw()
    love.graphics.pop()
end

function ProjectStart:mousepressed(x, y, button, presses)
    if self.windowControls:press(x, y, button) then return end
    if button ~= 1 then return end
    local r = self:layout()
    local sameField = self.activeField and (self.activeField ~= "name" or self.mode == "create") and Ui.contains(x, y, r[self.activeField])
    if sameField then
        self:finishComposition()
        Edit.press(self, self[self.activeField], r[self.activeField], x, false)
        self.replace = false
        return
    end
    self:finishComposition()
    if Ui.contains(x, y, r.cancel) then self.cancel(); return
    elseif self.mode == "create" and Ui.contains(x, y, r.openExisting) then self:useOpenMode(); return
    elseif self.mode == "create" and Ui.contains(x, y, r.name) then self.activeField = "name"
    elseif Ui.contains(x, y, r.path) then self.activeField = "path"
    elseif Ui.contains(x, y, r.browse) then
        self:browse()
    elseif Ui.contains(x, y, r.submit) then self:submit()
    else
        self.activeField = nil
        if Ui.contains(x, y, r.grid) then
            for index, card in ipairs(r.cards) do
                if Ui.contains(x, y, card) then
                    self:selectEntry(index)
                    if index > 1 and presses == 2 then self:submit() end
                    return
                end
            end
        end
    end
    self.replace = true
    if self.activeField then
        Edit.begin(self, self[self.activeField], true)
        if Ui.contains(x, y, r[self.activeField]) then Edit.press(self, self[self.activeField], r[self.activeField], x, true) end
    end
end

function ProjectStart:wheelmoved(_, dy)
    self:layout()
    self.scroll = math.max(0, math.min(self.maxScroll, self.scroll - dy * 54))
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
    if key == "escape" then
        if self.composition then Ime.cancel(self) else self.cancel() end
        return
    end
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
