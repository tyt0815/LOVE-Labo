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

end

function Operations.new(app, browser)
    return setmetatable({app = app, browser = browser, project = browser.project}, Operations)
end
function Operations:perform(callback)
    if self.app:isPlaying() then return false, "Stop Play before editing asset files" end
    self.app.inspector:commitEdit()
    self.app:recordHistory()
    local previous = self.app.performingAssets
    self.app.performingAssets = true
    local called, ok, result = pcall(callback)
    self.app.performingAssets = previous
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
    local id = self.project:getAssetId(reference)
    for _, missing in ipairs(self.project.missingAssets or {}) do
        if missing.id == id then
            local usages = require("editor.AssetRepair").usage(self.project, id, self.app.level)
            assert(#usages == 0, "Asset is referenced by: " .. table.concat(usages, ", "))
        end
    end
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
function Operations:reindexOrRollback(source, target, kind, command, restoring)
    local indexed, err = self.project:rebuildAssetIndex(false, true)
    if indexed then return end
    transfer(target, source, kind)
    if restoring then require("editor.AssetCatalog").remove(self.project, command.reference)
    else require("editor.AssetCatalog").update(self.project, command.metadata) end
    self.project:rebuildAssetIndex(false, true)
    error(err)
end
function Operations:stash(command)
    self:checkDelete(command.reference)
    local path = self:livePath(command.reference)
    matches(command.snapshot, snapshot(path))
    local storage = self:storage(command)
    command.metadata = require("editor.AssetCatalog").capture(self.project, command.reference)
    transfer(path, storage, command.snapshot[""].type)
    local removed, removeError = require("editor.AssetCatalog").remove(self.project, command.reference)
    if not removed then transfer(storage, path, command.snapshot[""].type); error(removeError) end
    self:reindexOrRollback(path, storage, command.snapshot[""].type, command, false)
end
function Operations:restore(command)
    local storage = self:storage(command)
    matches(command.snapshot, snapshot(storage))
    local parent, info = self.project:checkedEntry(command.reference:match("^(.*)/[^/]+$"))
    assert(parent and info.type == "directory", "Restore parent is missing")
    local path = assert(self.project:resolvePath(command.reference))
    transfer(storage, path, command.snapshot[""].type)
    local restored, restoreError = require("editor.AssetCatalog").update(self.project, command.metadata or {})
    if not restored then transfer(path, storage, command.snapshot[""].type); error(restoreError) end
    self:reindexOrRollback(storage, path, command.snapshot[""].type, command, true)
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
function Operations:recordCreation(reference, created)
    local captured, state = pcall(function()
        local commands = {}
        for _, path in ipairs(created and #created > 0 and created or {reference}) do
            commands[#commands + 1] = {reference = path, snapshot = snapshot(self:livePath(path))}
        end
        return commands
    end)
    if not captured then
        for i = #(created or {reference}), 1, -1 do self.project:deleteEntry((created or {reference})[i]) end
        return false, tostring(state)
    end
    local command = {reference = reference}
    command.undo = function()
        for i = #state, 1, -1 do
            local saved, err = pcall(self.stash, self, state[i])
            if not saved then
                for j = i + 1, #state do self:restore(state[j]) end
                error(err)
            end
        end
        self:refresh(reference); return true
    end
    command.redo = function()
        for i = 1, #state do
            local restored, err = pcall(self.restore, self, state[i])
            if not restored then
                for j = i - 1, 1, -1 do self:stash(state[j]) end
                error(err)
            end
        end
        self:refresh(reference); return true
    end
    self.app:pushAssetAction(command)
    return true, reference
end
function Operations:create(folder, kind, name, options)
    return self:perform(function()
        local ok, reference, created = self.project:createEntry(folder, kind, name, options)
        if not ok then return false, reference end
        return self:recordCreation(reference, created)
    end)
end
function Operations:import(input, folder)
    return self:perform(function()
        local ok, reference = require("editor.AssetImport").copy(self.project, input, folder)
        if not ok then return false, reference end
        local recorded, err = self:recordCreation(reference)
        if recorded then self:refresh(reference) end
        return recorded, err
    end)
end

function Operations:createLinkedPrefab(folder, name, object)
    local hierarchy = require("project.PrefabHierarchy")
    local allowed, err = hierarchy.canLinkCapture(object)
    if not allowed then return false, err end
    local app, document, reference = self.app, self.app.document, nil
    local ok, failure = self:batch(function()
        local data, captureError, paths = hierarchy.capture(self.project, app.level, object)
        if not data then return false, captureError end
        local before = assert(require("editor.LevelFile").encode(app.level))
        local created, result = self:create(folder, "prefab", name, {prefabData = data})
        if not created then return false, result end
        reference = result
        local after
        local function restore(text)
            document.level = assert(require("editor.LevelFile").decode(text))
            local history = app.histories[document]
            document.level.nextAuthoringId = math.max(document.level.nextAuthoringId, history.highWater or 1)
            history.entries[history.index].text = text
            if app.document == document then
                app:setDocument(document)
                app.sceneView:setSelection({app.level:findLObject(object.authoringId)})
                app.inspectorSource = "scene"; app.instanceInspectorObject = nil; app:updateInspectorTarget()
            end
            return true
        end
        app:pushAssetAction({undo = function() return restore(before) end, redo = function() return restore(after) end})
        local linked, linkError = hierarchy.linkCapture(self.project, app.level, object, reference, paths)
        if not linked then return false, linkError end
        after = assert(require("editor.LevelFile").encode(app.level))
        restore(after)
        return true
    end)
    return ok, ok and reference or failure
end
function Operations:delete(reference)
    return self:perform(function()
        self:checkDelete(reference)
        if #assert(self.project:deletionEntries(reference)) == 0 then
            local catalog = require("editor.AssetCatalog")
            local metadata = catalog.capture(self.project, reference)
            local function remove()
                assert(self.project:getAssetId(reference) == metadata[reference].id, "Asset identity changed outside Undo history")
                self:checkDelete(reference)
                assert(catalog.remove(self.project, reference))
                local ok, err = self.project:rebuildAssetIndex()
                if not ok then catalog.update(self.project, metadata); error(err) end
                self:refresh(reference)
                return true
            end
            local function restore()
                assert(not self.project:getAssetId(reference), "Asset identity changed outside Undo history")
                local path = assert(self.project:resolvePath(reference))
                local info, err = Fs.info(path)
                assert(not info and not err, err or "Undo destination already exists")
                assert(catalog.update(self.project, metadata))
                local ok, rebuildError = self.project:rebuildAssetIndex()
                if not ok then catalog.remove(self.project, reference); error(rebuildError) end
                self:refresh(reference)
                return true
            end
            remove()
            self.app:pushAssetAction({undo = restore, redo = remove})
            return true
        end
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
        local identities = require("editor.AssetCatalog").capture(self.project, source)
        local expected = snapshot(self:livePath(source))
        local ok, err = self.browser:moveEntryDirect(entry, destination)
        if not ok then return false, err end
        local function replay(from, to)
            for reference, meta in pairs(identities) do
                local current = from .. reference:sub(#source + 1)
                assert(self.project:getAssetId(current) == meta.id, "Asset identity changed outside Undo history")
            end
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
-- 여러 파일 작업을 하나의 Undo 명령으로 묶고 실패 시 완료된 작업을 되돌린다.
function Operations:batch(callback)
    return self:perform(function()
        local app, commands = self.app, {}
        local push = app.pushAssetAction
        app.pushAssetAction = function(_, command) commands[#commands + 1] = command end
        local called, ok, err = pcall(callback)
        app.pushAssetAction = push
        local function replay(direction)
            local completed = {}
            local first, last, step = 1, #commands, 1
            if direction == "undo" then first, last, step = #commands, 1, -1 end
            for i = first, last, step do
                local success, result, failure = pcall(commands[i][direction])
                if not success or not result then
                    local rollbackError
                    for j = #completed, 1, -1 do
                        local restored, value = pcall(commands[completed[j]][direction == "undo" and "redo" or "undo"])
                        if not restored or not value then rollbackError = tostring(value) end
                    end
                    error(tostring(success and failure or result) .. (rollbackError and " / rollback failed: " .. rollbackError or ""))
                end
                completed[#completed + 1] = i
            end
            return true
        end
        if not called or not ok then
            local restored, restoreError = pcall(replay, "undo")
            return false, tostring(called and err or ok) .. (restored and "" or " / rollback failed: " .. tostring(restoreError))
        end
        if #commands > 0 then push(app, {undo = function() return replay("undo") end, redo = function() return replay("redo") end}) end
        return true
    end)
end
function Operations:deleteMany(entries)
    return self:batch(function()
        for _, entry in ipairs(entries) do self:checkDelete(entry.reference) end
        for _, entry in ipairs(entries) do local ok, err = self:delete(entry.reference); if not ok then return false, err end end
        return true
    end)
end
function Operations:moveMany(entries, folder)
    return self:batch(function()
        for _, entry in ipairs(entries) do
            local ok, err = self:move(entry, folder .. "/" .. (entry.name or entry.reference:match("[^/]+$")))
            if not ok then return false, err end
        end
        return true
    end)
end
return Operations
