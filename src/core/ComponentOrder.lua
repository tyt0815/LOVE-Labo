local Space = require("core.CoordinateSpace")
local Transform = require("core.Transform")
local Order = {}
function Order.entries(objects, class, predicate)
    local entries, indices, index = {}, {}, 0
    for _, object in ipairs(objects) do
        for _, name in ipairs(object:getComponentOrder()) do
            local component = object.components[name]
            index = index + 1; indices[component] = index
            if component:isA(class) and (not predicate or predicate(component)) then entries[#entries + 1] = {component = component, index = index, sequence = index} end
        end
    end
    for _, entry in ipairs(entries) do
        local component = entry.component
        local pointer = component:isA(require("core.PointerComponent"))
        local source = pointer and component:getBoundsSource() or component
        entry.layer = Space.canvas(source) and 1 or 0
        entry.order = source.properties.sortingOrder or 0
        entry.priority = pointer and component.properties.inputPriority or 0
        entry.index = indices[source] or entry.index
        assert(Transform.finite(entry.order) and Transform.finite(entry.priority), "Invalid component priority")
    end
    table.sort(entries, function(a, b)
        if a.layer ~= b.layer then return a.layer < b.layer end
        if a.priority ~= b.priority then return a.priority < b.priority end
        if a.order ~= b.order then return a.order < b.order end
        if a.index ~= b.index then return a.index < b.index end
        return a.sequence < b.sequence
    end)
    return entries
end
return Order
