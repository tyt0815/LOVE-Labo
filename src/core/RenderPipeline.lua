local Rendering = require("core.Rendering")
local Viewport = require("core.Viewport")
local Pipeline = {}
function Pipeline.viewport(view, x, y, width, height)
    local rect = view.viewport
    if rect then
        if rect.x >= width or rect.y >= height then return nil end
        x, y, width, height = x + rect.x, y + rect.y, math.min(rect.width, width - rect.x), math.min(rect.height, height - rect.y)
    end
    local viewport = Viewport.new(view.world, x, y, width, height, view)
    viewport.outputRect = {x = x, y = y, width = width, height = height}
    return viewport
end
function Pipeline.primaryViewport(world, x, y, width, height)
    local views = Rendering.views(world)
    for index = #views, 1, -1 do
        local view = views[index]
        if view.target == Rendering.screen then
            local viewport = Pipeline.viewport(view, x, y, width, height)
            if viewport then return viewport end
        end
    end
    return Viewport.new(nil, x, y, width, height)
end
function Pipeline.draw(world, image, x, y, width, height)
    local drawn = {}
    for _, view in ipairs(Rendering.views(world)) do
        if view:isActive() then
            local target = view.target
            local screen = target == Rendering.screen
            local texture = not screen and target:getTexture()
            local viewport = Pipeline.viewport(view, screen and x or 0, screen and y or 0,
                screen and width or target.width, screen and height or target.height)
            if viewport then
                love.graphics.push("all")
                if texture then love.graphics.setCanvas(texture); target.writing = true end
                local ok, result = pcall(function()
                    love.graphics.origin()
                    local rect = viewport.outputRect
                    -- 타깃 전환 후에는 에디터 패널의 scissor가 텍스처 출력을 자르지 않아야 한다.
                    love.graphics.setScissor(rect.x, rect.y, rect.width, rect.height)
                    if view.clearColor then
                        love.graphics.setBlendMode("replace")
                        love.graphics.setColor(unpack(view.clearColor))
                        love.graphics.rectangle("fill", rect.x, rect.y, rect.width, rect.height)
                        love.graphics.setBlendMode("alpha")
                    end
                    love.graphics.setColor(1, 1, 1, 1)
                    return require("core.Renderer").drawWorld(world, image, viewport)
                end)
                if texture then target.writing = nil end
                love.graphics.pop()
                assert(ok, result)
                for object, value in pairs(result) do drawn[object] = drawn[object] or value end
            end
        end
    end
    return drawn
end
function Pipeline.captureButton(world, button)
    for _, view in ipairs(Rendering.views(world)) do
        if view.target == Rendering.screen and view.input then
            for id, region in pairs(view.pointerCaptures) do
                if not region:isActive() then view.pointerCaptures[id] = nil
                elseif not button or id == button then return id end
            end
        end
    end
end
function Pipeline.pointer(world, kind, x, y, button, dx, dy, image, rect)
    local views = Rendering.views(world)
    local combined = {consumed = false, targets = {}}
    local function captured(view)
        return kind == "move" and next(view.pointerCaptures) ~= nil or kind == "up" and view.pointerCaptures[button or 1] ~= nil
    end
    local routeCapture = false
    for _, view in ipairs(views) do
        if view.target == Rendering.screen and view.input and captured(view) then routeCapture = true end
    end
    for index = #views, 1, -1 do
        local view = views[index]
        if view:isActive() and view.target == Rendering.screen and view.input and (not routeCapture or captured(view)) then
            local viewport = Pipeline.viewport(view, rect.x, rect.y, rect.width, rect.height)
            local captured = captured(view)
            if viewport and (captured or viewport:containsWorldScreen(x, y)) then
                local previous = world.pointerCaptures
                world.pointerCaptures = view.pointerCaptures
                local ok, result = viewport:dispatchPointer(world, kind, x, y, button, dx, dy, image)
                view.pointerCaptures, world.pointerCaptures = world.pointerCaptures, previous
                if not ok then return false, result end
                for _, target in ipairs(result.targets) do combined.targets[#combined.targets + 1] = target end
                combined.consumed = combined.consumed or result.consumed
                if combined.consumed and not captured then break end
            end
        end
    end
    return true, combined
end
return Pipeline
