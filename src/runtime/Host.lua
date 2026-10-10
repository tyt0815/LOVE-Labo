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
    -- 배포 검증은 실제 게임 호스트에서 beginPlay·update·렌더링을 실행한 뒤 종료한다.
    for i, value in ipairs(args or {}) do
        if value == "--verify-game" then
            Host.update(1 / 60); Host.draw()
            for _, argument in ipairs(args) do
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
                report.properties = {}
                for _, object in ipairs(world.lobjects) do
                    local values = {}
                    for key, item in pairs(object.properties) do
                        if type(item) ~= "table" then values[key] = item
                        elseif item.authoringId then values[key] = {instance = item.authoringId} end
                    end
                    report.properties[#report.properties + 1] = values
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
            if candidate then world = candidate end
        end
    end
end
local function image(reference)
    if not images[reference] then images[reference] = love.graphics.newImage(assert(project:resolveAssetFile(reference))) end
    return images[reference]
end
function Host.draw()
    love.graphics.clear(0.05, 0.05, 0.07, 1)
    if world then
        attempt(function()
            local width, height = love.graphics.getDimensions()
            require("core.Renderer").drawWorld(world, image, require("core.Viewport").new(world, 0, 0, width, height))
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
function Host.mousepressed(x, y, button) return Host.pointer("down", x, y, button) end
function Host.mousereleased(x, y, button) return Host.pointer("up", x, y, button) end
function Host.mousemoved(x, y, dx, dy) return Host.pointer("move", x, y, 1, dx, dy) end
function Host.focus(focused) if not focused and world then world:cancelPointer() end end
return Host
