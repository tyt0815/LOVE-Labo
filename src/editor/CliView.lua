local Operations = {}
function Operations.execute(project, level, request)
    assert(request.space == nil or request.space == "world" or request.space == "screen", "Expected world or screen space")
    if request.command == "level.render" and not love.window.isOpen() then
        assert(love.window.setMode(1, 1, {borderless = true, vsync = 0}))
        love.window.minimize()
    end
    return require("runtime.WorldLoader").run(project, level:toData(), nil, function(world)
        local width, height = tonumber(request.width or 1280), tonumber(request.height or 720)
        local viewport = require("core.RenderPipeline").primaryViewport(world, 0, 0, width, height)
        local result = {width = viewport.width, height = viewport.height, scale = viewport.scale,
            contentWidth = viewport.contentWidth, contentHeight = viewport.contentHeight, canvases = {}}
        result.projection, result.instances = viewport.projection, {}
        for _, object in ipairs(world.lobjects) do
            local x, y, width, height = require("core.Bounds").of(object)
            result.instances[#result.instances + 1] = {authoringId = object.authoringId, name = object.name,
                authoredTransform = require("core.Transform").toData(object.transform), worldTransform = object:getWorldTransform(),
                bounds = x and {x = x, y = y, width = width, height = height} or nil}
        end
        if request.x or request.y then
            local x, y = tonumber(request.x or 0), tonumber(request.y or 0)
            assert(require("core.Transform").finite(x) and require("core.Transform").finite(y), "Invalid coordinates")
            if request.space == "screen" then x, y = viewport:screenToWorld(x, y)
            else assert(request.space == nil or request.space == "world", "Expected world or screen space"); x, y = viewport:worldToScreen(x, y) end
            result.projected = {x = x, y = y}
        end
        result.lifecycleExecuted, result.views = true, {}
        for _, view in ipairs(require("core.Rendering").views(world)) do
            local screen = view.target == require("core.Rendering").screen
            local vp = require("core.RenderPipeline").viewport(view, 0, 0, screen and width or view.target.width, screen and height or view.target.height)
            result.views[#result.views + 1] = {id = view.id, order = view.order, target = screen and "screen" or "texture",
                width = screen and width or view.target.width, height = screen and height or view.target.height,
                projection = view:getProjection(), input = view.input,
                viewport = vp and {x = vp.x, y = vp.y, width = vp.width, height = vp.height, scale = vp.scale}}
        end
        if request.command == "level.render" then
            assert(width >= 1 and height >= 1 and width % 1 == 0 and height % 1 == 0, "Expected positive integer render dimensions")
            local output = assert(request.output, "level.render requires --output PNG path")
            assert(output:lower():match("%.png$"), "Expected PNG output")
            local canvas = love.graphics.newCanvas(width, height)
            local images = {}
            love.graphics.push("all"); love.graphics.setCanvas(canvas); love.graphics.clear(0, 0, 0, 1)
            local ok, err = pcall(require("core.RenderPipeline").draw, world, function(reference)
                if not images[reference] then images[reference] = love.graphics.newImage(love.filesystem.newFileData(assert(project:readAsset(reference)), reference)) end
                return images[reference]
            end, 0, 0, width, height)
            love.graphics.pop()
            for _, image in pairs(images) do image:release() end
            if ok then
                local pixels = canvas:newImageData(); local png = pixels:encode("png")
                ok, err = require("editor.HostFileSystem").writeAtomic(output, png:getString())
                png:release(); pixels:release()
            end
            canvas:release(); assert(ok, err)
            result.output = output
        end
        return result
    end)
end
return Operations
