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

tests[#tests + 1] = {
    name = "editor saves project document by relative reference",

    fn = function()
        local EditorApp = require("editor.app")
        local Project = require("editor.project")
        local LevelDocument =
            require("editor.level_document")

        local root =
            love.filesystem.getSaveDirectory()
            .. "/"
            .. TEST_LEVEL_DIRECTORY

        local project = assert(Project.new(root))
        local reference = "editor_project_save.level"
        local path = assert(project:resolvePath(reference))

        removeLevelFileArtifacts(path)

        local app = EditorApp.new(nil, project)
        app.level:addLObject(12, 34)

        local saved, saveError =
            app:saveCurrentDocumentAs(reference)

        Assert.equal(true, saved)
        Assert.equal(nil, saveError)
        Assert.equal(reference, app.documentReference)
        Assert.equal(path, app.document.path)
        Assert.equal(false, app.document:isDirty())

        local loaded, loadError =
            LevelDocument.load(path)

        Assert.equal(nil, loadError)
        Assert.equal(12, loaded.level.lobjects[1].transform.x)
        Assert.equal(34, loaded.level.lobjects[1].transform.y)

        -- 이후 일반 Ctrl+S 계열 저장은 기억된 absolute path를 사용하지만
        -- Editor-facing project reference는 그대로 유지한다.
        app.level.lobjects[1].transform.x = 56

        local savedAgain, saveAgainError =
            app:saveCurrentDocument()

        Assert.equal(true, savedAgain)
        Assert.equal(nil, saveAgainError)
        Assert.equal(reference, app.documentReference)

        removeLevelFileArtifacts(path)
    end
}

tests[#tests + 1] = {
    name = "editor opens project document by relative reference",

    fn = function()
        local EditorApp = require("editor.app")
        local Project = require("editor.project")
        local LevelDocument =
            require("editor.level_document")

        local root =
            love.filesystem.getSaveDirectory()
            .. "/"
            .. TEST_LEVEL_DIRECTORY

        local project = assert(Project.new(root))
        local reference = "editor_project_open.level"
        local path = assert(project:resolvePath(reference))

        removeLevelFileArtifacts(path)

        local source = assert(LevelDocument.new())
        source.level:addLObject(70, 90)

        local saved = source:save(path)
        Assert.equal(true, saved)

        local app = EditorApp.new(nil, project)

        local opened, openError =
            app:openProjectDocument(reference)

        Assert.equal(true, opened)
        Assert.equal(nil, openError)
        Assert.equal(reference, app.documentReference)
        Assert.equal(path, app.document.path)
        Assert.equal(70, app.level.lobjects[1].transform.x)
        Assert.equal(90, app.level.lobjects[1].transform.y)
        Assert.equal(false, app.document:isDirty())

        removeLevelFileArtifacts(path)
    end
}

tests[#tests + 1] = {
    name = "editor project document commands require project",

    fn = function()
        local EditorApp = require("editor.app")
        local app = EditorApp.new()

        local saved, saveError =
            app:saveCurrentDocumentAs("levels/main.level")

        Assert.equal(false, saved)
        Assert.equal("editor has no project", saveError)

        local opened, openError =
            app:openProjectDocument("levels/main.level")

        Assert.equal(false, opened)
        Assert.equal("editor has no project", openError)
    end
}

tests[#tests + 1] = {
    name = "editor rejects invalid project document reference",

    fn = function()
        local EditorApp = require("editor.app")
        local Project = require("editor.project")

        local root =
            love.filesystem.getSaveDirectory()
            .. "/"
            .. TEST_LEVEL_DIRECTORY

        local project = assert(Project.new(root))
        local app = EditorApp.new(nil, project)
        local oldDocument = app.document
        local oldLevel = app.level

        local opened, err =
            app:openProjectDocument("../outside.level")

        Assert.equal(false, opened)
        Assert.truthy(err)
        Assert.equal(oldDocument, app.document)
        Assert.equal(oldLevel, app.level)

        local saved, saveError =
            app:saveCurrentDocumentAs("../outside.level")

        Assert.equal(false, saved)
        Assert.truthy(saveError)
        Assert.equal(nil, app.documentReference)
    end
}

tests[#tests + 1] = {
    name = "level document creates new file without overwriting",

    fn = function()
        local LevelDocument =
            require("editor.level_document")

        local path =
            getLevelTestPath("level_document_create")

        removeLevelFileArtifacts(path)

        local document, createError =
            LevelDocument.create(path)

        Assert.equal(nil, createError)
        Assert.truthy(document)
        Assert.equal(path, document.path)
        Assert.equal(false, document:isDirty())

        local secondDocument, secondError =
            LevelDocument.create(path)

        Assert.equal(nil, secondDocument)
        Assert.equal(
            "level file already exists",
            secondError
        )

        removeLevelFileArtifacts(path)
    end
}

tests[#tests + 1] = {
    name = "editor creates blank project level asset",

    fn = function()
        local EditorApp = require("editor.app")
        local Project = require("editor.project")

        local root =
            love.filesystem.getSaveDirectory()
            .. "/"
            .. TEST_LEVEL_DIRECTORY

        local project = assert(Project.new(root))
        local reference = "editor_new_level.level"
        local path = assert(project:resolvePath(reference))

        removeLevelFileArtifacts(path)

        local app = EditorApp.new(nil, project)
        app.level:addLObject(10, 20)

        local created, createError =
            app:createProjectDocument(reference, true)

        Assert.equal(true, created)
        Assert.equal(nil, createError)
        Assert.equal(reference, app.documentReference)
        Assert.equal(path, app.document.path)
        Assert.equal(0, #app.level.lobjects)
        Assert.equal(false, app.document:isDirty())

        local file = io.open(path, "rb")
        Assert.truthy(file)
        file:close()

        removeLevelFileArtifacts(path)
    end
}

tests[#tests + 1] = {
    name = "editor refuses new project level when current document is dirty",

    fn = function()
        local EditorApp = require("editor.app")
        local Project = require("editor.project")

        local root =
            love.filesystem.getSaveDirectory()
            .. "/"
            .. TEST_LEVEL_DIRECTORY

        local project = assert(Project.new(root))
        local reference = "editor_new_dirty_guard.level"
        local path = assert(project:resolvePath(reference))

        removeLevelFileArtifacts(path)

        local app = EditorApp.new(nil, project)
        local currentLObject =
            app.level:addLObject(10, 20)

        local oldDocument = app.document

        local created, err =
            app:createProjectDocument(reference)

        Assert.equal(false, created)
        Assert.equal(
            "current level has unsaved changes",
            err
        )
        Assert.equal(oldDocument, app.document)
        Assert.equal(currentLObject, app.level.lobjects[1])

        local unexpectedFile = io.open(path, "rb")
        Assert.equal(nil, unexpectedFile)

        removeLevelFileArtifacts(path)
    end
}

tests[#tests + 1] = {
    name = "editor new project level preserves current document on create failure",

    fn = function()
        local EditorApp = require("editor.app")
        local Project = require("editor.project")

        local root =
            love.filesystem.getSaveDirectory()
            .. "/"
            .. TEST_LEVEL_DIRECTORY

        local project = assert(Project.new(root))
        local reference = "editor_existing_level.level"
        local path = assert(project:resolvePath(reference))

        removeLevelFileArtifacts(path)

        local file = assert(io.open(path, "wb"))
        file:write("existing")
        file:close()

        local app = EditorApp.new(nil, project)
        local oldDocument = app.document
        local oldLevel = app.level

        local created, err =
            app:createProjectDocument(reference)

        Assert.equal(false, created)
        Assert.equal("level file already exists", err)
        Assert.equal(oldDocument, app.document)
        Assert.equal(oldLevel, app.level)
        Assert.equal(nil, app.documentReference)

        local preserved = assert(io.open(path, "rb"))
        local text = preserved:read("*a")
        preserved:close()

        Assert.equal("existing", text)

        removeLevelFileArtifacts(path)
    end
}

tests[#tests + 1] = {
    name = "runtime world builds independent lobjects from level data",

    fn = function()
        local Level = require("editor.level")
        local World = require("core.world")

        local level = Level.new()
        local authoringLObject =
            level:addLObject(10, 20)

        local levelData = level:toData()
        local world, worldError =
            World.fromLevelData(levelData)

        Assert.equal(nil, worldError)
        Assert.truthy(world)
        Assert.equal(1, #world.lobjects)

        local runtimeLObject = world.lobjects[1]

        Assert.equal(1, runtimeLObject.runtimeId)
        Assert.equal(10, runtimeLObject.transform.x)
        Assert.equal(20, runtimeLObject.transform.y)

        -- Runtime mutation이 authoring Level 또는 중간 data snapshot에
        -- write-back되면 안 된다.
        runtimeLObject.transform.x = 100
        runtimeLObject.transform.y = 200

        Assert.equal(10, authoringLObject.transform.x)
        Assert.equal(20, authoringLObject.transform.y)
        Assert.equal(10, levelData.lobjects[1].transform.x)
        Assert.equal(20, levelData.lobjects[1].transform.y)
    end
}

tests[#tests + 1] = {
    name = "runtime world assigns independent runtime identities",

    fn = function()
        local Level = require("editor.level")
        local World = require("core.world")

        local level = Level.new()
        level:addLObject(10, 20)
        level:addLObject(30, 40)

        local world = assert(
            World.fromLevelData(level:toData())
        )

        Assert.equal(2, #world.lobjects)
        Assert.equal(1, world.lobjects[1].runtimeId)
        Assert.equal(2, world.lobjects[2].runtimeId)

        local added, addError =
            world:addLObject({
                transform = {
                    x = 50,
                    y = 60
                }
            })

        Assert.equal(nil, addError)
        Assert.truthy(added)
        Assert.equal(3, added.runtimeId)
        Assert.equal(3, #world.lobjects)
    end
}

tests[#tests + 1] = {
    name = "runtime world copies state passed to add lobject",

    fn = function()
        local World = require("core.world")

        local initialState = {
            transform = {
                x = 15,
                y = 25
            }
        }

        local world = World.new()
        local lobject = assert(
            world:addLObject(initialState)
        )

        initialState.transform.x = 999

        Assert.equal(15, lobject.transform.x)

        lobject.transform.y = 888

        Assert.equal(25, initialState.transform.y)
    end
}

tests[#tests + 1] = {
    name = "runtime world rejects invalid level data atomically",

    fn = function()
        local World = require("core.world")

        local invalid = {
            lobjects = {
                {
                    transform = {
                        x = 10,
                        y = 20
                    }
                },
                {
                    transform = {
                        x = "invalid",
                        y = 40
                    }
                }
            }
        }

        local world, err =
            World.fromLevelData(invalid)

        Assert.equal(nil, world)
        Assert.truthy(err)
    end
}

tests[#tests + 1] = {
    name = "editor play builds runtime world from current level",

    fn = function()
        local EditorApp = require("editor.app")

        local app = EditorApp.new()
        local authoringLObject =
            app.level:addLObject(10, 20)

        local started, startError =
            app:startPlay()

        Assert.equal(true, started)
        Assert.equal(nil, startError)
        Assert.equal(true, app:isPlaying())
        Assert.truthy(app.runtimeWorld)
        Assert.equal(1, #app.runtimeWorld.lobjects)

        local runtimeLObject =
            app.runtimeWorld.lobjects[1]

        Assert.equal(10, runtimeLObject.transform.x)
        Assert.equal(20, runtimeLObject.transform.y)

        -- Runtime과 authoring은 서로 write-back하지 않는다.
        runtimeLObject.transform.x = 100
        Assert.equal(10, authoringLObject.transform.x)

        authoringLObject.transform.y = 200
        Assert.equal(20, runtimeLObject.transform.y)
    end
}

tests[#tests + 1] = {
    name = "editor stop discards runtime world and replay rebuilds it",

    fn = function()
        local EditorApp = require("editor.app")

        local app = EditorApp.new()
        local authoringLObject =
            app.level:addLObject(10, 20)

        Assert.equal(true, app:startPlay())

        local firstWorld = app.runtimeWorld
        firstWorld.lobjects[1].transform.x = 999

        local stopped, stopError =
            app:stopPlay()

        Assert.equal(true, stopped)
        Assert.equal(nil, stopError)
        Assert.equal(false, app:isPlaying())
        Assert.equal(nil, app.runtimeWorld)

        -- Stop은 Runtime 값을 Level로 되돌려 쓰지 않는다.
        Assert.equal(10, authoringLObject.transform.x)

        -- 다음 Play는 현재 authoring state에서 새 World를 만든다.
        authoringLObject.transform.x = 30

        Assert.equal(true, app:startPlay())
        Assert.truthy(app.runtimeWorld ~= firstWorld)
        Assert.equal(
            30,
            app.runtimeWorld.lobjects[1].transform.x
        )
    end
}

tests[#tests + 1] = {
    name = "editor play commits inspector edit before snapshot",

    fn = function()
        local EditorApp = require("editor.app")

        local app = EditorApp.new()
        local lobject =
            app.level:addLObject(10, 20)

        app.inspector:beginEdit("x", lobject)
        app.inspector:textinput("42")

        Assert.equal(10, lobject.transform.x)

        local started, startError =
            app:startPlay()

        Assert.equal(true, started)
        Assert.equal(nil, startError)
        Assert.equal(42, lobject.transform.x)
        Assert.equal(
            42,
            app.runtimeWorld.lobjects[1].transform.x
        )
        Assert.equal(false, app.inspector:isEditing())
    end
}

tests[#tests + 1] = {
    name = "editor document change stops active play world",

    fn = function()
        local EditorApp = require("editor.app")
        local LevelDocument =
            require("editor.level_document")

        local app = EditorApp.new()
        app.level:addLObject(10, 20)

        Assert.equal(true, app:startPlay())
        Assert.equal(true, app:isPlaying())

        local nextDocument =
            assert(LevelDocument.new())

        nextDocument.level:addLObject(30, 40)

        local changed =
            app:setDocument(nextDocument)

        Assert.equal(true, changed)
        Assert.equal(false, app:isPlaying())
        Assert.equal(nil, app.runtimeWorld)
        Assert.equal(nextDocument, app.document)
        Assert.equal(30, app.level.lobjects[1].transform.x)
    end
}

tests[#tests + 1] = {
    name = "game view maps runtime world position into viewport",

    fn = function()
        local GameView =
            require("editor.game_view")

        local gameView =
            GameView.new()

        gameView:setViewport(
            200,
            30,
            640,
            480
        )

        local screenX, screenY =
            gameView:worldToScreen(
                50,
                75
            )

        Assert.equal(250, screenX)
        Assert.equal(105, screenY)
    end
}

tests[#tests + 1] = {
    name = "editor active center view switches during play",

    fn = function()
        local EditorApp =
            require("editor.app")

        local app =
            EditorApp.new()

        Assert.equal(
            app.sceneView,
            app:getActiveCenterView()
        )

        app.level:addLObject(10, 20)

        Assert.equal(
            true,
            app:startPlay()
        )

        Assert.equal(
            app.gameView,
            app:getActiveCenterView()
        )

        Assert.equal(
            true,
            app:stopPlay()
        )

        Assert.equal(
            app.sceneView,
            app:getActiveCenterView()
        )
    end
}

tests[#tests + 1] = {
    name = "editor f5 toggles play and stop",

    fn = function()
        local EditorApp =
            require("editor.app")

        local app =
            EditorApp.new()

        app.level:addLObject(10, 20)

        local oldIsDown =
            love.keyboard.isDown

        love.keyboard.isDown =
            function(...)
                return false
            end

        local startOk,
            started,
            startError =
            pcall(function()
                return app:keypressed("f5")
            end)

        if not startOk then
            love.keyboard.isDown =
                oldIsDown

            error(started)
        end

        Assert.equal(true, started)
        Assert.equal(nil, startError)
        Assert.equal(true, app:isPlaying())

        local stopOk,
            stopped,
            stopError =
            pcall(function()
                return app:keypressed("f5")
            end)

        love.keyboard.isDown =
            oldIsDown

        if not stopOk then
            error(stopped)
        end

        Assert.equal(true, stopped)
        Assert.equal(nil, stopError)
        Assert.equal(false, app:isPlaying())
    end
}

tests[#tests + 1] = {
    name = "editor blocks authoring keyboard shortcuts while playing",

    fn = function()
        local EditorApp =
            require("editor.app")

        local app =
            EditorApp.new()

        local original =
            app.level:addLObject(10, 20)

        app.sceneView.selectedLObject =
            original

        Assert.equal(
            true,
            app:startPlay()
        )

        local oldIsDown =
            love.keyboard.isDown

        love.keyboard.isDown =
            function(...)
                return false
            end

        local callOk, callError =
            pcall(function()
                app:keypressed("delete")
            end)

        love.keyboard.isDown =
            oldIsDown

        if not callOk then
            error(callError)
        end

        -- Game View가 활성화된 동안 Delete가
        -- 숨겨진 authoring Level을 수정하면 안 된다.
        Assert.equal(
            1,
            #app.level.lobjects
        )

        Assert.equal(
            original,
            app.level.lobjects[1]
        )
    end
}

tests[#tests + 1] = {
    name = "editor play start clears active scene drag state",

    fn = function()
        local EditorApp =
            require("editor.app")

        local app =
            EditorApp.new()

        app.level:addLObject(10, 20)

        app.sceneView.isDraggingLObject =
            true

        app.sceneView.isPanning =
            true

        Assert.equal(
            true,
            app:startPlay()
        )

        Assert.equal(
            false,
            app.sceneView.isDraggingLObject
        )

        Assert.equal(
            false,
            app.sceneView.isPanning
        )
    end
}

tests[#tests + 1] = {
    name = "runtime world update advances elapsed time",

    fn = function()
        local World = require("core.world")

        local world = World.new()

        Assert.equal(0, world.elapsedTime)

        local updated, updateError =
            world:update(0.25)

        Assert.equal(true, updated)
        Assert.equal(nil, updateError)
        Assert.equal(0.25, world.elapsedTime)

        Assert.equal(true, world:update(0.5))
        Assert.equal(0.75, world.elapsedTime)
    end
}

tests[#tests + 1] = {
    name = "runtime world rejects invalid delta time",

    fn = function()
        local World = require("core.world")

        local world = World.new()

        local updated, err =
            world:update(-0.1)

        Assert.equal(false, updated)
        Assert.truthy(err)
        Assert.equal(0, world.elapsedTime)
    end
}

tests[#tests + 1] = {
    name = "editor update advances runtime only while playing",

    fn = function()
        local EditorApp = require("editor.app")

        local app = EditorApp.new()
        app.level:addLObject(10, 20)

        -- Edit mode에서는 Runtime World 자체가 없으므로
        -- update가 authoring state를 변경하지 않는다.
        local updatedBeforePlay =
            app:update(0.25)

        Assert.equal(nil, updatedBeforePlay)
        Assert.equal(false, app:isPlaying())

        Assert.equal(true, app:startPlay())
        Assert.equal(0, app.runtimeWorld.elapsedTime)

        local updated, updateError =
            app:update(0.25)

        Assert.equal(true, updated)
        Assert.equal(nil, updateError)
        Assert.equal(0.25, app.runtimeWorld.elapsedTime)

        Assert.equal(true, app:update(0.5))
        Assert.equal(0.75, app.runtimeWorld.elapsedTime)
    end
}

tests[#tests + 1] = {
    name = "editor replay starts with fresh runtime clock",

    fn = function()
        local EditorApp = require("editor.app")

        local app = EditorApp.new()
        app.level:addLObject(10, 20)

        Assert.equal(true, app:startPlay())
        Assert.equal(true, app:update(1.5))
        Assert.equal(1.5, app.runtimeWorld.elapsedTime)

        Assert.equal(true, app:stopPlay())
        Assert.equal(true, app:startPlay())

        -- 새 Play session은 새 World이므로 Runtime clock도 초기화된다.
        Assert.equal(0, app.runtimeWorld.elapsedTime)
    end
}

tests[#tests + 1] = {
    name = "runtime lobject owns copied transform state",

    fn = function()
        local LObject =
            require("core.lobject")

        local initialState = {
            transform = {
                x = 10,
                y = 20
            }
        }

        local lobject, createError =
            LObject.new(7, initialState)

        Assert.equal(nil, createError)
        Assert.truthy(lobject)
        Assert.equal(7, lobject.runtimeId)
        Assert.equal(10, lobject.transform.x)
        Assert.equal(20, lobject.transform.y)

        initialState.transform.x = 999

        Assert.equal(10, lobject.transform.x)
    end
}

tests[#tests + 1] = {
    name = "runtime world owns runtime lobject instances",

    fn = function()
        local LObject =
            require("core.lobject")

        local World =
            require("core.world")

        local world = assert(
            World.fromLevelData({
                lobjects = {
                    {
                        transform = {
                            x = 10,
                            y = 20
                        }
                    }
                }
            })
        )

        local lobject =
            world.lobjects[1]

        Assert.equal(
            LObject,
            getmetatable(lobject)
        )

        Assert.equal(1, lobject.runtimeId)
    end
}

tests[#tests + 1] = {
    name = "runtime world delegates update to lobjects",

    fn = function()
        local World =
            require("core.world")

        local world = World.new()

        local lobject = assert(
            world:addLObject({
                transform = {
                    x = 10,
                    y = 20
                }
            })
        )

        local receivedDt = nil

        lobject.update =
            function(self, dt)
                receivedDt = dt
            end

        local updated, updateError =
            world:update(0.25)

        Assert.equal(true, updated)
        Assert.equal(nil, updateError)
        Assert.equal(0.25, receivedDt)
        Assert.equal(0.25, world.elapsedTime)
    end
}

tests[#tests + 1] = {
    name = "runtime world reports lobject update failure",

    fn = function()
        local World =
            require("core.world")

        local world = World.new()

        local lobject = assert(
            world:addLObject({
                transform = {
                    x = 10,
                    y = 20
                }
            })
        )

        lobject.update =
            function(self, dt)
                return false, "test failure"
            end

        local updated, err =
            world:update(0.25)

        Assert.equal(false, updated)
        Assert.truthy(err)

        -- 실패한 frame은 Runtime clock의 정상 진행으로 취급하지 않는다.
        Assert.equal(0, world.elapsedTime)
    end
}

tests[#tests + 1] = {
    name = "level lobject preserves definition reference when duplicated",

    fn = function()
        local Level = require("editor.level")

        local level = Level.new()

        local original, addError =
            level:addLObject(
                10,
                20,
                "player"
            )

        Assert.equal(nil, addError)
        Assert.truthy(original)
        Assert.equal(
            "player",
            original.definitionReference
        )

        local duplicate =
            level:duplicateLObject(
                original,
                30,
                40
            )

        Assert.truthy(duplicate)
        Assert.equal(
            "player",
            duplicate.definitionReference
        )
        Assert.equal(30, duplicate.transform.x)
        Assert.equal(40, duplicate.transform.y)
    end
}

tests[#tests + 1] = {
    name = "level serialization preserves definition reference",

    fn = function()
        local Level = require("editor.level")

        local level = Level.new()

        assert(
            level:addLObject(
                10,
                20,
                "enemy.basic"
            )
        )

        local data = level:toData()

        Assert.equal(
            "enemy.basic",
            data.lobjects[1].definitionReference
        )

        local loaded, loadError =
            Level.fromData(data)

        Assert.equal(nil, loadError)
        Assert.truthy(loaded)
        Assert.equal(
            "enemy.basic",
            loaded.lobjects[1].definitionReference
        )
    end
}

tests[#tests + 1] = {
    name = "runtime lobject keeps level definition reference",

    fn = function()
        local Level = require("editor.level")
        local World = require("core.world")

        local level = Level.new()

        assert(
            level:addLObject(
                10,
                20,
                "player"
            )
        )

        local world, worldError =
            World.fromLevelData(
                level:toData()
            )

        Assert.equal(nil, worldError)
        Assert.truthy(world)
        Assert.equal(
            "player",
            world.lobjects[1].definitionReference
        )
    end
}

tests[#tests + 1] = {
    name = "level and runtime reject invalid definition reference",

    fn = function()
        local Level = require("editor.level")
        local LObject = require("core.lobject")

        local level = Level.new()

        local added, addError =
            level:addLObject(
                10,
                20,
                ""
            )

        Assert.equal(nil, added)
        Assert.truthy(addError)
        Assert.equal(0, #level.lobjects)
        Assert.equal(1, level.nextAuthoringId)

        local runtimeLObject, runtimeError =
            LObject.new(
                1,
                {
                    definitionReference = "",
                    transform = {
                        x = 10,
                        y = 20
                    }
                }
            )

        Assert.equal(nil, runtimeLObject)
        Assert.truthy(runtimeError)
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