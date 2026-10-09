local Definition = require("project.ObjectDefinition")
local Hierarchy = require("project.PrefabHierarchy")
local Objects = {}

function Objects.configure(world, recipe, root, rootOverrides, authored)
    local objects, overridden = {root = root}, {}
    for _, node in ipairs(recipe.nodes) do
        if not Hierarchy.isRemoved(node.path, rootOverrides.removedPaths) then
        local source = authored and authored[node.path]
        local object = node.parent and source and source.object or not node.parent and root
        if not object then
            object = assert(world:addLObject({transform = node.transform, definitionReference = node.reference}))
            object.name = node.name or "LObject"
            object:attachTo(objects[node.parent.path])
        end
        objects[node.path] = object
        local extra = node.parent and source and {properties = source.data.propertyOverrides, components = source.data.componentOverrides}
            or not node.parent and rootOverrides or {}
        local properties, components = Hierarchy.copy(node.overrides.properties or {}), Hierarchy.copy(node.overrides.components or {})
        overridden[node.path] = {}
        for name, value in pairs(extra.properties or {}) do properties[name] = value; overridden[node.path][name] = true end
        for name, fields in pairs(extra.components or {}) do
            components[name] = components[name] or {}
            for field, value in pairs(fields) do components[name][field] = value; overridden[node.path][name .. "." .. field] = true end
        end
        local ok, err = Definition.configure(object, node.definition, properties, components)
        if not ok then return nil, err end
        end
    end
    local valid, err = Hierarchy.applyBindings(recipe, objects, overridden)
    if not valid then return nil, err end
    return objects
end

function Objects.resolveReferences(project, world)
    local byId = {}
    for _, object in ipairs(world.lobjects) do
        if object.authoringId then byId[object.authoringId] = object end
        byId["runtime:" .. object.runtimeId] = object
    end
    for _, object in ipairs(world.lobjects) do
        local ok, err = Definition.resolveReferences(object.properties, object.luaClass and object.luaClass.properties, byId, project)
        if not ok then return false, err end
        for _, name in ipairs(object.componentOrder) do
            local component = object.components[name]
            ok, err = Definition.resolveReferences(component.properties, getmetatable(component).properties, byId, project)
            if not ok then return false, err end
        end
    end
    return true, byId
end
return Objects
