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

    -- Editor mode에서만 EditorApp을 생성한다.
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

function love.mousepressed(x, y, button)
    if app then
        app:mousepressed(x, y, button)
    end
end

function love.mousereleased(x, y, button)
    if app then
        app:mousereleased(x, y, button)
    end
end

function love.mousemoved(x, y, dx, dy)
    if app then
        app:mousemoved(x, y, dx, dy)
    end
end

function love.wheelmoved(x, y)
    if app then
        app:wheelmoved(x, y)
    end
end

-- love.textinput은 실제 입력된 문자(text)를 전달한다.
-- Inspector의 숫자 field처럼 text editing이 필요한 UI에서 사용한다.
function love.textinput(text)
    if app then
        app:textinput(text)
    end
end

function love.keypressed(key)
    if app then
        app:keypressed(key)
    end
end
