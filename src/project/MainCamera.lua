local MainCamera = {}
function MainCamera.copy(value)
    if value == nil or value == false then return nil end
    if type(value) ~= "table" or type(value.authoringId) ~= "number" or value.authoringId < 1
        or value.authoringId % 1 ~= 0 or type(value.component) ~= "string" or value.component == "" then
        return nil, "Main Camera requires an instance ID and component name"
    end
    return {authoringId = value.authoringId, component = value.component}
end
function MainCamera.resolve(world, value)
    if not value then return end
    for _, object in ipairs(world.lobjects) do
        if object.authoringId == value.authoringId then
            local component = object.components[value.component]
            if component and component:isA(require("core.CameraComponent")) then return component end
        end
    end
end
function MainCamera.choices(project, level, object)
    if not object or level:findLObject(object.authoringId) ~= object then return nil, "Select an instance in the current level" end
    local definition, err = require("project.PrefabHierarchy").authoringDefinition(project, level, object)
    if not definition then return nil, err end
    local preview = assert(require("core.LObject").new(1, object))
    local ok, configureError = require("project.ObjectDefinition").configure(preview, definition, object.propertyOverrides, object.componentOverrides)
    if not ok then return nil, configureError end
    local result = {}
    for _, name in ipairs(preview:getComponentOrder()) do
        if preview.components[name]:isA(require("core.CameraComponent")) then
            result[#result + 1] = {authoringId = object.authoringId, component = name}
        end
    end
    if #result == 0 then return nil, "Selected instance has no CameraComponent" end
    return result
end
return MainCamera
