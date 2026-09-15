local Assert = require("tests.assert")

local tests = {}

tests[#tests + 1] = {
    name = "editor app module loads",

    fn = function()
        local EditorApp = require("editor.app")

        Assert.truthy(EditorApp)
        Assert.truthy(EditorApp.new)
    end
}

tests[#tests + 1] = {
    name = "scene view calculates grid line positions",

    fn = function()
        local SceneView = require("editor.scene_view")
        local sceneView = SceneView.new(32)

        local vertical, horizontal = sceneView:getGridLines(100, 70)

        Assert.equal(4, #vertical)
        Assert.equal(0, vertical[1])
        Assert.equal(32, vertical[2])
        Assert.equal(64, vertical[3])
        Assert.equal(96, vertical[4])

        Assert.equal(3, #horizontal)
        Assert.equal(0, horizontal[1])
        Assert.equal(32, horizontal[2])
        Assert.equal(64, horizontal[3])
    end
}

tests[#tests + 1] = {
    name = "scene view pans with middle mouse drag",

    fn = function()
        local SceneView = require("editor.scene_view")
        local sceneView = SceneView.new(32)

        sceneView:mousepressed(100, 100, 3)
        sceneView:mousemoved(110, 105, 10, 5)

        Assert.equal(10, sceneView.cameraX)
        Assert.equal(5, sceneView.cameraY)

        local vertical, horizontal = sceneView:getGridLines(100, 70)

        Assert.equal(3, #vertical)
        Assert.equal(10, vertical[1])
        Assert.equal(42, vertical[2])
        Assert.equal(74, vertical[3])

        Assert.equal(3, #horizontal)
        Assert.equal(5, horizontal[1])
        Assert.equal(37, horizontal[2])
        Assert.equal(69, horizontal[3])

        sceneView:mousereleased(110, 105, 3)
        sceneView:mousemoved(120, 115, 10, 10)

        Assert.equal(10, sceneView.cameraX)
        Assert.equal(5, sceneView.cameraY)
    end
}

tests[#tests + 1] = {
    name = "scene view zoom changes grid spacing",

    fn = function()
        local SceneView = require("editor.scene_view")
        local sceneView = SceneView.new(32)

        sceneView:zoomAtScreenPosition(0, 0, 1)

        Assert.equal(1.25, sceneView.zoom)

        local vertical, horizontal = sceneView:getGridLines(100, 70)

        Assert.equal(3, #vertical)
        Assert.equal(0, vertical[1])
        Assert.equal(40, vertical[2])
        Assert.equal(80, vertical[3])

        Assert.equal(2, #horizontal)
        Assert.equal(0, horizontal[1])
        Assert.equal(40, horizontal[2])
    end
}

tests[#tests + 1] = {
    name = "scene view zoom is clamped",

    fn = function()
        local SceneView = require("editor.scene_view")
        local sceneView = SceneView.new(32)

        sceneView:zoomAtScreenPosition(0, 0, -100)
        Assert.equal(0.25, sceneView.zoom)

        sceneView:zoomAtScreenPosition(0, 0, 100)
        Assert.equal(4.0, sceneView.zoom)
    end
}

tests[#tests + 1] = {
    name = "scene view zoom keeps cursor world position fixed",

    fn = function()
        local SceneView = require("editor.scene_view")
        local sceneView = SceneView.new(32)

        sceneView.cameraX = 10
        sceneView.cameraY = 20
        sceneView.zoom = 1

        local cursorX = 110
        local cursorY = 70

        local worldXBefore, worldYBefore =
            sceneView:screenToWorld(cursorX, cursorY)

        Assert.equal(100, worldXBefore)
        Assert.equal(50, worldYBefore)

        sceneView:zoomAtScreenPosition(cursorX, cursorY, 1)

        Assert.equal(1.25, sceneView.zoom)

        local worldXAfter, worldYAfter =
            sceneView:screenToWorld(cursorX, cursorY)

        Assert.equal(worldXBefore, worldXAfter)
        Assert.equal(worldYBefore, worldYAfter)
    end
}

tests[#tests + 1] = {
    name = "scene view converts between world and screen coordinates",

    fn = function()
        local SceneView = require("editor.scene_view")
        local sceneView = SceneView.new(32)

        sceneView.cameraX = 10
        sceneView.cameraY = 20
        sceneView.zoom = 2

        local screenX, screenY = sceneView:worldToScreen(15, 25)

        Assert.equal(40, screenX)
        Assert.equal(70, screenY)

        local worldX, worldY = sceneView:screenToWorld(screenX, screenY)

        Assert.equal(15, worldX)
        Assert.equal(25, worldY)
    end
}

tests[#tests + 1] = {
    name = "scene view world origin follows camera",

    fn = function()
        local SceneView = require("editor.scene_view")
        local sceneView = SceneView.new(32)

        sceneView.cameraX = 50
        sceneView.cameraY = 30
        sceneView.zoom = 2

        local originX, originY = sceneView:worldToScreen(0, 0)

        Assert.equal(50, originX)
        Assert.equal(30, originY)
    end
}

tests[#tests + 1] = {
    name = "level stores lobject transform",

    fn = function()
        local Level = require("editor.level")
        local level = Level.new()

        level:addLObject(20, 30)

        Assert.equal(1, #level.lobjects)
        Assert.equal(20, level.lobjects[1].transform.x)
        Assert.equal(30, level.lobjects[1].transform.y)
    end
}

tests[#tests + 1] = {
    name = "scene view adds lobject transform with left click",

    fn = function()
        local Level = require("editor.level")
        local SceneView = require("editor.scene_view")

        local level = Level.new()
        local sceneView = SceneView.new(32, level)

        sceneView.cameraX = 10
        sceneView.cameraY = 20
        sceneView.zoom = 2

        -- Screen (50, 80)은 현재 camera/zoom 기준으로
        -- World (20, 30)에 해당한다.
        sceneView:mousepressed(50, 80, 1)

        Assert.equal(1, #level.lobjects)
        Assert.equal(20, level.lobjects[1].transform.x)
        Assert.equal(30, level.lobjects[1].transform.y)
    end
}

tests[#tests + 1] = {
    name = "scene view selects newly added lobject",

    fn = function()
        local Level = require("editor.level")
        local SceneView = require("editor.scene_view")

        local level = Level.new()
        local sceneView = SceneView.new(32, level)

        sceneView:mousepressed(40, 60, 1)

        Assert.equal(1, #level.lobjects)
        Assert.equal(level.lobjects[1], sceneView.selectedLObject)
    end
}

tests[#tests + 1] = {
    name = "scene view selects existing lobject without adding another",

    fn = function()
        local Level = require("editor.level")
        local SceneView = require("editor.scene_view")

        local level = Level.new()
        local existingLObject = level:addLObject(20, 30)

        local sceneView = SceneView.new(32, level)

        -- 현재 zoom/camera 기본값에서는
        -- World (20, 30) == Screen (20, 30)이다.
        sceneView:mousepressed(20, 30, 1)

        Assert.equal(1, #level.lobjects)
        Assert.equal(existingLObject, sceneView.selectedLObject)
    end
}

local TestRunner = {}

function TestRunner.runAll()
    local passed = 0
    local failed = 0

    for _, test in ipairs(tests) do
        -- 개별 테스트 오류가 전체 test runner를 종료시키지 않도록
        -- pcall로 테스트 함수를 보호한다.
        local ok, err = pcall(test.fn)

        if ok then
            passed = passed + 1
            print("[PASS] " .. test.name)
        else
            failed = failed + 1
            print("[FAIL] " .. test.name .. ": " .. tostring(err))
        end
    end

    print(string.format("%d passed, %d failed", passed, failed))

    return passed, failed
end

return TestRunner