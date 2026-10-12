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
    local complete = require("core.ScriptOrder").objects(world.lobjects)
    return true, complete, loadClass
end

-- 검증 단계에서는 build·참조 해석까지만 수행하고 beginPlay를 실행하지 않는다.
function Loader.prepare(project, data)
    local _, cameraError = require("project.MainCamera").copy(type(data) == "table" and data.mainCamera)
    if cameraError then return nil, cameraError end
    local world, err = require("core.World").fromLevelData(data)
    if not world then return nil, err end
    -- 레벨의 require와 부착·Spawn이 같은 클래스 테이블을 사용한다.
    local loadClass = LuaScript.loader(project)
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
    local camera = require("project.MainCamera").resolve(world, data.mainCamera)
    if camera then assert(world:setActiveCamera(camera)) end
    return world, class, initial, loadClass
end

function Loader.activate(project, world, class, initial, loadClass)
    require("runtime.PrefabSpawner").bind(project, world, loadClass)
    require("runtime.LevelTransition").bind(project, world)
    for _, object in ipairs(initial) do
        if object.world == world then
            local ok, err = object:beginPlay(world)
            if not ok then return nil, err end
        end
    end
    if class then
        local ok, err = world:setLevelScript(class)
        if not ok then return nil, err end
    end
    return world
end
function Loader.create(project, data, debugSession)
    local world, class, initial, loadClass = Loader.prepare(project, data)
    if not world then return nil, class end
    if debugSession then world.debug = debugSession end
    return Loader.activate(project, world, class, initial, loadClass)
end
return Loader
