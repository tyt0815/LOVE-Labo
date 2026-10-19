local Level = require("editor.Level")
local Transform = require("core.Transform")
local Scene = {}
Scene.__index = Scene

-- 편집 UI의 식별자는 런타임 ID를 쓰며 원본의 authoringId를 변경하지 않는다.
function Scene.new(world, assets)
    local self = setmetatable({world = world, lobjects = {}, wrappers = {}, assets = assets}, Scene)
    self.spriteAssets = {
        project = assets and assets.project,
        setLevel = function() end,
        preview = function(_, object) return object.runtimeObject end,
        image = function(_, reference) return assets and assets:image(reference) end,
        scopePreview = function(_, _, kind) return kind == "project" and world.project or world end,
    }
    self:sync()
    return self
end
function Scene:sync()
    local objects, live = {}, {}
    for _, object in ipairs(self.world.lobjects) do
        local wrapper = self.wrappers[object] or {runtimeObject = object, authoringId = object.runtimeId}
        self.wrappers[object], live[object] = wrapper, true
        wrapper.transform, wrapper.name = object.transform, object.name or "LObject " .. object.runtimeId
        wrapper.parentAuthoringId = object.parent and object.parent.runtimeId
        objects[#objects + 1] = wrapper
    end
    for object in pairs(self.wrappers) do if not live[object] then self.wrappers[object] = nil end end
    self.lobjects = objects
end
for _, name in ipairs({"findLObject", "getParent", "getChildren", "isDescendant", "selectionRoots", "treeRows"}) do Scene[name] = Level[name] end
function Scene:getWorldTransform(object) return object.runtimeObject:getWorldTransform() end
function Scene:setWorldPosition(object, x, y)
    local runtime = object.runtimeObject
    if runtime.parent then x, y = Transform.inversePoint(runtime.parent:getWorldTransform(), x, y) end
    if not x then return false, "Parent Transform cannot be inverted" end
    local value = assert(Transform.copy(runtime.transform)); value.x, value.y = x, y
    value = Transform.unresolve(runtime, value)
    runtime.transform.x, runtime.transform.y = value.x, value.y
    return true
end
function Scene:removeLObjects(objects)
    local err
    for _, object in ipairs(self:selectionRoots(objects)) do
        local ok, message = self.world:removeLObject(object.runtimeObject)
        if not ok then err = err or message end
    end
    self:sync()
    return err == nil, err
end
function Scene:dropObjects() return false, "Runtime hierarchy reordering is not supported" end
function Scene:duplicateLObjects() return {} end

function Scene:target(object)
    local runtime, schema, types = object.runtimeObject, {}, {}
    for field in pairs(Transform.FIELDS) do
        schema["$transform." .. field] = {type = "number", default = Transform.copy({x = 0, y = 0})[field], field = field, rootTransform = true, sceneTransform = true, group = "Transform"}
    end
    for _, id in ipairs(runtime.scriptOrder) do
        local script = runtime.scripts[id]
        types[id] = script.scriptType or "Script"
        for field, declaration in pairs(getmetatable(script).properties) do
            schema[id .. "." .. field] = {type = declaration.type, default = declaration.default, script = id, field = field, group = declaration.group,
                options = declaration.options, enabledIf = require("core.PropertySchema").copyEnabledIf(declaration.enabledIf, id .. ".")}
        end
    end
    local target = {runtime = true, data = object, kind = "lobject", label = "Runtime", hideParent = true, instance = true, level = self,
        preview = runtime, class = {properties = schema, scriptTypes = types, className = "Runtime LObject"}}
    function target:getOverrides()
        local values = {}
        for name, declaration in pairs(schema) do
            local value = declaration.rootTransform and runtime.transform[declaration.field] or runtime.scripts[declaration.script].properties[declaration.field]
            if type(value) == "table" and (declaration.type == "object" or declaration.type == "script") then
                local owner = declaration.type == "script" and value.owner or value
                value = owner and (declaration.type == "script" and {authoringId = owner.runtimeId, script = value.id} or owner.runtimeId) or false
            end
            values[name] = value
        end
        return values
    end
    function target:setProperty(name, value)
        local declaration = schema[name]
        if not declaration or runtime.world ~= self.level.world then return false, "Runtime object has been removed" end
        if declaration.rootTransform then
            local transform = assert(Transform.copy(runtime.transform)); transform[declaration.field] = value
            local valid, err = Transform.copy(transform); if not valid then return false, err end
            runtime.transform[declaration.field] = valid[declaration.field]
        else
            if value ~= false and (declaration.type == "object" or declaration.type == "script") then
                local wrapper = self.level:findLObject(type(value) == "table" and value.authoringId or value)
                local owner = wrapper and wrapper.runtimeObject
                if owner and owner.world ~= self.level.world then return false, "Referenced runtime object has been removed" end
                value = owner and (declaration.type == "script" and owner.scripts[value.script] or owner)
                if not value then return false, "Referenced runtime object or script is missing" end
            end
            runtime.scripts[declaration.script][declaration.field] = value
        end
        return true
    end
    return target
end
return Scene
