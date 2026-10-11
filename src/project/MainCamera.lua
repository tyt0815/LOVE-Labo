local MainCamera = {}
function MainCamera.copy(value)
    if value == nil or value == false then return nil end
    if type(value) ~= "table" or type(value.authoringId) ~= "number" or value.authoringId < 1
        or value.authoringId % 1 ~= 0 or type(value.script) ~= "string" or value.script == "" then
        return nil, "Main Camera requires an instance ID and script name"
    end
    return {authoringId = value.authoringId, script = value.script}
end
function MainCamera.resolve(world, value)
    if not value then return end
    for _, object in ipairs(world.lobjects) do
        if object.authoringId == value.authoringId then
            local script = object.scripts[value.script]
            if script and script.camera then return script end
        end
    end
end
function MainCamera.choices(project, level, object)
    if not object or level:findLObject(object.authoringId) ~= object then return nil, "Select an instance in the current level" end
    local definition, err = require("project.PrefabHierarchy").authoringDefinition(project, level, object)
    if not definition then return nil, err end
    local preview = assert(require("core.LObject").new(1, object))
    local ok, configureError = require("project.ObjectDefinition").configure(preview, definition, object.propertyOverrides, object.scriptOverrides)
    if not ok then return nil, configureError end
    local result = {}
    for _, name in ipairs(preview:getScriptOrder()) do
        if preview.scripts[name].camera then
            result[#result + 1] = {authoringId = object.authoringId, script = name}
        end
    end
    if #result == 0 then return nil, "Selected instance has no CameraScript" end
    return result
end
return MainCamera
