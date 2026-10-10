local Transform = require("core.Transform")
local Space = {}
function Space.parent(component)
    return component.parent or component.owner and component.owner.parent and component.owner.parent.rootComponent
end
function Space.canvas(component)
    while component do
        if component:isA(require("core.CanvasComponent")) then return component end
        component = Space.parent(component)
    end
end
function Space.transform(component)
    local path, current = {}, component
    while current do
        path[#path + 1] = current
        if current:isA(require("core.CanvasComponent")) then
            local result = current.transform
            for index = #path - 1, 1, -1 do
                if path[index].transform then result = Transform.compose(result, path[index].transform) end
            end
            return result
        end
        current = Space.parent(current)
    end
    return component:getWorldTransform()
end
return Space
