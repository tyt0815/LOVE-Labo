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
    require("editor.theme").load()
    require("editor.fonts").apply()
    if hasArg(args, "--verify-package") then
        require("editor.package_verification").run(args)
        return
    end
    if hasArg(args, "--test") then
        local runner = require("tests.runner")

        local _, failed = runner.runAll()

        -- 테스트 결과를 process exit code로 전달한다.
        love.event.quit(failed == 0 and 0 or 1)
        return
    end

    local ProjectStart = require("editor.project_start")
    app = ProjectStart.new(function(project)
        local Settings = require("editor.snap_settings")
        local ok, editor = pcall(require("editor.app").new, nil, project, {snapSettings = Settings.load(), saveSnapSettings = Settings.save})
        if not ok then return false, tostring(editor) end
        app = editor
        love.window.setTitle("LOVE Labo - " .. project.name)
        return true
    end)
    require("editor.startup").openRequestedProject(args, app, love.filesystem.getWorkingDirectory())
end

-- love.update는 LÖVE Runtime이 매 프레임 호출한다.
-- dt는 직전 프레임 이후 경과 시간(초)이다.
function love.update(dt)
    require("editor.ui.ime").update()
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
        app:finishComposition()
        app.mode = "open"
        app:setPath(path)
        app.activeField = "path"
        app.replace = true
        require("editor.ui.text_edit").begin(app, app.path, true)
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
    if require("editor.ui.ime").consume(text) then return end
    if app then
        app:textinput(text)
    end
end

-- 조합 중인 글자는 확정 입력과 분리해 현재 입력칸에 표시한다.
function love.textedited(text, start, length)
    if app and app.textedited then app:textedited(text, start, length) end
end

function love.keypressed(key)
    if app then
        app:keypressed(key)
    end
end

function love.focus(focused)
    if app and app.focus then app:focus(focused) end
end

function love.quit()
    if app and app.viewportControls then app.viewportControls:commit() end
    if app and app.focus then app:focus(false) end
end
