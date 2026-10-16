local Bindings = require("core.Bindings")
local Input = {}
function Input.registerRegion(world, options)
    assert(world and not world.disposed and type(options) == "table", "Expected live World and input options")
    assert(options.owner and options.owner:getWorld() == world and type(options.hitTest) == "function", "Input region requires an owner and hitTest")
    for _, name in ipairs({"onDown", "onUp", "onMove", "filterSource"}) do
        assert(options[name] == nil or type(options[name]) == "function", "Input callback must be a function: " .. name)
    end
    for _, name in ipairs({"order", "priority"}) do
        assert(options[name] == nil or type(options[name]) == "function" or require("core.Transform").finite(options[name]), "Invalid input order")
    end
    assert(options.block == nil or type(options.block) == "boolean" or type(options.block) == "function", "Invalid input block option")
    local region = {world = world, owner = options.owner, hitTest = options.hitTest,
        onDown = options.onDown, onUp = options.onUp, onMove = options.onMove,
        order = options.order or function() return options.owner.drawOrder end, priority = options.priority or 0, block = options.block or false,
        filterSource = options.filterSource or function() return options.owner end}
    world.inputRegions = world.inputRegions or {}; world.nextRegionId = (world.nextRegionId or 0) + 1
    region.id = world.nextRegionId; world.inputRegions[#world.inputRegions + 1] = region
    local handle = Bindings.add(options.owner, function()
        assert(not region.transferPending, "Input region is being transferred")
        local world = region.world
        region.released = true
        for index, value in ipairs(world.inputRegions) do if value == region then table.remove(world.inputRegions, index); break end end
        for button, value in pairs(world.pointerCaptures or {}) do if value == region then world.pointerCaptures[button] = nil end end
        for _, view in ipairs(world.renderViews or {}) do
            for button, value in pairs(view.pointerCaptures) do if value == region then view.pointerCaptures[button] = nil end end
        end
    end)
    region.release = function() assert(not region.transferPending, "Input region is being transferred"); handle:release() end
    function region:isActive() return not self.released and not self.world.disposed and Bindings.live(self.owner) and self.owner:getWorld() == self.world end
    return region
end
function Input.value(region, name)
    local value = region[name]
    if type(value) == "function" then value = value() end
    if name == "block" then assert(type(value) == "boolean", "Input block provider must return a boolean")
    else assert(require("core.Transform").finite(value), "Input order provider must return a finite number") end
    return value
end
return Input
