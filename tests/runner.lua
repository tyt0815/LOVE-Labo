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
