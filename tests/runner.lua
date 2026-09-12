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

        sceneView:wheelmoved(0, 1)

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

        sceneView:wheelmoved(0, -100)
        Assert.equal(0.25, sceneView.zoom)

        sceneView:wheelmoved(0, 100)
        Assert.equal(4.0, sceneView.zoom)
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