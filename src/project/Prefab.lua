local Json = require("project.Json")
local Level = {isValidScriptReference = require("project.Reference").validScript}
local Prefab = {}

function Prefab.decode(text)
    local data, err = Json.decode(text)
    if type(data) ~= "table" then return nil, err or "Prefab must be an object" end
    if data.formatVersion ~= 1 and data.formatVersion ~= 2 and data.formatVersion ~= 3 then return nil, "Unsupported Prefab format" end
    local valid, referenceError = Level.isValidScriptReference(data.definitionReference)
    if not valid then return nil, referenceError end
    if type(data.overrides) ~= "table" then return nil, "Prefab overrides must be an object" end
    local properties, propertyError = require("project.PropertyData").validate(data.overrides.properties)
    if not properties then return nil, propertyError end
    local components, componentError = require("project.PropertyData").validateComponents(data.overrides.components)
    if not components then return nil, componentError end
    local function removed(paths)
        if paths == nil then return true end
        if type(paths) ~= "table" then return nil, "Invalid removed Prefab paths" end
        for _, path in ipairs(paths) do
            if type(path) ~= "string" or path:sub(1, 5) ~= "root/" or path:find("[^%w_/%-]") then return nil, "Invalid removed Prefab path" end
        end
        return true
    end
    local function children(nodes, depth)
        if nodes == nil then return true end
        if type(nodes) ~= "table" or depth > 64 then return nil, "Invalid Prefab children" end
        local ids = {}
        for _, node in ipairs(nodes) do
            if type(node) ~= "table" or type(node.id) ~= "string" or not node.id:match("^[%w_%-]+$") or ids[node.id] then return nil, "Invalid or duplicate Prefab child ID" end
            ids[node.id] = true
            if node.definitionReference then
                local valid, err = Level.isValidScriptReference(node.definitionReference)
                if not valid then return nil, err end
            end
            if node.transform then
                if type(node.transform) ~= "table" then return nil, "Invalid child Transform overrides" end
                local values = {x = 0, y = 0}
                for field, value in pairs(node.transform) do
                    if not require("core.Transform").FIELDS[field] then return nil, "Invalid child Transform field" end
                    values[field] = value
                end
                local transform, err = require("core.Transform").copy(values)
                if not transform then return nil, err end
            end
            if node.name ~= nil and type(node.name) ~= "string" then return nil, "Invalid Prefab child name" end
            if node.overrides ~= nil and type(node.overrides) ~= "table" then return nil, "Invalid Prefab child overrides" end
            if node.overrides then
                local valid, err = require("project.PropertyData").validate(node.overrides.properties)
                if not valid then return nil, err end
                valid, err = require("project.PropertyData").validateComponents(node.overrides.components)
                if not valid then return nil, err end
            end
            local valid, err = removed(node.removedPaths)
            if not valid then return nil, err end
            local valid, err = children(node.children, depth + 1)
            if not valid then return nil, err end
        end
        return true
    end
    local valid, childError = children(data.children, 0)
    if not valid then return nil, childError end
    local valid, removedError = removed(data.removedPaths)
    if not valid then return nil, removedError end
    if data.bindings ~= nil then
        if type(data.bindings) ~= "table" then return nil, "Invalid Prefab bindings" end
        for _, binding in ipairs(data.bindings) do
            if type(binding) ~= "table" or type(binding.from) ~= "string" or type(binding.to) ~= "string"
                or not binding.from:match("^root") or not binding.to:match("^root") or type(binding.property) ~= "string" then return nil, "Invalid Prefab binding" end
        end
    end
    return data
end

function Prefab.encodeData(data)
    local text, err = Json.encode(data, true)
    if not text then return nil, err end
    local valid, validationError = Prefab.decode(text)
    if not valid then return nil, validationError end
    return text .. "\n"
end

function Prefab.encode(definitionReference)
    local valid, err = Level.isValidScriptReference(definitionReference)
    if not valid then return nil, err end
    -- Definition의 데이터 변형을 위한 에셋이다. 빈 override는 원본 값을 유지한다.
    return Prefab.encodeData({ formatVersion = 2,
        definitionReference = definitionReference, overrides = {} })
end

return Prefab
