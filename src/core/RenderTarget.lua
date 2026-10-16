local Transform = require("core.Transform")
local Target = {}
Target.__index = Target
local function size(width, height)
    assert(Transform.finite(width) and Transform.finite(height) and width >= 1 and height >= 1
        and width % 1 == 0 and height % 1 == 0, "Render target size must be positive integers")
end
function Target.new(world, options)
    size(options.width, options.height)
    assert(not options.owner or options.owner:getWorld() == world, "Render target owner must belong to this World")
    local self = setmetatable({world = world, owner = options.owner, width = options.width, height = options.height}, Target)
    world.renderTargets = world.renderTargets or {}
    world.renderTargets[#world.renderTargets + 1] = self
    return self
end
function Target:getTexture()
    assert(not self.released and not self.world.disposed, "Render target is released")
    assert(not self.writing, "Cannot sample the render target currently being written")
    -- CLI의 load·update 검증은 그래픽 컨텍스트 없이도 타깃을 생성할 수 있다.
    if not self.texture then self.texture = love.graphics.newCanvas(self.width, self.height) end
    return self.texture
end
function Target:resize(width, height)
    size(width, height)
    assert(not self.released and not self.world.disposed and not self.writing, "Render target is unavailable")
    if self.width == width and self.height == height then return end
    if self.texture then self.texture:release(); self.texture = nil end
    self.width, self.height = width, height
end
function Target:release()
    assert(not self.transferPending, "Render target is being transferred")
    assert(not self.writing, "Cannot release a render target during rendering")
    if self.released then return end
    if self.texture then self.texture:release(); self.texture = nil end
    self.released = true
    for index, target in ipairs(self.world.renderTargets) do
        if target == self then table.remove(self.world.renderTargets, index); break end
    end
end
return Target
