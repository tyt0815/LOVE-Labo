local Project = require("editor.project")
local FileSystem = require("editor.host_filesystem")
local UI = require("editor.ui")

local Launcher = {}
Launcher.__index = Launcher

local function rect(x, y, w, h) return { x = x, y = y, w = w, h = h } end

function Launcher.new(onOpen)
    return setmetatable({
        onOpen = onOpen, mode = "create", name = "New Project",
        path = love.filesystem.getUserDirectory(), activeField = "name",
        replace = true, error = nil, picker = nil
    }, Launcher)
end

function Launcher:layout()
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
    form.picker = rect(left, top, width, 460)
    return form
end

function Launcher:submit()
    -- 경로/파일 오류는 런처 안에 남겨, 실패 시 반쯤 열린 에디터를 만들지 않는다.
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

function Launcher:navigate(path)
    local ok, entries, err = pcall(FileSystem.list, path)
    if not ok then err, entries = tostring(entries), nil end
    self.picker.path = path
    self.picker.entries, self.picker.error, self.picker.scroll = {}, err, 0
    if entries then
        for _, entry in ipairs(entries) do
            if entry.type == "directory" then self.picker.entries[#self.picker.entries + 1] = entry end
        end
    end
end

function Launcher:pickerRects()
    local p = self:layout().picker
    return {
        path = rect(p.x + 24, p.y + 58, p.w - 154, 36),
        go = rect(p.x + p.w - 120, p.y + 58, 96, 36),
        up = rect(p.x + 24, p.y + 104, 90, 30),
        list = rect(p.x + 24, p.y + 146, p.w - 48, 232),
        choose = rect(p.x + 24, p.y + 400, p.w - 168, 36),
        cancel = rect(p.x + p.w - 134, p.y + 400, 110, 36)
    }
end

function Launcher:draw()
    local layout = self:layout()
    local p = layout.panel
    love.graphics.push("all")
    love.graphics.clear(0.065, 0.075, 0.095, 1)
    love.graphics.setColor(0.105, 0.12, 0.15, 1)
    love.graphics.rectangle("fill", p.x, p.y, p.w, p.h, 8, 8)
    if self.picker then
        local r = self:pickerRects()
        UI.text("Choose folder", p.x + 24, p.y + 22)
        UI.field(self.picker.path, r.path, self.activeField == "picker")
        UI.button("Go", r.go)
        UI.button("Up", r.up)
        love.graphics.setScissor(r.list.x, r.list.y, r.list.w, r.list.h)
        for i, entry in ipairs(self.picker.entries) do
            local y = r.list.y + (i - 1 - self.picker.scroll) * 28
            if y + 28 > r.list.y and y < r.list.y + r.list.h then
                UI.button("[Folder] " .. entry.name, rect(r.list.x, y, r.list.w, 26))
            end
        end
        if self.picker.error then UI.text(self.picker.error, r.list.x, r.list.y, r.list.w, {1, 0.55, 0.5, 1})
        elseif #self.picker.entries == 0 then UI.text("No subfolders", r.list.x, r.list.y) end
        love.graphics.setScissor()
        UI.button("Use this folder", r.choose, true)
        UI.button("Cancel", r.cancel)
    else
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
    end
    love.graphics.pop()
end

function Launcher:mousepressed(x, y, button)
    if button ~= 1 then return end
    if self.picker then
        local r = self:pickerRects()
        if UI.contains(x, y, r.path) then self.activeField = "picker"; self.replace = true
        elseif UI.contains(x, y, r.go) then self:navigate(self.picker.path); self.activeField = nil
        elseif UI.contains(x, y, r.up) then self:navigate(FileSystem.parent(self.picker.path)); self.activeField = nil
        elseif UI.contains(x, y, r.cancel) then self.picker = nil; self.activeField = "path"; self.replace = true
        elseif UI.contains(x, y, r.choose) then
            local ok, info, err = pcall(FileSystem.info, self.picker.path)
            if not ok then err, info = tostring(info), nil end
            if info and info.type == "directory" then
                self.path = self.picker.path; self.picker = nil; self.activeField = "path"; self.replace = true
            else self.picker.error = err or "Folder does not exist" end
        elseif UI.contains(x, y, r.list) then
            local i = math.floor((y - r.list.y) / 28) + 1 + self.picker.scroll
            local entry = self.picker.entries[i]
            if entry then self:navigate(FileSystem.join(self.picker.path, entry.name)); self.activeField = nil end
        end
        return
    end
    local r = self:layout()
    if UI.contains(x, y, r.create) then self.mode = "create"; self.activeField = "name"; self.error = nil
    elseif UI.contains(x, y, r.open) then self.mode = "open"; self.activeField = "path"; self.error = nil
    elseif self.mode == "create" and UI.contains(x, y, r.name) then self.activeField = "name"
    elseif UI.contains(x, y, r.path) then self.activeField = "path"
    elseif UI.contains(x, y, r.browse) then
        self.picker = {}; self:navigate(self.path); self.activeField = "picker"
    elseif UI.contains(x, y, r.submit) then self:submit()
    else self.activeField = nil end
    self.replace = true
end

function Launcher:textinput(text)
    if not self.activeField then return end
    local owner, field = self, self.activeField
    if field == "picker" then owner, field = self.picker, "path" end
    owner[field] = (self.replace and "" or owner[field]) .. text
    self.replace = false
end

function Launcher:keypressed(key)
    if key == "escape" and self.picker then self.picker = nil; self.activeField = "path"; return end
    if key == "return" or key == "kpenter" then
        if self.picker then self:navigate(self.picker.path) else self:submit() end
        return
    end
    if key == "tab" and not self.picker then
        self.activeField = self.mode == "create" and self.activeField == "path" and "name" or "path"
        self.replace = true
        return
    end
    if self.activeField then
        local owner, field = self, self.activeField
        if field == "picker" then owner, field = self.picker, "path" end
        owner[field], self.replace = UI.editKey(owner[field], key, self.replace)
    end
end

function Launcher:wheelmoved(_, y)
    if self.picker then
        local visible = math.floor(self:pickerRects().list.h / 28)
        self.picker.scroll = math.floor(math.max(0, math.min(math.max(0, #self.picker.entries - visible), self.picker.scroll - y * 3)))
    end
end

return Launcher
