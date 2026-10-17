local tests = {}
for _, test in ipairs(require("tests.failureBoundaries")) do tests[#tests + 1] = test end
for _, suite in ipairs({"windowsExport", "gameCli", "sessionPersistence", "carryTransition", "publicRendering", "rendering", "codeEditor", "projectBrowser", "scopedScripts", "resourceLifecycle", "scriptEvents", "scriptRuntime", "attachedWorkflow", "plugins", "assetCatalog", "assetPlacement", "preview", "debugging", "uiTree", "viewportTools", "ime", "textEdit", "theme", "objectHierarchy"}) do
    for _, test in ipairs(require("tests." .. suite)) do tests[#tests + 1] = test end
end
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
