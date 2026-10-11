local Operations = {}
function Operations.execute(project, level, request)
    assert(request.space == nil or request.space == "world" or request.space == "screen", "Expected world or screen space")
    local world = assert(require("runtime.WorldLoader").prepare(project, level:toData()))
    local viewport = require("core.Viewport").new(world, 0, 0, tonumber(request.width or 1280), tonumber(request.height or 720))
    local result = {width = viewport.width, height = viewport.height, scale = viewport.scale,
        contentWidth = viewport.contentWidth, contentHeight = viewport.contentHeight, canvases = {}}
    if viewport.camera then
        local camera = viewport.camera
        local width, height = camera:getViewSize()
        result.camera = {authoringId = camera.owner.authoringId, script = camera.name,
            transform = camera:getViewTransform(), viewWidth = width, viewHeight = height}
    end
    for _, object in ipairs(world.lobjects) do
        for _, name in ipairs(object:getScriptOrder()) do
            local script = object.scripts[name]
            if script.canvas then
                local x, y, width, height = script:getBounds({viewport = viewport})
                result.canvases[#result.canvases + 1] = {authoringId = object.authoringId, script = name,
                    x = x, y = y, width = width, height = height}
            end
        end
    end
    if request.x or request.y then
        local x, y = tonumber(request.x or 0), tonumber(request.y or 0)
        assert(require("core.Transform").finite(x) and require("core.Transform").finite(y), "Invalid coordinates")
        if request.space == "screen" then x, y = viewport:screenToWorld(x, y)
        else assert(request.space == nil or request.space == "world", "Expected world or screen space"); x, y = viewport:worldToScreen(x, y) end
        result.projected = {x = x, y = y}
    end
    return result
end
return Operations
