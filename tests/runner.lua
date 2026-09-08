local Assert = require("tests.assert")

local tests = {}

-- 첫 테스트는 EditorApp module이 존재하고
-- 최소 생성 API를 제공하는지만 검증한다.
--
-- 지금 단계에서는 editor/app.lua를 만들지 않았으므로
-- 이 테스트가 실패하는 것이 정상이다.
tests[#tests + 1] = {
    name = "editor app module loads",

    fn = function()
        local EditorApp = require("editor.app")

        Assert.truthy(EditorApp)
        Assert.truthy(EditorApp.new)
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