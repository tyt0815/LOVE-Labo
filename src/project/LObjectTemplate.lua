local Definition = require("project.ObjectDefinition")
local Template = {}
function Template.source(project, reference)
    local path, err = project:getAssetReference(reference)
    if not path then return nil, err end
    if path:match("^Assets/.+%.prefab$") then
        local file, fileError = project:resolveAssetFile(reference)
        if not file then return nil, fileError end
        return path, "prefab"
    end
    if path:match("^Sources/.+%.lua$") then
        local kind, kindError = project:getScriptKind(reference)
        if kind ~= "lobject" then return nil, kindError or "Expected an LObject Lua Class" end
        local file, fileError = project:resolveSourceFile(reference)
        if not file then return nil, fileError end
        return path, "lua"
    end
    return nil, "Expected an LObject Lua Class or Prefab"
end
function Template.resolve(project, reference, loadClass)
    local path, kind = Template.source(project, reference)
    if not path then return nil, kind end
    local definition, err = Definition.resolve(project, reference, loadClass)
    if not definition then return nil, err end
    local hierarchy, hierarchyError = require("project.PrefabHierarchy").resolve(project, reference, loadClass)
    if not hierarchy then return nil, hierarchyError end
    -- Lua 클래스는 디스크 Prefab 없이 기본 생성 정의를 가진다. 실제 객체는 매번 새로 구성한다.
    return {reference = project:getAssetId(path) or path, sourceKind = kind, name = path:match("([^/]+)%.[^.]+$"), definition = definition, hierarchy = hierarchy}
end
function Template.loader(project, loadClass)
    local cache = {}
    return function(reference)
        local path, err = Template.source(project, reference)
        if not path then return nil, err end
        local key = project:getAssetId(path) or path
        if cache[key] then return cache[key] end
        local template, resolveError = Template.resolve(project, key, loadClass)
        if template then cache[key] = template end
        return template, resolveError
    end
end
return Template
