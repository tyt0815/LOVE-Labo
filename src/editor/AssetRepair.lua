local Catalog = require("editor.AssetCatalog")
local Fs = require("editor.HostFileSystem")
local Repair = {}
local function extension(path) return (path:match("%.[^/.]+$") or ""):lower() end
function Repair.plan(project)
    local rows, signatures = {}, {}
    for _, owner in ipairs(Catalog.owners(project)) do
        signatures[#signatures + 1] = owner.path .. ":" .. (owner.readOnly and owner.plugin.read("assets.json") or Fs.read(owner.path) or "")
    end
    for _, asset in ipairs(project.untrackedAssets or {}) do signatures[#signatures + 1] = asset.reference .. ":" .. asset.hash end
    table.sort(signatures)
    for _, missing in ipairs(project.missingAssets or {}) do
        local owner = Catalog.owner(project, missing.reference)
        local row = {id = missing.id, reference = missing.reference, candidates = {}, readOnly = missing.readOnly}
        local matches = {}
        for _, asset in ipairs(project.untrackedAssets or {}) do
            local candidateOwner = Catalog.owner(project, asset.reference)
            if owner.path == candidateOwner.path and extension(asset.reference) == extension(missing.reference) then
                row.candidates[#row.candidates + 1] = asset.reference
                if missing.hash and asset.hash == missing.hash then matches[#matches + 1] = asset.reference end
            end
        end
        table.sort(row.candidates)
        if #matches == 1 and not row.readOnly then row.target, row.checked, row.confidence = matches[1], true, "Content match"
        else row.checked, row.confidence = false, #matches > 1 and "Ambiguous content match" or "Choose a file" end
        rows[#rows + 1] = row
    end
    local claims = {}
    for _, row in ipairs(rows) do if row.target then claims[row.target] = (claims[row.target] or 0) + 1 end end
    for _, row in ipairs(rows) do if row.target and claims[row.target] > 1 then
        row.target, row.checked, row.confidence = nil, false, "Ambiguous content match"
    end end
    table.sort(rows, function(a, b) return a.reference < b.reference end)
    return {rows = rows, revision = Catalog.hash(table.concat(signatures, "\n"))}
end
function Repair.usage(project, id, level, protectedIds)
    local result = {}
    local projectScripts = require("project.Json").encode({scripts = project.scripts, scriptOverrides = project.scriptOverrides})
    if not projectScripts or projectScripts:find(id, 1, true) then result[#result + 1] = "Project scripts" end
    if project.defaultLevelReference == id then result[#result + 1] = "Project default level" end
    for _, protected in ipairs(protectedIds or {}) do if protected == id then result[#result + 1] = "Current open document" end end
    local draft = project.draftAssets and project.draftAssets[id]
    if draft and draft:isDirty() then result[#result + 1] = "Unsaved Prefab document" end
    for levelId, document in pairs(project.draftLevelAssets or {}) do
        if levelId == id and document:isDirty() then result[#result + 1] = "Unsaved Level document" end
        local bytes = require("editor.LevelFile").encode(document.level)
        if not bytes or bytes:find(id, 1, true) then result[#result + 1] = "Level draft: " .. tostring(project:getAssetReference(levelId) or levelId) end
    end
    -- 파일의 기존 위치가 사라져도 메모리에 남은 초안의 참조는 보호한다.
    for draftId, document in pairs(project.draftAssets or {}) do
        local bytes = require("project.Json").encode(document.data)
        if not bytes or bytes:find(id, 1, true) then
            result[#result + 1] = "Prefab draft: " .. tostring(project:getAssetReference(draftId) or draftId)
        end
    end
    for name, source in pairs(project.plugins and project.plugins.scripts or {}) do
        if source.id == id then result[#result + 1] = "Plugin public script: " .. name end
    end
    for reference in pairs(project.assetMetadata) do
        if reference:match("%.prefab$") or reference:match("%.level$") or reference:match("%.lua$") then
            local bytes = project:readAsset(reference)
            if bytes and bytes:find(id, 1, true) then result[#result + 1] = reference end
        end
    end
    if level and assert(require("project.Json").encode(level:toData())):find(id, 1, true) then result[#result + 1] = "Current unsaved level" end
    return result
end
function Repair.apply(project, request, level)
    local ok, err = project:rebuildAssetIndex(); if not ok then return false, err end
    local plan = Repair.plan(project)
    if request.revision ~= plan.revision then return false, "Asset repair revision conflict; refresh the plan" end
    local rows = {}; for _, row in ipairs(plan.rows) do rows[row.id] = row end
    local changes, used = {}, {}
    for _, item in ipairs(request.changes or {}) do
        local row = rows[item.id]
        if not row or row.readOnly then return false, "Missing or read-only repair entry" end
        if used[item.id] then return false, "Duplicate repair entry" end
        used[item.id] = true
        if item.delete then
            local usages = Repair.usage(project, item.id, level, request.protectedIds)
            if #usages > 0 then return false, "Asset is referenced by: " .. table.concat(usages, ", ") end
        else
            local allowed = false; for _, candidate in ipairs(row.candidates) do if candidate == item.target then allowed = true end end
            if not allowed or used[item.target] or project:getAssetId(item.target) then return false, "Choose a unique untracked file" end
            local path, info = project:checkedEntry(item.target)
            if not path or info.type ~= "file" then return false, "Repair target is missing" end
            used[item.target] = true
            local meta = {}; for key, value in pairs(project.assetMetadata[row.reference]) do meta[key] = value end
            local bytes, readError = Fs.read(path)
            if not bytes then return false, readError or "Cannot read repair target" end
            meta.hash = Catalog.hash(bytes)
            changes[item.target] = meta
        end
        changes[row.reference] = false
    end
    if next(changes) == nil then return false, "Select at least one repair" end
    local saved, saveError = Catalog.update(project, changes); if not saved then return false, saveError end
    return project:rebuildAssetIndex()
end
return Repair
