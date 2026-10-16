return function(builder)
    builder:packageGame()
    builder:packageCli("Game-cli.exe", {entry = "Assets/Examples/StageCommands.lua"})
    builder:copy("Docs/StageGuide.md", "README.md")
    builder:copy("Docs/StageSeed.json", "Content/Stage.json")
end
