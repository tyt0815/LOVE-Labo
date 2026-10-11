local Transform = require("core.Transform")
local Space = {}
function Space.canvas(script)
    local object = script.owner
    while object do
        for _, id in ipairs(object.scriptOrder) do if object.scripts[id].canvas then return object.scripts[id] end end
        object = object.parent
    end
end
function Space.transform(script)
    local canvas = Space.canvas(script)
    if not canvas then return script.owner:getWorldTransform() end
    local path, object = {}, script.owner
    while object ~= canvas.owner do path[#path + 1] = object; object = object.parent end
    local result = canvas.owner.transform
    for index = #path, 1, -1 do result = Transform.compose(result, path[index].transform) end
    return result
end
return Space
