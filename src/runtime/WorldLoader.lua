local Loader = {}
local LuaScript = require("project.LuaScript")
local Definition = require("project.ObjectDefinition")

function Loader.bind(project, data, world, loadClass)
    loadClass = loadClass or LuaScript.loader(project)
    local initial, byId, dataById = {}, {}, {}
    for i, object in ipairs(world.lobjects) do initial[i] = object; byId[object.authoringId] = object end
    local authored = {}
    for i, source in ipairs(data.lobjects) do
        dataById[source.authoringId] = source
        if source.prefabRootId then
            authored[source.prefabRootId] = authored[source.prefabRootId] or {}
            authored[source.prefabRootId][source.prefabNodePath] = {object = initial[i], data = source}
        end
    end
    local Hierarchy = require("project.PrefabHierarchy")
    local recipes, removed = {}, {}
    local function removeBranch(object)
        if removed[object] then return end
        removed[object] = true
        for _, child in ipairs(object.children) do removeBranch(child) end
    end
    -- 저장된 구체화 노드를 최신 생성 정의와 대조하고 사라진 가지는 초기화 전에 제거한다.
    for rootId, members in pairs(authored) do
        local source = dataById[rootId]
        if not source then return false, "Missing Prefab root instance" end
        local recipe, err = Hierarchy.resolve(project, source.definitionReference, loadClass)
        if not recipe then return false, err end
        recipes[rootId] = recipe
        for path, member in pairs(members) do
            if member.object ~= byId[rootId] and (not recipe.byPath[path] or Hierarchy.isRemoved(path, source.prefabRemovedPaths)) then
                removeBranch(member.object)
            end
        end
    end
    for index = #world.lobjects, 1, -1 do
        local object = world.lobjects[index]
        if removed[object] then
            object:attachTo(nil)
            byId[object.authoringId] = nil
            table.remove(world.lobjects, index)
        end
    end
    for i, source in ipairs(data.lobjects) do
        if not removed[initial[i]] and (not source.prefabRootId or source.prefabRootId == source.authoringId) then
            local recipe, err = recipes[source.authoringId]
            if not recipe then recipe, err = Hierarchy.resolve(project, source.definitionReference, loadClass) end
            if not recipe then return false, err end
            local objects, configureError = require("runtime.TemplateObjects").configure(world, recipe, initial[i],
                {attachments = source.scripts, properties = source.propertyOverrides, scripts = source.scriptOverrides, removedPaths = source.prefabRemovedPaths}, authored[source.authoringId])
            if not objects then return false, configureError end
        end
    end
    local ok, err = Definition.resolveReferences(world.properties, world.levelPropertySchema, byId, project)
    if not ok then return false, err end
    local valid, referenceError = require("runtime.TemplateObjects").resolveReferences(project, world)
    if not valid then return false, referenceError end
    local hosts = {world}
    if world.project and not world.project.hasLoaded then hosts[#hosts + 1] = world.project end
    for _, host in ipairs(hosts) do
        for _, id in ipairs(host.scriptOrder) do
            local script = host.scripts[id]
            local resolved, resolveError = Definition.resolveReferences(script.properties, getmetatable(script).properties, byId, project)
            if not resolved then return false, resolveError end
        end
    end
    local complete = require("core.ScriptOrder").objects(world.lobjects)
    return true, complete, loadClass
end

-- 검증 단계에서는 build·참조 해석까지만 수행하고 load를 실행하지 않는다.
function Loader.prepare(project, data, session)
    local _, cameraError = require("project.MainCamera").copy(type(data) == "table" and data.mainCamera)
    if cameraError then return nil, cameraError end
    if type(data) == "table" and data.mainCamera then return nil, "Legacy mainCamera: run project.migrate-rendering before Play or Export" end
    local world, err = require("core.World").fromLevelData(data)
    if not world then return nil, err end
    world.assetDataLoader = function(reference) return require("project.AssetData").read(project, reference) end
    -- 레벨의 require와 부착·Spawn이 같은 클래스 테이블을 사용한다.
    local loadClass = session and session.scriptLoader or LuaScript.loader(project)
    if not session then
        session = require("core.ScriptHost").new("project")
        session.scriptLoader = loadClass
        local configured, configureError = require("project.ScopedScripts").configure(session, project or {}, loadClass)
        if not configured then return nil, configureError end
    end
    world.project = session
    local configured, configureError = require("project.ScopedScripts").configure(world, data, loadClass)
    if not configured then return nil, configureError end
    local class
    if data.scriptReference then
        if not project then return nil, "Level script requires a project" end
        class, err = loadClass(data.scriptReference, "level")
        if not class then return nil, err end
    end
    world.properties, err = LuaScript.values(class, data.propertyOverrides)
    if not world.properties then return nil, err end
    world.levelPropertySchema = class and class.properties
    local ok, initial = Loader.bind(project, data, world, loadClass)
    if not ok then return nil, initial end
    return world, class, initial, loadClass
end

function Loader.activate(project, world, class, initial, loadClass)
    local session, previous = world.project, world.project and world.project.world
    if session then session.world = world end
    local function fail(err)
        local ok, cleanupError = world:dispose(previous ~= nil)
        if previous then session.world = previous end
        return nil, tostring(err) .. (not ok and "\n" .. tostring(cleanupError) or "")
    end
    require("runtime.PrefabSpawner").bind(project, world, loadClass)
    require("runtime.LevelTransition").bind(project, world)
    if session and not session.hasLoaded then
        local ok, err = session:load(world)
        if not ok then return fail(err) end
    end
    local loaded, loadError = require("core.ScriptHost").load(world, world)
    if not loaded then return fail(loadError) end
    for _, object in ipairs(initial) do
        if object.world == world then
            local ok, err = object:load(world)
            if not ok then return fail(err) end
        end
    end
    if class then
        local ok, err = world:setLevelScript(class)
        if not ok then return fail(err) end
    end
    return world
end
function Loader.create(project, data, debugSession)
    local world, class, initial, loadClass = Loader.prepare(project, data)
    if not world then return nil, class end
    if debugSession then world.debug = debugSession end
    return Loader.activate(project, world, class, initial, loadClass)
end
-- CLI처럼 실행 결과만 읽는 임시 세션은 실패 경로에서도 반드시 정리한다.
function Loader.run(project, data, debugSession, callback)
    local world = assert(Loader.create(project, data, debugSession))
    local ok, result = pcall(callback, world, function(current) world = current end)
    local cleaned, cleanupError = world:dispose()
    assert(ok, tostring(result) .. (not cleaned and "\n" .. tostring(cleanupError) or ""))
    assert(cleaned, cleanupError)
    return result
end
return Loader
