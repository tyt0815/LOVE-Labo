local Template = {}
Template.text = [=[-- Export는 고정 경로 Tools/Build.lua를 실행한다. 출력은 선택한 .love 파일 옆에 둔다.
return function(builder)
    builder:packageGame()
    -- CLI 모듈과 문서를 만든 뒤 필요한 항목을 활성화한다.
    -- builder:packageCli("Game-cli.exe", {entry = "Assets/Tools/GameCli.lua"})
    -- builder:copy("Docs/ContentGuide.md", "README.md")
end
]=]
return Template
