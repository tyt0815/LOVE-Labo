local Fs = require("editor.HostFileSystem")
local Json = require("project.Json")
local Operations = {}
Operations.__index = Operations

-- 실제 바이트는 프로젝트 밖으로 복사하지 않고 캐시로 이동한다. 해시는 외부 변경 감지용이다.
local function digest(bytes) return love.data.encode("string", "hex", love.data.hash("sha256", bytes)) end
local function scan(path, relative, result)
    local info = assert(Fs.info(path), "History entry is missing: " .. path)
    assert(not info.isLink, "History cannot follow filesystem links")
    local entry = {type = info.type}
    result[relative] = entry
    if info.type == "directory" then
        for _, child in ipairs(assert(Fs.list(path))) do
            scan(Fs.join(path, child.name), relative .. "/" .. child.name, result)
        end
    else
        local bytes = assert(Fs.read(path))
        entry.hash = digest(bytes)
        if path:match("%.meta$") then
            local meta = Json.decode(bytes)
            entry.id = type(meta) == "table" and meta.id or nil
        end
    end
end
local function snapshot(path)
    local result = {}
    scan(path, "", result)
    if result[""].type == "file" then scan(path .. ".meta", ".meta", result) end
    return result
end
local function matches(expected, actual, identityOnly)
    for name, entry in pairs(expected) do
        local current = actual[name]
        assert(current and current.type == entry.type, "Asset changed outside Undo history")
        if identityOnly then
            if entry.id then assert(current.id == entry.id, "Asset identity changed outside Undo history") end
        else assert(current.hash == entry.hash, "Asset content changed outside Undo history") end
    end
    if not identityOnly then
        for name in pairs(actual) do assert(expected[name], "Asset contains files added outside Undo history") end
    end
end
local function transfer(source, target, kind)
    for _, path in ipairs({target, target .. ".meta"}) do
        local info, err = Fs.info(path)
        assert(not info and not err, err or "Undo destination already exists: " .. path)
    end
    assert(Fs.rename(source, target))
    if kind == "file" then
        local moved, err = Fs.rename(source .. ".meta", target .. ".meta")
        if not moved then
            local restored, restoreError = Fs.rename(target, source)
            error(tostring(err) .. (restored and "" or " / rollback failed: " .. tostring(restoreError)))
        end
    end
end

function Operations.new(app, browser)
    return setmetatable({app = app, browser = browser, project = browser.project}, Operations)
end
function Operations:perform(callback)
    self.app.inspector:commitEdit()
    self.app:recordHistory()
    self.app.performingAssets = true
    local called, ok, result = pcall(callback)
    self.app.performingAssets = nil
    if not called then return false, tostring(ok) end
    return ok, result
end
function Operations:livePath(reference)
    return assert(self.project:checkedEntry(reference))
end
function Operations:checkDelete(reference)
    if self.browser.canDelete then
        local allowed, err = self.browser.canDelete(reference)
        assert(allowed, err)
    end
    assert(self.project:deletionEntries(reference))
end
function Operations:storage(command)
    local root = Fs.join(self.project.rootPath, ".labo-history")
    local info, err = Fs.info(root)
    assert(not err, err)
    if info then assert(info.type == "directory" and not info.isLink, "History storage must be a regular folder")
    else assert(Fs.mkdir(root)) end
    if not command.directory then
        command.directory = Fs.join(root, require("project.AssetId").new())
        assert(Fs.mkdir(command.directory))
        assert(Fs.createFile(Fs.join(command.directory, "manifest.json"), assert(Json.encode({version = 1,
            reference = command.reference, snapshot = command.snapshot}, true))))
    end
    local directory = assert(Fs.info(command.directory))
    assert(directory.type == "directory" and not directory.isLink, "History storage was replaced")
    return Fs.join(command.directory, "payload")
end
function Operations:reindexOrRollback(source, target, kind)
    local indexed, err = self.project:rebuildAssetIndex(false, true)
    if indexed then return end
    transfer(target, source, kind)
    self.project:rebuildAssetIndex(false, true)
    error(err)
end
function Operations:stash(command)
    self:checkDelete(command.reference)
    local path = self:livePath(command.reference)
    matches(command.snapshot, snapshot(path))
    local storage = self:storage(command)
    transfer(path, storage, command.snapshot[""].type)
    self:reindexOrRollback(path, storage, command.snapshot[""].type)
end
function Operations:restore(command)
    local storage = self:storage(command)
    matches(command.snapshot, snapshot(storage))
    local parent, info = self.project:checkedEntry(command.reference:match("^(.*)/[^/]+$"))
    assert(parent and info.type == "directory", "Restore parent is missing")
    local path = assert(self.project:resolvePath(command.reference))
    transfer(storage, path, command.snapshot[""].type)
    self:reindexOrRollback(storage, path, command.snapshot[""].type)
end
function Operations:refresh(reference)
    self.browser:refresh(true)
    local parent = reference:match("^(.*)/[^/]+$")
    if self.project:checkedEntry(reference) then
        self.browser:openFolder(parent)
        self.browser.selectedReference = reference
    end
    self.app.instanceInspectorObject = nil
    if self.app.spriteAssets then self.app.spriteAssets:clear() end
    self.app:updateInspectorTarget()
    -- 이동 중 ID 정규화는 파일 작업의 일부이며 별도 문서 편집으로 기록하지 않는다.
    local history = self.app.histories[self.app.document]
    history.entries[history.index].text = assert(require("editor.LevelFile").encode(self.app.level))
end
function Operations:create(folder, kind, name, options)
    return self:perform(function()
        local ok, reference = self.project:createEntry(folder, kind, name, options)
        if not ok then return false, reference end
        local captured, state = pcall(function() return snapshot(self:livePath(reference)) end)
        if not captured then
            local removed, err = self.project:deleteEntry(reference)
            return false, tostring(state) .. (removed and "" or " / rollback failed: " .. tostring(err))
        end
        local command = {reference = reference, snapshot = state}
        command.undo = function() self:stash(command); self:refresh(reference); return true end
        command.redo = function() self:restore(command); self:refresh(reference); return true end
        self.app:pushAssetAction(command)
        return true, reference
    end)
end
function Operations:delete(reference)
    return self:perform(function()
        self:checkDelete(reference)
        local command = {reference = reference, snapshot = snapshot(self:livePath(reference))}
        self:stash(command)
        command.undo = function() self:restore(command); self:refresh(reference); return true end
        command.redo = function() self:stash(command); self:refresh(reference); return true end
        self.app:pushAssetAction(command)
        return true
    end)
end
function Operations:move(entry, destination)
    return self:perform(function()
        local source = entry.reference
        local expected = snapshot(self:livePath(source))
        local ok, err = self.browser:moveEntryDirect(entry, destination)
        if not ok then return false, err end
        local function replay(from, to)
            matches(expected, snapshot(self:livePath(from)), true)
            local moved, moveError = self.browser:moveEntryDirect({reference = from}, to)
            assert(moved, moveError)
            self:refresh(to)
            return true
        end
        self.app:pushAssetAction({undo = function() return replay(destination, source) end,
            redo = function() return replay(source, destination) end})
        local history = self.app.histories[self.app.document]
        history.entries[history.index].text = assert(require("editor.LevelFile").encode(self.app.level))
        return true
    end)
end
return Operations
