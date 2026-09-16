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
    name = "scene view adds lobject at mouse position with a key",

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
        sceneView:keypressed("a", false, 50, 80)

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

        sceneView:keypressed("a", false, 40, 60)

        Assert.equal(1, #level.lobjects)
        Assert.equal(level.lobjects[1], sceneView.selectedLObject)
    end
}

tests[#tests + 1] = {
    name = "scene view empty left click deselects without adding lobject",

    fn = function()
        local Level = require("editor.level")
        local SceneView = require("editor.scene_view")

        local level = Level.new()
        local lobject = level:addLObject(20, 30)

        local sceneView = SceneView.new(32, level)
        sceneView.selectedLObject = lobject

        sceneView:mousepressed(100, 100, 1)

        -- 빈 공간 클릭은 선택만 해제해야 하며
        -- 새로운 authoring data를 만들면 안 된다.
        Assert.equal(1, #level.lobjects)
        Assert.equal(nil, sceneView.selectedLObject)
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

tests[#tests + 1] = {
    name = "selected lobject drag updates transform",

    fn = function()
        local Level = require("editor.level")
        local SceneView = require("editor.scene_view")

        local level = Level.new()
        local lobject = level:addLObject(20, 30)

        local sceneView = SceneView.new(32, level)

        -- LObject를 눌러 선택 + drag 시작.
        sceneView:mousepressed(20, 30, 1)

        -- Screen 기준으로 (10, 5)만큼 이동.
        sceneView:mousemoved(30, 35, 10, 5)

        Assert.equal(30, lobject.transform.x)
        Assert.equal(35, lobject.transform.y)

        sceneView:mousereleased(30, 35, 1)
    end
}

tests[#tests + 1] = {
    name = "lobject drag respects zoom",

    fn = function()
        local Level = require("editor.level")
        local SceneView = require("editor.scene_view")

        local level = Level.new()
        local lobject = level:addLObject(20, 30)

        local sceneView = SceneView.new(32, level)
        sceneView.zoom = 2

        -- World (20, 30)은 zoom 2 기준으로 Screen (40, 60).
        sceneView:mousepressed(40, 60, 1)

        -- Screen에서 10px 이동하면 World에서는 5만 이동해야 한다.
        sceneView:mousemoved(50, 70, 10, 10)

        Assert.equal(25, lobject.transform.x)
        Assert.equal(35, lobject.transform.y)

        sceneView:mousereleased(50, 70, 1)
    end
}

tests[#tests + 1] = {
    name = "level removes lobject",

    fn = function()
        local Level = require("editor.level")
        local level = Level.new()

        local first = level:addLObject(10, 20)
        local second = level:addLObject(30, 40)

        level:removeLObject(first)

        Assert.equal(1, #level.lobjects)
        Assert.equal(second, level.lobjects[1])
    end
}

tests[#tests + 1] = {
    name = "scene view deletes selected lobject",

    fn = function()
        local Level = require("editor.level")
        local SceneView = require("editor.scene_view")

        local level = Level.new()
        local lobject = level:addLObject(20, 30)

        local sceneView = SceneView.new(32, level)
        sceneView.selectedLObject = lobject

        sceneView:keypressed("delete")

        Assert.equal(0, #level.lobjects)
        Assert.equal(nil, sceneView.selectedLObject)
    end
}

tests[#tests + 1] = {
    name = "love keypressed callback exists",

    fn = function()
        Assert.truthy(love.keypressed)
    end
}

tests[#tests + 1] = {
    name = "level duplicates lobject without sharing transform",

    fn = function()
        local Level = require("editor.level")
        local level = Level.new()

        local original = level:addLObject(10, 20)
        local duplicate = level:duplicateLObject(original, 50, 60)

        Assert.equal(2, #level.lobjects)
        Assert.truthy(duplicate)
        Assert.truthy(duplicate ~= original)
        Assert.truthy(duplicate.transform ~= original.transform)

        Assert.equal(50, duplicate.transform.x)
        Assert.equal(60, duplicate.transform.y)

        duplicate.transform.x = 100

        Assert.equal(10, original.transform.x)
        Assert.equal(100, duplicate.transform.x)
    end
}

tests[#tests + 1] = {
    name = "scene view ctrl+d duplicates selected lobject at mouse position",

    fn = function()
        local Level = require("editor.level")
        local SceneView = require("editor.scene_view")

        local level = Level.new()
        local original = level:addLObject(20, 30)

        local sceneView = SceneView.new(32, level)
        sceneView.selectedLObject = original

        sceneView.cameraX = 10
        sceneView.cameraY = 20
        sceneView.zoom = 2

        -- Screen (110, 70)
        -- → World ((110 - 10) / 2, (70 - 20) / 2)
        -- → World (50, 25)
        sceneView:keypressed("d", true, 110, 70)

        Assert.equal(2, #level.lobjects)

        local duplicate = level.lobjects[2]

        Assert.equal(duplicate, sceneView.selectedLObject)
        Assert.truthy(duplicate ~= original)
        Assert.truthy(duplicate.transform ~= original.transform)

        Assert.equal(50, duplicate.transform.x)
        Assert.equal(25, duplicate.transform.y)
    end
}

tests[#tests + 1] = {
    name = "hierarchy maps rows to lobjects",

    fn = function()
        local Level = require("editor.level")
        local Hierarchy = require("editor.hierarchy")

        local level = Level.new()
        local first = level:addLObject(10, 20)
        local second = level:addLObject(30, 40)

        local hierarchy = Hierarchy.new(level)

        -- Header는 y=0~35, 첫 row는 y=36~59,
        -- 두 번째 row는 y=60~83이다.
        Assert.equal(first, hierarchy:getLObjectAtPosition(20, 40))
        Assert.equal(second, hierarchy:getLObjectAtPosition(20, 64))
    end
}

tests[#tests + 1] = {
    name = "hierarchy ignores positions outside panel or rows",

    fn = function()
        local Level = require("editor.level")
        local Hierarchy = require("editor.hierarchy")

        local level = Level.new()
        level:addLObject(10, 20)

        local hierarchy = Hierarchy.new(level)

        Assert.equal(nil, hierarchy:getLObjectAtPosition(20, 10))
        Assert.equal(nil, hierarchy:getLObjectAtPosition(250, 40))
        Assert.equal(nil, hierarchy:getLObjectAtPosition(20, 100))
    end
}

tests[#tests + 1] = {
    name = "editor app selects lobject from hierarchy",

    fn = function()
        local EditorApp = require("editor.app")
        local app = EditorApp.new()

        local first = app.level:addLObject(10, 20)
        local second = app.level:addLObject(30, 40)

        app.sceneView.selectedLObject = first

        -- 두 번째 Hierarchy row 클릭.
        app:mousepressed(20, 64, 1)

        Assert.equal(second, app.sceneView.selectedLObject)
        Assert.equal(2, #app.level.lobjects)

        -- LObject row가 없는 빈 영역 클릭은 선택 해제.
        app:mousepressed(20, 120, 1)

        Assert.equal(nil, app.sceneView.selectedLObject)
        Assert.equal(2, #app.level.lobjects)
    end
}

tests[#tests + 1] = {
    name = "inspector identifies lobject index",

    fn = function()
        local Level = require("editor.level")
        local Inspector = require("editor.inspector")

        local level = Level.new()
        local first = level:addLObject(10, 20)
        local second = level:addLObject(30, 40)

        local inspector = Inspector.new(level)

        Assert.equal(1, inspector:getLObjectIndex(first))
        Assert.equal(2, inspector:getLObjectIndex(second))
    end
}

tests[#tests + 1] = {
    name = "inspector detects right panel bounds",

    fn = function()
        local Inspector = require("editor.inspector")
        local inspector = Inspector.new(nil, 240)

        -- Window width가 1000이면 Inspector는 x=760~999.
        Assert.equal(false, inspector:containsPoint(759, 100, 1000))
        Assert.equal(true, inspector:containsPoint(760, 100, 1000))
        Assert.equal(true, inspector:containsPoint(999, 100, 1000))
        Assert.equal(false, inspector:containsPoint(1000, 100, 1000))
    end
}

tests[#tests + 1] = {
    name = "inspector maps transform fields",

    fn = function()
        local Inspector = require("editor.inspector")
        local inspector = Inspector.new(nil, 240)

        -- Window width 1000 기준 Inspector left는 760.
        Assert.equal("x", inspector:getFieldAtPosition(820, 110, 1000))
        Assert.equal("y", inspector:getFieldAtPosition(820, 140, 1000))
        Assert.equal(nil, inspector:getFieldAtPosition(820, 180, 1000))
    end
}

tests[#tests + 1] = {
    name = "inspector edits transform value",

    fn = function()
        local Level = require("editor.level")
        local Inspector = require("editor.inspector")

        local level = Level.new()
        local lobject = level:addLObject(10, 20)
        local inspector = Inspector.new(level, 240)

        inspector:mousepressed(820, 110, 1, 1000, lobject)

        Assert.equal(true, inspector:isEditing())

        inspector:textinput("-12.5")
        inspector:keypressed("return")

        Assert.equal(-12.5, lobject.transform.x)
        Assert.equal(20, lobject.transform.y)
        Assert.equal(false, inspector:isEditing())
    end
}

tests[#tests + 1] = {
    name = "inspector escape cancels transform edit",

    fn = function()
        local Level = require("editor.level")
        local Inspector = require("editor.inspector")

        local level = Level.new()
        local lobject = level:addLObject(10, 20)
        local inspector = Inspector.new(level, 240)

        inspector:mousepressed(820, 140, 1, 1000, lobject)
        inspector:textinput("99")
        inspector:keypressed("escape")

        Assert.equal(20, lobject.transform.y)
        Assert.equal(false, inspector:isEditing())
    end
}

tests[#tests + 1] = {
    name = "inspector rejects invalid transform value",

    fn = function()
        local Level = require("editor.level")
        local Inspector = require("editor.inspector")

        local level = Level.new()
        local lobject = level:addLObject(10, 20)
        local inspector = Inspector.new(level, 240)

        inspector:mousepressed(820, 110, 1, 1000, lobject)
        inspector:textinput("invalid")
        inspector:keypressed("return")

        Assert.equal(10, lobject.transform.x)
        Assert.equal(false, inspector:isEditing())
    end
}

tests[#tests + 1] = {
    name = "love textinput callback exists",

    fn = function()
        Assert.truthy(love.textinput)
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