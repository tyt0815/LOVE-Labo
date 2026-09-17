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

tests[#tests + 1] = {
    name = "scene view viewport offsets coordinate conversion",

    fn = function()
        local SceneView = require("editor.scene_view")
        local sceneView = SceneView.new(32)

        sceneView:setViewport(220, 0, 540, 600)
        sceneView.cameraX = 10
        sceneView.cameraY = 20
        sceneView.zoom = 2

        local screenX, screenY = sceneView:worldToScreen(15, 25)

        -- 220 + 10 + 15 * 2 = 260
        Assert.equal(260, screenX)

        -- 0 + 20 + 25 * 2 = 70
        Assert.equal(70, screenY)

        local worldX, worldY = sceneView:screenToWorld(screenX, screenY)

        Assert.equal(15, worldX)
        Assert.equal(25, worldY)
    end
}

tests[#tests + 1] = {
    name = "scene view detects viewport bounds",

    fn = function()
        local SceneView = require("editor.scene_view")
        local sceneView = SceneView.new(32)

        sceneView:setViewport(220, 0, 540, 600)

        Assert.equal(false, sceneView:containsPoint(219, 100))
        Assert.equal(true, sceneView:containsPoint(220, 100))
        Assert.equal(true, sceneView:containsPoint(759, 100))
        Assert.equal(false, sceneView:containsPoint(760, 100))
    end
}

tests[#tests + 1] = {
    name = "editor app places scene view between panels",

    fn = function()
        local EditorApp = require("editor.app")
        local app = EditorApp.new()

        local width, height = love.graphics.getDimensions()

        app:updateSceneViewport()

        Assert.equal(app.hierarchy.width, app.sceneView.viewportX)
        Assert.equal(0, app.sceneView.viewportY)

        Assert.equal(
            width - app.hierarchy.width - app.inspector.width,
            app.sceneView.viewportWidth
        )

        Assert.equal(height, app.sceneView.viewportHeight)
    end
}

tests[#tests + 1] = {
    name = "scene view frames selected lobject",

    fn = function()
        local Level = require("editor.level")
        local SceneView = require("editor.scene_view")

        local level = Level.new()
        local lobject = level:addLObject(100, 50)

        local sceneView = SceneView.new(32, level)
        sceneView:setViewport(220, 0, 540, 600)
        sceneView.zoom = 2
        sceneView.selectedLObject = lobject

        sceneView:keypressed("f", false)

        local screenX, screenY =
            sceneView:worldToScreen(
                lobject.transform.x,
                lobject.transform.y
            )

        -- Scene View 중앙:
        -- X = 220 + 540 / 2 = 490
        -- Y = 600 / 2 = 300
        Assert.equal(490, screenX)
        Assert.equal(300, screenY)
    end
}

tests[#tests + 1] = {
    name = "level assigns stable authoring ids",

    fn = function()
        local Level = require("editor.level")
        local level = Level.new()

        local first = level:addLObject(10, 20)
        local second = level:addLObject(30, 40)
        local third = level:addLObject(50, 60)

        Assert.equal(1, first.authoringId)
        Assert.equal(2, second.authoringId)
        Assert.equal(3, third.authoringId)

        level:removeLObject(first)

        -- 배열 index는 바뀌어도 authoring identity는 바뀌면 안 된다.
        Assert.equal(second, level.lobjects[1])
        Assert.equal(2, second.authoringId)
        Assert.equal(3, third.authoringId)

        local fourth = level:addLObject(70, 80)

        -- 삭제된 1번을 재사용하지 않는다.
        Assert.equal(4, fourth.authoringId)
    end
}

tests[#tests + 1] = {
    name = "duplicated lobject gets new authoring id",

    fn = function()
        local Level = require("editor.level")
        local level = Level.new()

        local original = level:addLObject(10, 20)
        local duplicate = level:duplicateLObject(original, 30, 40)

        Assert.equal(1, original.authoringId)
        Assert.equal(2, duplicate.authoringId)
        Assert.truthy(original.authoringId ~= duplicate.authoringId)
    end
}

tests[#tests + 1] = {
    name = "level serialization round trip preserves authoring data",

    fn = function()
        local Level = require("editor.level")
        local level = Level.new()

        local first = level:addLObject(10, 20)
        local second = level:addLObject(30, 40)

        level:removeLObject(first)

        local data = level:toData()
        local loaded, err = Level.fromData(data)

        Assert.equal(nil, err)
        Assert.truthy(loaded)
        Assert.equal(1, #loaded.lobjects)

        Assert.equal(
            second.authoringId,
            loaded.lobjects[1].authoringId
        )
        Assert.equal(30, loaded.lobjects[1].transform.x)
        Assert.equal(40, loaded.lobjects[1].transform.y)

        -- 가장 큰 기존 ID 다음부터 새 identity를 발급한다.
        local added = loaded:addLObject(50, 60)
        Assert.equal(3, added.authoringId)
    end
}

tests[#tests + 1] = {
    name = "level serialization does not share mutable tables",

    fn = function()
        local Level = require("editor.level")
        local level = Level.new()
        local original = level:addLObject(10, 20)

        local data = level:toData()

        Assert.truthy(data.lobjects[1] ~= original)
        Assert.truthy(
            data.lobjects[1].transform ~= original.transform
        )

        data.lobjects[1].transform.x = 999

        Assert.equal(10, original.transform.x)

        local loaded = Level.fromData(data)

        Assert.truthy(
            loaded.lobjects[1].transform
                ~= data.lobjects[1].transform
        )

        loaded.lobjects[1].transform.y = 888

        Assert.equal(20, data.lobjects[1].transform.y)
    end
}

tests[#tests + 1] = {
    name = "level serialization rejects invalid data",

    fn = function()
        local Level = require("editor.level")

        local invalid = {
            formatVersion = 1,
            lobjects = {
                {
                    authoringId = 1,
                    transform = {
                        x = 10,
                        y = 20
                    }
                },
                {
                    -- duplicate stable identity
                    authoringId = 1,
                    transform = {
                        x = 30,
                        y = 40
                    }
                }
            }
        }

        local level, err = Level.fromData(invalid)

        Assert.equal(nil, level)
        Assert.truthy(err)
    end
}

local TEST_LEVEL_DIRECTORY = "level_file_tests"

local function getLevelTestPath(name)
    -- love.filesystem을 통해 save directory와 테스트용 하위 폴더를
    -- 실제로 생성한 뒤, io.open에서 사용할 absolute path를 만든다.
    local created = love.filesystem.createDirectory(
        TEST_LEVEL_DIRECTORY
    )

    Assert.equal(true, created)

    return love.filesystem.getSaveDirectory()
        .. "/"
        .. TEST_LEVEL_DIRECTORY
        .. "/"
        .. name
        .. ".level"
end

local function removeLevelFileArtifacts(path)
    os.remove(path)
    os.remove(path .. ".tmp")
    os.remove(path .. ".bak")
end

tests[#tests + 1] = {
    name = "level file encoding is deterministic readable json",

    fn = function()
        local Level = require("editor.level")
        local LevelFile = require("editor.level_file")

        local level = Level.new()
        level:addLObject(10, 20)

        local first, firstError = LevelFile.encode(level)
        local second, secondError = LevelFile.encode(level)

        Assert.equal(nil, firstError)
        Assert.equal(nil, secondError)
        Assert.equal(first, second)

        Assert.truthy(
            first:find('"formatVersion": 1', 1, true)
        )
        Assert.truthy(
            first:find('"authoringId": 1', 1, true)
        )
        Assert.truthy(
            first:find('"lobjects": [', 1, true)
        )
    end
}

tests[#tests + 1] = {
    name = "level file saves and loads level from disk",

    fn = function()
        local Level = require("editor.level")
        local LevelFile = require("editor.level_file")

        local path = getLevelTestPath("save_load_test")
        removeLevelFileArtifacts(path)

        local level = Level.new()
        local first = level:addLObject(10, 20)
        local second = level:addLObject(30, 40)

        level:removeLObject(first)

        local saved, saveError =
            LevelFile.save(path, level)

        Assert.equal(true, saved)
        Assert.equal(nil, saveError)

        -- 같은 경로에 다시 저장해 기존 파일 교체 경로도 통과시킨다.
        second.transform.x = 35

        local savedAgain, saveAgainError =
            LevelFile.save(path, level)

        Assert.equal(true, savedAgain)
        Assert.equal(nil, saveAgainError)

        local loaded, loadError =
            LevelFile.load(path)

        Assert.equal(nil, loadError)
        Assert.truthy(loaded)
        Assert.equal(1, #loaded.lobjects)
        Assert.equal(2, loaded.lobjects[1].authoringId)
        Assert.equal(35, loaded.lobjects[1].transform.x)
        Assert.equal(40, loaded.lobjects[1].transform.y)

        -- load 뒤에도 stable ID의 다음 번호를 이어간다.
        local added = loaded:addLObject(50, 60)
        Assert.equal(3, added.authoringId)

        removeLevelFileArtifacts(path)
    end
}

tests[#tests + 1] = {
    name = "level file rejects invalid json",

    fn = function()
        local LevelFile = require("editor.level_file")

        local path = getLevelTestPath("invalid_json_test")
        removeLevelFileArtifacts(path)

        local file = assert(io.open(path, "wb"))
        file:write('{"formatVersion":1,"lobjects":[')
        file:close()

        local level, err = LevelFile.load(path)

        Assert.equal(nil, level)
        Assert.truthy(err)

        removeLevelFileArtifacts(path)
    end
}

tests[#tests + 1] = {
    name = "failed level save preserves existing file",

    fn = function()
        local LevelFile = require("editor.level_file")

        local path = getLevelTestPath("preserve_existing_test")
        removeLevelFileArtifacts(path)

        local originalText = "existing good level"

        local file = assert(io.open(path, "wb"))
        file:write(originalText)
        file:close()

        -- JSON으로 encode할 수 없는 function을 넣어
        -- disk 교체 전에 save가 실패하도록 만든다.
        local invalidLevel = {
            toData = function()
                return {
                    formatVersion = 1,
                    lobjects = {},
                    unsupported = function()
                    end
                }
            end
        }

        local saved, err =
            LevelFile.save(path, invalidLevel)

        Assert.equal(false, saved)
        Assert.truthy(err)

        local preservedFile = assert(io.open(path, "rb"))
        local preservedText = preservedFile:read("*a")
        preservedFile:close()

        Assert.equal(originalText, preservedText)

        removeLevelFileArtifacts(path)
    end
}

tests[#tests + 1] = {
    name = "level document tracks dirty state from serialized level",

    fn = function()
        local LevelDocument =
            require("editor.level_document")

        local document = assert(LevelDocument.new())

        Assert.equal(false, document:isDirty())

        document.level:addLObject(10, 20)

        Assert.equal(true, document:isDirty())
    end
}

tests[#tests + 1] = {
    name = "level document save clears dirty and remembers path",

    fn = function()
        local LevelDocument =
            require("editor.level_document")

        local path =
            getLevelTestPath("level_document_save")

        removeLevelFileArtifacts(path)

        local document = assert(LevelDocument.new())
        document.level:addLObject(10, 20)

        Assert.equal(true, document:isDirty())

        local saved, saveError =
            document:save(path)

        Assert.equal(true, saved)
        Assert.equal(nil, saveError)
        Assert.equal(path, document.path)
        Assert.equal(false, document:isDirty())

        document.level.lobjects[1].transform.x = 30

        Assert.equal(true, document:isDirty())

        -- path를 다시 넘기지 않아도 마지막 성공 경로에 저장한다.
        local savedAgain, saveAgainError =
            document:save()

        Assert.equal(true, savedAgain)
        Assert.equal(nil, saveAgainError)
        Assert.equal(false, document:isDirty())

        removeLevelFileArtifacts(path)
    end
}

tests[#tests + 1] = {
    name = "loaded level document starts clean",

    fn = function()
        local Level = require("editor.level")
        local LevelFile = require("editor.level_file")
        local LevelDocument =
            require("editor.level_document")

        local path =
            getLevelTestPath("level_document_load")

        removeLevelFileArtifacts(path)

        local level = Level.new()
        level:addLObject(15, 25)

        local saved, saveError =
            LevelFile.save(path, level)

        Assert.equal(true, saved)
        Assert.equal(nil, saveError)

        local document, loadError =
            LevelDocument.load(path)

        Assert.equal(nil, loadError)
        Assert.truthy(document)
        Assert.equal(path, document.path)
        Assert.equal(false, document:isDirty())
        Assert.equal(15, document.level.lobjects[1].transform.x)
        Assert.equal(25, document.level.lobjects[1].transform.y)

        document.level.lobjects[1].transform.y = 50

        Assert.equal(true, document:isDirty())

        removeLevelFileArtifacts(path)
    end
}

tests[#tests + 1] = {
    name = "editor app owns level document shared by surfaces",

    fn = function()
        local EditorApp = require("editor.app")
        local app = EditorApp.new()

        Assert.truthy(app.document)
        Assert.equal(app.document.level, app.level)
        Assert.equal(app.level, app.sceneView.level)
        Assert.equal(app.level, app.hierarchy.level)
        Assert.equal(app.level, app.inspector.level)

        Assert.equal(false, app.document:isDirty())

        app.level:addLObject(10, 20)

        Assert.equal(true, app.document:isDirty())
    end
}

tests[#tests + 1] = {
    name = "editor app rebinds surfaces when document changes",

    fn = function()
        local EditorApp = require("editor.app")
        local LevelDocument =
            require("editor.level_document")

        local app = EditorApp.new()
        local oldLObject = app.level:addLObject(10, 20)

        app.sceneView.selectedLObject = oldLObject
        app.sceneView.isDraggingLObject = true

        local document = assert(LevelDocument.new())
        document.level:addLObject(30, 40)

        local changed = app:setDocument(document)

        Assert.equal(true, changed)
        Assert.equal(document, app.document)
        Assert.equal(document.level, app.level)
        Assert.equal(document.level, app.sceneView.level)
        Assert.equal(document.level, app.hierarchy.level)
        Assert.equal(document.level, app.inspector.level)
        Assert.equal(nil, app.sceneView.selectedLObject)
        Assert.equal(false, app.sceneView.isDraggingLObject)
    end
}

tests[#tests + 1] = {
    name = "editor save commits inspector edit before writing",

    fn = function()
        local EditorApp = require("editor.app")
        local LevelDocument =
            require("editor.level_document")

        local path =
            getLevelTestPath("editor_save_command")

        removeLevelFileArtifacts(path)

        local app = EditorApp.new()
        local lobject = app.level:addLObject(10, 20)

        app.inspector:beginEdit("x", lobject)
        app.inspector:textinput("42")

        -- text edit 중에는 아직 authoring Transform이 바뀌지 않았다.
        Assert.equal(10, lobject.transform.x)

        local saved, saveError =
            app:saveCurrentDocument(path)

        Assert.equal(true, saved)
        Assert.equal(nil, saveError)
        Assert.equal(42, lobject.transform.x)
        Assert.equal(false, app.inspector:isEditing())
        Assert.equal(false, app.document:isDirty())

        local loaded, loadError =
            LevelDocument.load(path)

        Assert.equal(nil, loadError)
        Assert.equal(
            42,
            loaded.level.lobjects[1].transform.x
        )

        removeLevelFileArtifacts(path)
    end
}

tests[#tests + 1] = {
    name = "editor ctrl+s saves document to remembered path",

    fn = function()
        local EditorApp = require("editor.app")
        local LevelDocument =
            require("editor.level_document")

        local path =
            getLevelTestPath("editor_ctrl_s")

        removeLevelFileArtifacts(path)

        local document = assert(LevelDocument.new())
        document.level:addLObject(10, 20)

        local initiallySaved, initialSaveError =
            document:save(path)

        Assert.equal(true, initiallySaved)
        Assert.equal(nil, initialSaveError)

        document.level.lobjects[1].transform.y = 55

        local app = EditorApp.new(document)

        Assert.equal(true, app.document:isDirty())

        local oldIsDown = love.keyboard.isDown

        love.keyboard.isDown = function(...)
            local keys = { ... }

            for _, key in ipairs(keys) do
                if key == "lctrl" or key == "rctrl" then
                    return true
                end
            end

            return false
        end

        local callOk, saved, saveError =
            pcall(function()
                return app:keypressed("s")
            end)

        love.keyboard.isDown = oldIsDown

        if not callOk then
            error(saved)
        end

        Assert.equal(true, saved)
        Assert.equal(nil, saveError)
        Assert.equal(false, app.document:isDirty())

        local loaded, loadError =
            LevelDocument.load(path)

        Assert.equal(nil, loadError)
        Assert.equal(
            55,
            loaded.level.lobjects[1].transform.y
        )

        removeLevelFileArtifacts(path)
    end
}

tests[#tests + 1] = {
    name = "editor save reports missing path for new document",

    fn = function()
        local EditorApp = require("editor.app")
        local app = EditorApp.new()

        app.level:addLObject(10, 20)

        local saved, err =
            app:saveCurrentDocument()

        Assert.equal(false, saved)
        Assert.equal(
            "level document has no save path",
            err
        )

        -- 실패한 save가 dirty state를 clean으로 바꾸면 안 된다.
        Assert.equal(true, app.document:isDirty())
    end
}

tests[#tests + 1] = {
    name = "editor opens clean level document from path",

    fn = function()
        local EditorApp = require("editor.app")
        local LevelDocument =
            require("editor.level_document")

        local path =
            getLevelTestPath("editor_open_document")

        removeLevelFileArtifacts(path)

        local source = assert(LevelDocument.new())
        source.level:addLObject(70, 80)

        local saved, saveError =
            source:save(path)

        Assert.equal(true, saved)
        Assert.equal(nil, saveError)

        local app = EditorApp.new()

        local opened, openError =
            app:openDocument(path)

        Assert.equal(true, opened)
        Assert.equal(nil, openError)
        Assert.equal(path, app.document.path)
        Assert.equal(false, app.document:isDirty())
        Assert.equal(1, #app.level.lobjects)
        Assert.equal(70, app.level.lobjects[1].transform.x)
        Assert.equal(80, app.level.lobjects[1].transform.y)
        Assert.equal(app.level, app.sceneView.level)
        Assert.equal(app.level, app.hierarchy.level)
        Assert.equal(app.level, app.inspector.level)

        removeLevelFileArtifacts(path)
    end
}

tests[#tests + 1] = {
    name = "editor refuses open when current document is dirty",

    fn = function()
        local EditorApp = require("editor.app")
        local LevelDocument =
            require("editor.level_document")

        local path =
            getLevelTestPath("editor_open_dirty_guard")

        removeLevelFileArtifacts(path)

        local source = assert(LevelDocument.new())
        source.level:addLObject(100, 200)

        local saved = source:save(path)
        Assert.equal(true, saved)

        local app = EditorApp.new()
        local currentLObject =
            app.level:addLObject(10, 20)

        local oldDocument = app.document

        local opened, err =
            app:openDocument(path)

        Assert.equal(false, opened)
        Assert.equal(
            "current level has unsaved changes",
            err
        )

        Assert.equal(oldDocument, app.document)
        Assert.equal(currentLObject, app.level.lobjects[1])
        Assert.equal(10, app.level.lobjects[1].transform.x)
        Assert.equal(true, app.document:isDirty())

        removeLevelFileArtifacts(path)
    end
}

tests[#tests + 1] = {
    name = "editor can explicitly discard dirty document when opening",

    fn = function()
        local EditorApp = require("editor.app")
        local LevelDocument =
            require("editor.level_document")

        local path =
            getLevelTestPath("editor_open_discard")

        removeLevelFileArtifacts(path)

        local source = assert(LevelDocument.new())
        source.level:addLObject(30, 40)

        local saved = source:save(path)
        Assert.equal(true, saved)

        local app = EditorApp.new()
        app.level:addLObject(999, 999)

        local opened, err =
            app:openDocument(path, true)

        Assert.equal(true, opened)
        Assert.equal(nil, err)
        Assert.equal(path, app.document.path)
        Assert.equal(false, app.document:isDirty())
        Assert.equal(1, #app.level.lobjects)
        Assert.equal(30, app.level.lobjects[1].transform.x)
        Assert.equal(40, app.level.lobjects[1].transform.y)

        removeLevelFileArtifacts(path)
    end
}

tests[#tests + 1] = {
    name = "failed editor open preserves current document",

    fn = function()
        local EditorApp = require("editor.app")

        local path =
            getLevelTestPath("editor_open_invalid")

        removeLevelFileArtifacts(path)

        local file = assert(io.open(path, "wb"))
        file:write('{"formatVersion":1,"lobjects":[')
        file:close()

        local app = EditorApp.new()
        local oldDocument = app.document
        local oldLevel = app.level

        local opened, err =
            app:openDocument(path)

        Assert.equal(false, opened)
        Assert.truthy(err)
        Assert.equal(oldDocument, app.document)
        Assert.equal(oldLevel, app.level)
        Assert.equal(oldLevel, app.sceneView.level)
        Assert.equal(oldLevel, app.hierarchy.level)
        Assert.equal(oldLevel, app.inspector.level)

        removeLevelFileArtifacts(path)
    end
}

tests[#tests + 1] = {
    name = "project resolves canonical relative reference",

    fn = function()
        local Project = require("editor.project")

        local project =
            assert(Project.new("C:\\Games\\RhythmProject\\"))

        Assert.equal(
            "C:/Games/RhythmProject",
            project.rootPath
        )

        local path, err =
            project:resolvePath("levels/song01.level")

        Assert.equal(nil, err)
        Assert.equal(
            "C:/Games/RhythmProject/levels/song01.level",
            path
        )
    end
}

tests[#tests + 1] = {
    name = "project rejects absolute asset references",

    fn = function()
        local Project = require("editor.project")
        local project =
            assert(Project.new("C:/Games/RhythmProject"))

        local windowsPath, windowsError =
            project:resolvePath(
                "D:/OtherProject/levels/main.level"
            )

        Assert.equal(nil, windowsPath)
        Assert.truthy(windowsError)

        local unixPath, unixError =
            project:resolvePath(
                "/other/levels/main.level"
            )

        Assert.equal(nil, unixPath)
        Assert.truthy(unixError)
    end
}

tests[#tests + 1] = {
    name = "project rejects non canonical relative reference",

    fn = function()
        local Project = require("editor.project")
        local project =
            assert(Project.new("C:/Games/RhythmProject"))

        local parentPath, parentError =
            project:resolvePath("../main.level")

        Assert.equal(nil, parentPath)
        Assert.truthy(parentError)

        local dotPath, dotError =
            project:resolvePath("./levels/main.level")

        Assert.equal(nil, dotPath)
        Assert.truthy(dotError)

        local backslashPath, backslashError =
            project:resolvePath(
                "levels\\main.level"
            )

        Assert.equal(nil, backslashPath)
        Assert.truthy(backslashError)

        local emptySegmentPath, emptySegmentError =
            project:resolvePath(
                "levels//main.level"
            )

        Assert.equal(nil, emptySegmentPath)
        Assert.truthy(emptySegmentError)
    end
}

tests[#tests + 1] = {
    name = "project preserves filesystem root when resolving",

    fn = function()
        local Project = require("editor.project")

        local windowsProject =
            assert(Project.new("C:/"))

        local windowsPath =
            windowsProject:resolvePath("levels/main.level")

        Assert.equal(
            "C:/levels/main.level",
            windowsPath
        )

        local unixProject =
            assert(Project.new("/"))

        local unixPath =
            unixProject:resolvePath("levels/main.level")

        Assert.equal(
            "/levels/main.level",
            unixPath
        )
    end
}


tests[#tests + 1] = {
    name = "project requires absolute root path",

    fn = function()
        local Project = require("editor.project")

        local project, err =
            Project.new("relative/project")

        Assert.equal(nil, project)
        Assert.truthy(err)
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