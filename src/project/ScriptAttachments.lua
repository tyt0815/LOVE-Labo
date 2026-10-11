local Attachments = {}
function Attachments.validateIds(list)
    if list == nil then return true end
    if type(list) ~= "table" then return nil, "Script IDs must be a list" end
    local seen = {}
    for key, id in pairs(list) do
        if type(key) ~= "number" or key < 1 or key % 1 ~= 0 or key > #list
            or type(id) ~= "string" or not id:match("^[%a_][%w_]*$") or seen[id] then
            return nil, "Invalid or duplicate script ID list"
        end
        seen[id] = true
    end
    return true
end
function Attachments.copy(list)
    local result = {}
    for _, item in ipairs(list or {}) do
        result[#result + 1] = {id = item.id, source = item.source, label = item.label}
    end
    return result
end
function Attachments.validate(list)
    if list == nil then return {} end
    if type(list) ~= "table" then return nil, "Scripts must be a list" end
    local ids = {}
    for key, item in pairs(list) do
        if type(key) ~= "number" or key < 1 or key % 1 ~= 0 or key > #list then return nil, "Scripts must be a dense list" end
        if type(item) ~= "table" or type(item.id) ~= "string" or not item.id:match("^[%a_][%w_]*$") or ids[item.id]
            or type(item.source) ~= "string" or item.source == "" or item.label ~= nil and type(item.label) ~= "string" then
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
        if not removedIds[item.id] then result[#result + 1] = {id = item.id, source = item.source, label = item.label}; byId[item.id] = #result end
    end
    for _, item in ipairs(localList or {}) do
        local copy = {id = item.id, source = item.source, label = item.label}
        if byId[item.id] then result[byId[item.id]] = copy
        else result[#result + 1] = copy; byId[item.id] = #result end
    end
    return result
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
