local Host = {}
local Json = require("project.json")
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
        project = require("runtime.package_project").new(manifest)
        love.filesystem.setRequirePath(love.filesystem.getRequirePath() .. ";project/?.lua;project/?/init.lua")
        world = assert(require("runtime.world_loader").create(project, manifest.level))
        return true
    end)
    -- 배포 검증은 실제 게임 호스트에서 BeginPlay·Update·렌더링을 실행한 뒤 종료한다.
    for i, value in ipairs(args or {}) do
        if value == "--verify-game" then
            Host.update(1 / 60); Host.draw()
            local report = {ok = failure == nil, error = failure, objects = world and #world.lobjects,
                elapsedTime = world and world.elapsedTime, editorLoaded = package.loaded["editor.app"] ~= nil}
            if world then
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
    if world then attempt(function() return world:update(dt) end) end
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
            for _, object in ipairs(world.lobjects) do
                require("core.sprite_renderer").draw(object, image, function(x, y) return width / 2 + x, height / 2 + y end, 1)
            end
            return true
        end)
    end
    if failure then
        love.graphics.setColor(1, 0.5, 0.5, 1)
        love.graphics.printf("Game error\n" .. failure, 20, 20, math.max(1, love.graphics.getWidth() - 40))
    end
end
return Host
