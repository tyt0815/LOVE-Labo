local Host = {}
local Json = require("project.Json")
local world, project, failure
local images = {}
local function attempt(callback)
    local ok, result, err = pcall(callback)
    if not ok or result == false then failure = tostring(ok and err or result); world = nil; return false end
    return true
end

function Host.load(args)
    attempt(function()
        local manifest = assert(Json.decode(assert(love.filesystem.read("game.json"))))
        project = require("runtime.PackageProject").new(manifest)
        love.filesystem.setRequirePath(love.filesystem.getRequirePath() .. ";project/?.lua;project/?/init.lua")
        world = assert(require("runtime.WorldLoader").create(project, manifest.level))
        return true
    end)
    if world then Host.event("resize") end
    -- 배포 검증은 실제 게임 호스트에서 load·update·렌더링을 실행한 뒤 종료한다.
    for i, value in ipairs(args or {}) do
        if value == "--verify-game" then
            Host.update(1 / 60); Host.draw()
            for index, argument in ipairs(args) do
                if argument == "--verify-events" then
                    attempt(function()
                        local file = assert(io.open(assert(args[index + 1]), "rb"))
                        local bytes = file:read("*a"); file:close()
                        local events = assert(Json.decode(bytes))
                        for _, event in ipairs(events) do
                            assert(require("core.ScriptEvents").supported[event.name], "Unsupported script event")
                            Host[event.name](unpack(event.args))
                            if failure then return false, failure end
                        end
                        return true
                    end)
                end
                if argument == "--verify-pointer" then
                    local width, height = love.graphics.getDimensions()
                    Host.mousepressed(width / 2, height / 2, 1)
                    Host.mousereleased(width + 100, height + 100, 1)
                end
            end
            local report = {ok = failure == nil, error = failure, objects = world and #world.lobjects,
                elapsedTime = world and world.elapsedTime, levelReference = world and world.levelReference, transitionError = world and world.levelTransitionError, editorLoaded = package.loaded["editor.EditorApp"] ~= nil}
            if world then
                local width, height = love.graphics.getDimensions()
                local viewport = require("core.Viewport").new(world, 0, 0, width, height)
                report.view = {scale = viewport.scale, camera = viewport.camera and viewport.camera.name,
                    x = viewport.transform.x, y = viewport.transform.y}
                report.properties, report.instances = {}, {}
                for _, object in ipairs(world.lobjects) do
                    local values = {}
                    for key, item in pairs(object.properties) do
                        if type(item) ~= "table" then values[key] = item
                        elseif item.authoringId then values[key] = {instance = item.authoringId} end
                    end
                    report.properties[#report.properties + 1] = values
                    report.instances[#report.instances + 1] = {authoringId = object.authoringId, name = object.name,
                        transform = object.transform, scripts = require("runtime.ScriptState").read(object)}
                end
            end
            local path = args[i + 1]
            local file = path and io.open(path, "wb")
            if file then file:write(assert(Json.encode(report, true))); file:close()
            else failure = "Cannot write game verification report" end
            love.event.quit(failure and 1 or 0)
            return
        end
    end
end
function Host.update(dt)
    if world then
        attempt(function() return world:update(dt) end)
        if world then
            local candidate = world:takeLevelTransition()
            if candidate then
                world = candidate
                Host.event("resize")
            end
        end
    end
end
local function image(reference)
    if not images[reference] then images[reference] = love.graphics.newImage(assert(project:resolveAssetFile(reference))) end
    return images[reference]
end
function Host.draw()
    love.graphics.clear(0, 0, 0, 1)
    if world then
        attempt(function()
            local width, height = love.graphics.getDimensions()
            local viewport = require("core.Viewport").new(world, 0, 0, width, height)
            love.graphics.push("all")
            love.graphics.setColor(0.05, 0.05, 0.07, 1)
            love.graphics.rectangle("fill", viewport.x, viewport.y, viewport.width, viewport.height)
            local ok, err = pcall(require("core.Renderer").drawWorld, world, image, viewport)
            love.graphics.pop()
            if not ok then error(err, 0) end
            return true
        end)
    end
    if world and world.levelTransitionError then
        love.graphics.setColor(1, 0.5, 0.5, 1)
        love.graphics.printf("Level transition failed\n" .. world.levelTransitionError, 20, 20, math.max(1, love.graphics.getWidth() - 40))
    end
    if failure then
        love.graphics.setColor(1, 0.5, 0.5, 1)
        love.graphics.printf("Game error\n" .. failure, 20, 20, math.max(1, love.graphics.getWidth() - 40))
    end
end
function Host.pointer(kind, x, y, button, dx, dy)
    if not world then return end
    local width, height = love.graphics.getDimensions()
    return attempt(function()
        return require("core.Viewport").new(world, 0, 0, width, height):dispatchPointer(world, kind, x, y, button, dx, dy, function(_, reference) return image(reference) end)
    end)
end
local Events = require("core.ScriptEvents")
function Host.event(name, ...)
    if not world then return end
    local args, count = {...}, select("#", ...)
    return attempt(function()
        local width, height = love.graphics.getDimensions()
        local viewport = require("core.Viewport").new(world, 0, 0, width, height)
        if name == "resize" then args = {viewport.width, viewport.height}; count = 2 end
        if name == "focus" and not args[1] then world:cancelPointer() end
        return Events.screen(world, viewport, name, unpack(args, 1, count))
    end)
end
for _, name in ipairs(Events.names) do
    local eventName = name
    Host[name] = function(...) return Host.event(eventName, ...) end
end
local function mouse(name, kind, x, y, button, istouch, presses)
    Host.event(name, x, y, button, istouch, presses)
    return Host.pointer(kind, x, y, button)
end
function Host.mousepressed(...) return mouse("mousepressed", "down", ...) end
function Host.mousereleased(...) return mouse("mousereleased", "up", ...) end
function Host.mousemoved(x, y, dx, dy, istouch)
    Host.event("mousemoved", x, y, dx, dy, istouch)
    return Host.pointer("move", x, y, 1, dx, dy)
end
return Host
