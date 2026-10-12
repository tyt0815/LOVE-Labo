local Attachments = {}
function Attachments.validateIds(list)
    if list == nil then return true end
    if type(list) ~= "table" then return nil, "Script IDs must be a list" end
    local seen = {}
    for key, id in pairs(list) do
        if type(key) ~= "number" or key < 1 or key % 1 ~= 0 or key > #list
            or not require("core.ScriptId").isValid(id) or seen[id] then
            return nil, "Invalid or duplicate script ID list"
        end
        seen[id] = true
    end
    return true
end
function Attachments.copy(list)
    local result = {}
    for _, item in ipairs(list or {}) do
        result[#result + 1] = {id = item.id, source = item.source, name = item.name or item.label or item.id}
    end
    return result
end
function Attachments.validate(list)
    if list == nil then return {} end
    if type(list) ~= "table" then return nil, "Scripts must be a list" end
    local ids = {}
    for key, item in pairs(list) do
        if type(key) ~= "number" or key < 1 or key % 1 ~= 0 or key > #list then return nil, "Scripts must be a dense list" end
        if type(item) ~= "table" or not require("core.ScriptId").isValid(item.id) or ids[item.id]
            or item.source ~= nil and (type(item.source) ~= "string" or item.source == "")
            or item.source == nil and item.name == nil and item.label == nil
            or item.name ~= nil and (type(item.name) ~= "string" or item.name == "")
            or item.label ~= nil and type(item.label) ~= "string" then
            return nil, "Invalid or duplicate script attachment"
        end
        ids[item.id] = true
    end
    return Attachments.copy(list)
end
function Attachments.merge(base, localList, removed)
    local result, byId, removedIds = {}, {}, {}
    for _, id in ipairs(removed or {}) do removedIds[id] = true end
    for _, item in ipairs(base or {}) do
        if not removedIds[item.id] then result[#result + 1] = {id = item.id, source = item.source, name = item.name or item.label or item.id}; byId[item.id] = #result end
    end
    for _, item in ipairs(localList or {}) do
        local inherited = byId[item.id] and result[byId[item.id]]
        local copy = {id = item.id, source = item.source or inherited and inherited.source, name = item.name or item.label or inherited and inherited.name or item.id}
        if byId[item.id] then result[byId[item.id]] = copy
        else result[#result + 1] = copy; byId[item.id] = #result end
    end
    return result
end
function Attachments.find(list, query)
    for _, item in ipairs(list or {}) do if item.id == query then return item end end
    for _, item in ipairs(list or {}) do if (item.name or item.label or item.id) == query then return item end end
end
function Attachments.reidentify(list)
    local result, ids = Attachments.copy(list), {}
    for _, item in ipairs(result) do
        if item.source then
            local old = item.id
            item.id = require("project.AssetId").new()
            ids[old], ids[item.name] = item.id, item.id
        end
    end
    return result, ids
end
function Attachments.uniqueName(list, name, except)
    if type(name) ~= "string" or name:match("^%s*$") or name:find("%c") then return false, "Enter a script name" end
    for _, item in ipairs(list or {}) do
        if item.id ~= except and (item.name or item.label or item.id) == name then return false, "Script name already exists" end
    end
    return true
end
function Attachments.reorder(list, order)
    if not order then return list end
    local result, byId = {}, {}
    for _, item in ipairs(list) do byId[item.id] = item end
    for _, id in ipairs(order) do if byId[id] then result[#result + 1] = byId[id]; byId[id] = nil end end
    for _, item in ipairs(list) do if byId[item.id] then result[#result + 1] = item end end
    return result
end
return Attachments
