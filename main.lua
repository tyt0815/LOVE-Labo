local app

-- LÖVE가 전달한 command-line argument에
-- 특정 인자가 존재하는지 확인한다.
local function hasArg(args, expected)
    for _, value in ipairs(args or {}) do
        if value == expected then
            return true
        end
    end

    return false
end

-- love.load는 일반 Lua main()이 아니라
-- LÖVE Runtime이 프로그램 시작 시 한 번 호출하는 callback이다.
function love.load(args)
    if hasArg(args, "--test") then
        local runner = require("tests.runner")

        local _, failed = runner.runAll()

        -- 테스트 결과를 process exit code로 전달한다.
        love.event.quit(failed == 0 and 0 or 1)
        return
    end

    -- Editor mode에서만 EditorApp을 로드한다.
    -- 현재 RED 단계에서는 editor/app.lua가 아직 없기 때문에
    -- love . 실행은 아직 성공 대상이 아니다.
    local EditorApp = require("editor.app")

    app = EditorApp.new()
end

-- love.update는 LÖVE Runtime이 매 프레임 호출한다.
-- dt는 직전 프레임 이후 경과 시간(초)이다.
function love.update(dt)
    if app then
        app:update(dt)
    end
end

-- love.draw는 LÖVE Runtime이 렌더링 시점마다 호출한다.
function love.draw()
    if app then
        app:draw()
    end
end