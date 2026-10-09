local Loader = {}
local LuaClass = require("project.LuaClass")
local Definition = require("project.ObjectDefinition")

function Loader.bind(project, data, world)
    local loadClass = LuaClass.loader(project)
    local initial, byId = {}, {}
    for i, object in ipairs(world.lobjects) do initial[i] = object; byId[object.authoringId] = object end
    for i, source in ipairs(data.lobjects) do
        local definition, err = Definition.resolve(project, source.definitionReference, loadClass)
        if not definition then return false, err end
        local ok, configureError = Definition.configure(initial[i], definition, source.propertyOverrides, source.componentOverrides)
        if not ok then return false, configureError end
    end
    local ok, err = Definition.resolveReferences(world.properties, world.levelPropertySchema, byId, project)
    if not ok then return false, err end
    for _, object in ipairs(initial) do
        local valid, referenceError = Definition.resolveReferences(object.properties, object.luaClass and object.luaClass.properties, byId, project)
        if not valid then return false, referenceError end
        for _, name in ipairs(object.componentOrder) do
            local component = object.components[name]
            local resolved, fieldError = Definition.resolveReferences(component.properties, getmetatable(component).properties, byId, project)
            if not resolved then return false, fieldError end
        end
    end
    return true, initial, loadClass
end

-- 검증 단계에서는 build·참조 해석까지만 수행하고 beginPlay를 실행하지 않는다.
function Loader.prepare(project, data)
    local world, err = require("core.World").fromLevelData(data)
    if not world then return nil, err end
    local class
    if data.scriptReference then
        if not project then return nil, "Level script requires a project" end
        class, err = LuaClass.load(project, data.scriptReference, "level")
        if not class then return nil, err end
    end
    world.properties, err = LuaClass.values(class, data.propertyOverrides)
    if not world.properties then return nil, err end
    world.levelPropertySchema = class and class.properties
    local ok, initial, loadClass = Loader.bind(project, data, world)
    if not ok then return nil, initial end
    return world, class, initial, loadClass
end

function Loader.create(project, data)
    local world, class, initial, loadClass = Loader.prepare(project, data)
    if not world then return nil, class end
    require("runtime.PrefabSpawner").bind(project, world, loadClass)
    for _, object in ipairs(initial) do
        local ok, err = object:beginPlay(world)
        if not ok then return nil, err end
    end
    if class then
        local ok, err = world:setLevelScript(class)
        if not ok then return nil, err end
    end
    return world
end
return Loader
