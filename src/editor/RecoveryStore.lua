local Fs = require("editor.HostFileSystem")
local Json = require("project.Json")
local Store = {}
Store.__index = Store
function Store.new(app)
    local directory = Fs.join(app.project.rootPath, ".labo")
    if not Fs.info(directory) then assert(Fs.mkdir(directory)) end
    directory = Fs.join(directory, "Recovery")
    if not Fs.info(directory) then assert(Fs.mkdir(directory)) end
    return setmetatable({app = app, directory = directory, path = Fs.join(directory, require("project.AssetId").new() .. ".json"), elapsed = 0, restoredLevels = {}}, Store)
end
function Store:collect()
    local app, entries, seen = self.app, {}, {}
    local function level(document, id)
        if seen[document] then return end; seen[document] = true
        local restored = self.restoredLevels[document]
        -- 원본이 없는 문서는 기준 스냅샷과 같더라도 파일로 저장되기 전까지 복구 대상이다.
        if document:isDirty() or restored and not document.path then
            entries[#entries + 1] = {kind = "level", id = id or document.assetId or restored and restored.id,
                recoveryId = restored and restored.recoveryId, path = document.path, baseline = document.savedSnapshot,
                text = assert(require("editor.LevelFile").encode(document.level))}
        end
    end
    level(app.document, app.documentAssetId)
    if app.scopeInspector then
        for id, document in pairs(app.scopeInspector.levels) do level(document, id) end
        local document = app.scopeInspector.projectDocument
        if document:isDirty() then entries[#entries + 1] = {kind = "project", text = document:snapshot(), baseline = document.savedSnapshot} end
    end
    for document in pairs(self.restoredLevels) do level(document) end
    for id, document in pairs(app.prefabDocuments or {}) do
        if document:isDirty() then entries[#entries + 1] = {kind = "prefab", id = id, baseline = document.savedSnapshot, text = assert(require("editor.Prefab").encodeData(document.data))} end
    end
    table.sort(entries, function(a, b) return a.kind .. tostring(a.id or a.path or a.recoveryId or "") < b.kind .. tostring(b.id or b.path or b.recoveryId or "") end)
    return entries
end
function Store:flush()
    local entries = self:collect()
    local payload = assert(Json.encode(entries, true))
    if payload == self.last then return true end
    if #entries == 0 then
        if Fs.info(self.path) then local ok, err = Fs.removeFile(self.path); if not ok then return false, err end end
    else
        local ok, err = Fs.writeAtomic(self.path, assert(Json.encode({version = 1, time = os.date("%Y-%m-%d %H:%M:%S"), entries = entries}, true)))
        if not ok then return false, err end
    end
    self.last = payload
    return true
end
function Store:update(dt)
    self.elapsed = self.elapsed + dt
    if self.elapsed < 2 then return end
    self.elapsed = 0
    local ok, err = pcall(self.flush, self)
    if not ok then self.app.runtimeError = tostring(err)
    elseif err == false then self.app.runtimeError = "Recovery copy could not be written" end
end
function Store:restore(entry)
    local app = self.app
    local restoredDocument
    if entry.kind == "level" then
        local data = assert(require("editor.LevelFile").decode(entry.text))
        local document = assert(require("editor.LevelDocument").new(data))
        local path = entry.id and app.project:resolveAssetFile(entry.id)
        if path then
            document.path = path
            local saved = assert(require("editor.LevelDocument").load(path))
            document.savedSnapshot = saved.savedSnapshot
        else document.savedSnapshot = entry.baseline end
        if path and entry.id and app.scopeInspector then
            app.scopeInspector:rememberLevelDocument(document, entry.id)
            app.histories[document] = require("editor.History").new(entry.text)
        end
        -- 현재 문서·에셋 캐시에 들어가지 않는 두 번째 이후의 미등록 레벨도 강하게 보관한다.
        self.restoredLevels[document] = {id = entry.id, recoveryId = entry.recoveryId or require("project.AssetId").new()}
        restoredDocument = document
    elseif entry.kind == "prefab" then
        local document = assert(require("editor.PrefabDocument").load(app.project, entry.id))
        document.data = assert(require("editor.Prefab").decode(entry.text))
        app.prefabDocuments[entry.id] = document
        app.histories[document] = require("editor.History").new(entry.text)
    elseif entry.kind == "project" then
        app.scopeInspector.projectDocument:restore(entry.text)
    else error("Unknown recovery document kind") end
    app.project.draftRevision = (app.project.draftRevision or 0) + 1
    app.instanceInspectorObject = nil
    return restoredDocument
end
function Store:offer()
    local choices, sources = {}, {}
    for _, file in ipairs(assert(Fs.list(self.directory))) do
        if file.type == "file" and not file.isLink and file.name:match("%.json$") then
            local path = Fs.join(self.directory, file.name)
            if path ~= self.path then
                local data = Json.decode(assert(Fs.read(path)))
                if data and data.version == 1 and type(data.entries) == "table" then
                    sources[path] = data
                    for index, entry in ipairs(data.entries) do
                        local label = entry.id and self.app.project:getAssetReference(entry.id) or entry.kind == "project" and "Project settings" or "Untitled Level"
                        local current
                        local loaded = pcall(function()
                            if entry.kind == "level" and entry.id then current = assert(require("editor.LevelDocument").load(assert(self.app.project:resolveAssetFile(entry.id)))).savedSnapshot
                            elseif entry.kind == "prefab" then current = assert(require("editor.PrefabDocument").load(self.app.project, entry.id)).savedSnapshot
                            elseif entry.kind == "project" then current = self.app.scopeInspector.projectDocument.savedSnapshot end
                        end)
                        local conflict = not loaded or current and current ~= entry.baseline
                        choices[#choices + 1] = {label = (data.time or "") .. " / " .. (label or "Missing asset") .. (conflict and " [external change]" or ""),
                            value = {source = path, index = index, entry = entry}, checked = not conflict}
                    end
                else self.app.runtimeError = "Invalid recovery copy preserved: " .. path end
            end
        end
    end
    if #choices == 0 then return end
    require("editor.ui.Dialog").new(self.app.uiRoot, {title = "Recover unsaved edits", message = "Restore drafts; originals stay unchanged.\nLater keeps copies.", choiceLabel = "Recovery drafts",
        choices = choices, checkboxes = true, confirmLabel = "Restore", cancelLabel = "Later", backLabel = "Discard copies", onBack = function()
            for path in pairs(sources) do assert(Fs.removeFile(path)) end
            self.app.uiRoot:dismissPopup()
        end,
        onConfirm = function(_, _, checked)
            local ok, err = pcall(function()
                -- 복원 사본이 새 세션에 안전하게 기록되기 전에는 이전 사본을 지우지 않는다.
                local selected, identities = {}, {}
                for _, choice in ipairs(checked) do
                    local key = choice.entry.kind .. tostring(choice.entry.id or choice.entry.path or choice.entry.recoveryId or choice.source .. ":" .. choice.index)
                    assert(not identities[key], "Select only one recovery version per document")
                    identities[key] = true
                end
                local firstLevel
                for _, choice in ipairs(checked) do
                    -- 쓰기 실패 후 같은 선택을 재시도할 때 문서를 중복 생성하지 않는다.
                    if not choice.restored then
                        choice.document = self:restore(choice.entry)
                        choice.restored = true
                    end
                    firstLevel = firstLevel or choice.document
                    selected[choice.source] = selected[choice.source] or {}; selected[choice.source][choice.index] = true
                end
                local saved, saveError = self:flush()
                assert(saved, saveError)
                for path, indexes in pairs(selected) do
                    local remaining = {}
                    for index, entry in ipairs(sources[path].entries) do if not indexes[index] then remaining[#remaining + 1] = entry end end
                    if #remaining == 0 then assert(Fs.removeFile(path))
                    else sources[path].entries = remaining; assert(Fs.writeAtomic(path, assert(Json.encode(sources[path], true)))) end
                end
                -- 문서 전환은 팝업을 닫으므로 복원과 사본 이전이 모두 성공한 뒤 실행한다.
                if firstLevel then assert(self.app:setDocument(firstLevel)) end
                self.app:updateInspectorTarget()
            end)
            return ok, not ok and tostring(err) or nil
        end})
end
return Store
