local Json = require("project.Json")
local Level = {isValidScriptReference = require("project.Reference").validScript}
local Prefab = {}
local Array = require("core.Array")

function Prefab.decode(text)
    local data, err = Json.decode(text)
    if type(data) ~= "table" then return nil, err or "Prefab must be an object" end
    if data.formatVersion ~= 1 and data.formatVersion ~= 2 and data.formatVersion ~= 3 and data.formatVersion ~= 4 then return nil, "Unsupported Prefab format" end
    if data.formatVersion ~= 4 then return nil, "Legacy Prefab: convert to the attached-script format before opening" end
    if data.name ~= nil and (type(data.name) ~= "string" or data.name:match("^%s*$")) then return nil, "Invalid Prefab root name" end
    if data.previewBackground ~= nil then
        if data.previewBackground == Json.null or not Array.isDense(data.previewBackground) or #data.previewBackground ~= 3 then return nil, "Invalid preview RGB" end
        for _, channel in ipairs(data.previewBackground) do
            if type(channel) ~= "number" or channel ~= channel or channel < 0 or channel > 255 then return nil, "Invalid preview RGB" end
        end
    end
    local attachments, attachmentError = require("project.ScriptAttachments").validate(data.scripts)
    if not attachments then return nil, attachmentError end
    data.scripts = attachments
    local function validateRemoved(list)
        return require("project.ScriptAttachments").validateIds(list)
    end
    local validRemoved, removedError = validateRemoved(data.removedScripts)
    if not validRemoved then return nil, removedError end
    local validOrder, orderError = validateRemoved(data.scriptOrder)
    if not validOrder then return nil, orderError end
    local valid, referenceError = Level.isValidScriptReference(data.definitionReference)
    if not valid then return nil, referenceError end
    if type(data.overrides) ~= "table" then return nil, "Prefab overrides must be an object" end
    local properties, propertyError = require("project.PropertyData").validate(data.overrides.properties)
    if not properties then return nil, propertyError end
    local scripts, scriptError = require("project.PropertyData").validateScripts(data.overrides.scripts)
    if not scripts then return nil, scriptError end
    local function removed(paths, location)
        if paths == nil then return true end
        if paths == Json.null or not Array.isDense(paths) then return nil, location .. " must be a dense list" end
        for _, path in ipairs(paths) do
            if type(path) ~= "string" or path:sub(1, 5) ~= "root/" or path:find("[^%w_/%-]") then return nil, "Invalid removed Prefab path" end
        end
        return true
    end
    local function children(nodes, depth, location)
        if nodes == nil then return true end
        if nodes == Json.null or not Array.isDense(nodes) then return nil, location .. " must be a dense list" end
        if depth > 64 then return nil, "Invalid Prefab children depth: " .. location end
        local ids = {}
        for index, node in ipairs(nodes) do
            local nodePath = location .. "[" .. index .. "]"
            if type(node) ~= "table" or type(node.id) ~= "string" or not node.id:match("^[%w_%-]+$") or ids[node.id] then return nil, "Invalid or duplicate Prefab child ID" end
            ids[node.id] = true
            local scripts, scriptError = require("project.ScriptAttachments").validate(node.scripts)
            if not scripts then return nil, scriptError end
            local validRemoved, removedError = validateRemoved(node.removedScripts)
            if not validRemoved then return nil, removedError end
            local validOrder, orderError = validateRemoved(node.scriptOrder)
            if not validOrder then return nil, orderError end
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
                valid, err = require("project.PropertyData").validateScripts(node.overrides.scripts)
                if not valid then return nil, err end
            end
            local valid, err = removed(node.removedPaths, nodePath .. ".removedPaths")
            if not valid then return nil, err end
            local valid, err = children(node.children, depth + 1, nodePath .. ".children")
            if not valid then return nil, err end
        end
        return true
    end
    local valid, childError = children(data.children, 0, "children")
    if not valid then return nil, childError end
    local valid, removedError = removed(data.removedPaths, "removedPaths")
    if not valid then return nil, removedError end
    if data.bindings ~= nil then
        if data.bindings == Json.null or not Array.isDense(data.bindings) then return nil, "bindings must be a dense list" end
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
    return Prefab.encodeData({ formatVersion = 4,
        definitionReference = definitionReference, overrides = {} })
end

return Prefab
