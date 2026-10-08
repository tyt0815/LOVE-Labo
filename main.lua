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

    local Launcher = require("editor.launcher")
    -- 한글 프로젝트 이름과 경로를 표시할 수 있는 호스트 글꼴을 사용한다.
    local fs = require("editor.host_filesystem")
    local fontPath = fs.join(os.getenv("WINDIR") or "C:/Windows", "Fonts/malgun.ttf")
    local fontBytes = fs.read(fontPath)
    if fontBytes then
        love.graphics.setFont(love.graphics.newFont(love.filesystem.newFileData(fontBytes, "malgun.ttf"), 14))
    end
    app = Launcher.new(function(project)
        local ok, editor = pcall(require("editor.app").new, nil, project)
        if not ok then return false, tostring(editor) end
        app = editor
        love.window.setTitle("LOVE Labo - " .. project.name)
        return true
    end)
end

-- love.update는 LÖVE Runtime이 매 프레임 호출한다.
-- dt는 직전 프레임 이후 경과 시간(초)이다.
function love.update(dt)
    if app and app.update then
        app:update(dt)
    end
end

-- love.draw는 LÖVE Runtime이 렌더링 시점마다 호출한다.
function love.draw()
    if app then
        app:draw()
    end
end

function love.mousepressed(x, y, button, istouch, presses)
    if app then
        app:mousepressed(x, y, button, presses)
    end
end

function love.mousereleased(x, y, button)
    if app and app.mousereleased then
        app:mousereleased(x, y, button)
    end
end

function love.mousemoved(x, y, dx, dy)
    if app and app.mousemoved then
        app:mousemoved(x, y, dx, dy)
    end
end

function love.directorydropped(path)
    if app and app.mode then
        app.mode = "open"
        app.path = path
        app.activeField = "path"
        app.replace = true
        app.error = nil
    end
end

function love.wheelmoved(x, y)
    if app and app.wheelmoved then
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
