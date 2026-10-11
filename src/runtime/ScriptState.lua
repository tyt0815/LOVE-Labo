local State = {}
function State.read(object)
    local result = {}
    for _, id in ipairs(object.scriptOrder) do
        local values = {}
        for name, value in pairs(object.scripts[id].properties) do
            if type(value) ~= "table" then values[name] = value
            elseif value.owner then values[name] = {authoringId = value.owner.authoringId, runtimeId = value.owner.runtimeId, script = value.id}
            elseif value.runtimeId then values[name] = {authoringId = value.authoringId, runtimeId = value.runtimeId} end
        end
        result[id] = values
    end
    return result
end
return State
