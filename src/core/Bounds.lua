local Transform = require("core.Transform")
local Bindings = require("core.Bindings")
local Bounds = {}
function Bounds.bind(owner, provider, options)
    assert(type(provider) == "function", "Bounds provider must be a function")
    assert(not owner.boundsBinding or owner.boundsBinding.released, "Script already has a bounds binding")
    local binding = {owner = owner, provider = provider}
    owner.boundsBinding = binding
    if options and options.primary then
        local object = assert(owner.owner)
        assert(not object.boundsBinding or object.boundsBinding.released, "Object already has primary bounds")
        object.boundsBinding = binding
    end
    return Bindings.add(owner, function() binding.released = true end)
end
local function evaluate(binding, context)
    if binding and not binding.released and Bindings.live(binding.owner) then
        assert(not binding.evaluating, "Cyclic bounds binding")
        binding.evaluating = true
        local result = {pcall(binding.provider, context)}
        binding.evaluating = nil
        assert(result[1], result[2])
        local x, y, width, height = unpack(result, 2, 5)
        if x == nil then return end
        assert(Transform.finite(x) and Transform.finite(y) and Transform.finite(width) and Transform.finite(height)
            and width >= 0 and height >= 0, "Invalid script bounds")
        return x, y, width, height
    end
end
function Bounds.of(object, context) return evaluate(object and object.boundsBinding, context) end
function Bounds.parent(object, context)
    object = object and object.parent
    while object do
        local x, y, w, h = Bounds.of(object, context)
        if x then return x, y, w, h, object end
        object = object.parent
    end
end
function Bounds.getBounds(script, context)
    if script.boundsBinding then return evaluate(script.boundsBinding, context) end
    if script.getLocalBounds then return script:getLocalBounds(context) end
end
function Bounds.hitTest(script, context, worldX, worldY)
    local world = script:getWorldTransform(context)
    local x, y = Transform.inversePoint(world, worldX, worldY)
    if not x then return false end
    local left, top, width, height = script:getBounds(context)
    if not left then return false end
    assert(Transform.finite(left) and Transform.finite(top) and Transform.finite(width) and Transform.finite(height)
        and width >= 0 and height >= 0, "Invalid script bounds")
    return width > 0 and height > 0 and x >= left and x <= left + width and y >= top and y <= top + height, x, y
end
return Bounds
