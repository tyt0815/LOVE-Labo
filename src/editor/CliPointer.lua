local Operations = {}
function Operations.execute(project, level, request)
    local world = assert(require("runtime.WorldLoader").create(project, level:toData()))
    local events = request.events
    if request["events-json"] then events = assert(require("project.Json").decode(request["events-json"])) end
    events = events or {{kind = request.event or "down", x = tonumber(request.x or 0), y = tonumber(request.y or 0),
        button = tonumber(request.button or 1), dx = tonumber(request.dx or 0), dy = tonumber(request.dy or 0)}}
    assert(type(events) == "table" and #events > 0 and #events <= 1000, "Expected 1..1000 pointer events")
    local images, result = {}, {events = {}, instances = {}}
    local context = {image = function(_, reference)
        if not images[reference] then
            local path = assert(project:resolveAssetFile(reference))
            images[reference] = love.image.newImageData(love.filesystem.newFileData(assert(project:readAsset(reference)), path))
        end
        return images[reference]
    end}
    local ok, err = pcall(function()
        assert(request.space == nil or request.space == "world" or request.space == "screen", "Expected world or screen space")
        for _, event in ipairs(events) do
            assert(type(event) == "table", "Invalid pointer event")
            local viewport = require("core.Viewport").new(world, 0, 0, tonumber(request.width or 1280), tonumber(request.height or 720))
            local valid, response
            if request.space == "screen" then
                valid, response = viewport:dispatchPointer(world, event.kind, event.x, event.y, event.button, event.dx, event.dy, context.image)
            else
                local sx, sy = viewport:worldToScreen(event.x, event.y)
                local px, py = viewport:worldToScreen(event.x - (event.dx or 0), event.y - (event.dy or 0))
                valid, response = viewport:dispatchPointer(world, event.kind, sx, sy, event.button,
                    sx - px, sy - py, context.image)
            end
            assert(valid, response); result.events[#result.events + 1] = response
        end
        for _, object in ipairs(world.lobjects) do
            local values = {}
            for name, value in pairs(object.properties) do
                if type(value) ~= "table" then values[name] = value
                elseif value.runtimeId then values[name] = {runtimeId = value.runtimeId, authoringId = value.authoringId} end
            end
            result.instances[#result.instances + 1] = {runtimeId = object.runtimeId, authoringId = object.authoringId, properties = values}
        end
    end)
    for _, image in pairs(images) do image:release() end
    world:cancelPointer()
    assert(ok, err)
    return result
end
return Operations
