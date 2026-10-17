local Examples = {}
local SOURCES = {
    StageModel = [=[local Model = {}
function Model.validate(data)
    assert(type(data) == "table" and data.version == 1 and type(data.notes) == "table", "Invalid stage")
    assert(type(data.name) == "string" and #data.name > 0, "Stage requires a name")
    for index, note in ipairs(data.notes) do
        assert(type(note) == "table" and type(note.beat) == "number" and note.beat >= 0 and note.beat < math.huge, "Invalid note beat: " .. index)
        assert(type(note.lane) == "number" and note.lane % 1 == 0 and note.lane >= 1 and note.lane <= 4, "Invalid note lane: " .. index)
    end
    for key in pairs(data.notes) do assert(type(key) == "number" and key >= 1 and key <= #data.notes and key % 1 == 0, "Invalid notes array") end
    return data
end
function Model.new(name) return {version = 1, name = name, notes = {}} end
function Model.add(data, beat, lane)
    Model.validate(data)
    data.notes[#data.notes + 1] = {beat = beat, lane = lane}
    return Model.validate(data)
end
function Model.moveFirst(data, direction)
    Model.validate(data)
    if data.notes[1] then data.notes[1].lane = math.max(1, math.min(4, data.notes[1].lane + direction)) end
    return Model.validate(data)
end
return Model
]=],
    StageCommands = [=[local Model = require("Examples.StageModel")
local function workspace(context) return assert(context.workspace, "Specify --workspace <absolute content folder>") end
return {summary = "Stage editor commands. The game and CLI share StageModel.", commands = {
    create = {summary = "Create a stage without replacing an existing file.", parameters = {
        file = {type = "string", default = "Stage.json"}, name = {type = "string", required = true}},
        run = function(context, args)
            return {revision = workspace(context):writeJson(args.file, Model.new(args.name), false)}
        end},
    inspect = {summary = "Read and validate a stage.", parameters = {file = {type = "string", default = "Stage.json"}},
        run = function(context, args)
            local data, revision = workspace(context):readJson(args.file)
            return {data = Model.validate(data), revision = revision}
        end},
    add = {summary = "Append a note, optionally checking the last observed revision.", parameters = {
        file = {type = "string", default = "Stage.json"}, beat = {type = "number", required = true},
        lane = {type = "integer", required = true}, revision = {type = "string"}},
        run = function(context, args)
            local target = workspace(context)
            local data, revision = target:readJson(args.file)
            assert(not args.revision or args.revision == revision, "Revision conflict")
            Model.add(data, args.beat, args.lane)
            return {revision = target:writeJson(args.file, data, revision), notes = #data.notes}
        end},
}}
]=],
    StageEditor = [=[local Model = require("Examples.StageModel")
local Workspace = require("project.Workspace")
local Editor = {properties = {workspace = {type = "string", default = ""}, drawOrder = {type = "number", default = 100}}}
function Editor:load(world)
    self.view = require("Engine.Rendering").createView(world, {owner = self, projection = {width = 1280, height = 720}})
    local root = self.workspace
    for index, value in ipairs(arg or {}) do if value == "--workspace" then root = arg[index + 1] end end
    if root == "" then root = love.filesystem.getSaveDirectory() .. "/Content/" .. self:getProject().saveIdentity end
    Workspace.ensureDirectory(root)
    self.content = Workspace.new(root)
    self.content:withLock(function()
        local Fs = require("project.NativeFileSystem")
        if not Fs.info(self.content:path("Stage.json")) then
            local data = Model.add(Model.new("My first stage"), 1, 2)
            self.content:writeJson("Stage.json", data, false)
        end
    end)
    self:reload()
end
function Editor:reload()
    local ok, err = pcall(function()
        self.content:withLock(function()
            local data, revision = self.content:readJson("Stage.json")
            self.data, self.revision = Model.validate(data), revision
        end)
    end)
    self.status = ok and "Reloaded Stage.json" or tostring(err)
end
function Editor:keypressed(key)
    if key == "r" then self:reload()
    elseif key == "left" or key == "right" then Model.moveFirst(self.data, key == "left" and -1 or 1); self.status = "Changed in memory; S saves"
    elseif key == "s" then
        local ok, err = pcall(function()
            self.content:withLock(function() self.revision = self.content:writeJson("Stage.json", Model.validate(self.data), self.revision) end)
        end)
        self.status = ok and "Saved Stage.json" or tostring(err)
    end
end
function Editor:draw(context)
    context:withScreen(function()
        love.graphics.setColor(0.08, 0.09, 0.11, 1); love.graphics.rectangle("fill", 0, 0, context.viewport.width, context.viewport.height)
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.print("Shared stage editor / game CLI: " .. (self.data and self.data.name or ""), 40, 30)
        love.graphics.printf(self.content.root, 40, 65, context.viewport.width - 80)
        love.graphics.print("Left/Right: move first note | S: save | R: reload external changes", 40, 110)
        love.graphics.print(self.status or "", 40, 145)
        local laneHeight = math.max(60, context.viewport.height - 240)
        for lane = 1, 4 do
            love.graphics.setColor(0.25, 0.27, 0.3, 1); love.graphics.rectangle("line", 80 + (lane - 1) * 130, 220, 110, laneHeight)
        end
        for _, note in ipairs(self.data and self.data.notes or {}) do
            love.graphics.setColor(0.15, 0.6, 1, 1); love.graphics.rectangle("fill", 90 + (note.lane - 1) * 130, 230 + note.beat * 28 % math.max(1, laneHeight - 30), 90, 16)
        end
    end)
end
function Editor:unload() if self.view then self.view:release() end end
return Editor
]=],
}
Examples.buildScript = [=[return function(builder)
    builder:packageGame()
    builder:packageCli("Game-cli.exe", {entry = "Assets/Examples/StageCommands.lua"})
    builder:copy("Docs/StageGuide.md", "README.md")
    builder:copy("Docs/StageSeed.json", "Content/Stage.json")
end
]=]
Examples.guide = [=[# 스테이지 제작

Game-cli.exe help 또는 schema로 명령과 인자를 조회합니다. Labo나 Python 설치는 필요하지 않습니다. EXE 옆의 DLL과 license-love.txt도 함께 배포합니다.

```powershell
./Game-cli.exe inspect --workspace C:/Games/MyGame/Content
./Game-cli.exe add --workspace C:/Games/MyGame/Content --beat 4 --lane 3
./Game.exe --workspace C:/Games/MyGame/Content
```

게임의 R 키로 CLI 저장 결과를 다시 읽습니다. 좌우 키로 첫 노트를 옮기고 S로 저장합니다. 스테이지 이름과 파란 노트가 같은 StageModel에서 검증됩니다. GUI의 미저장 수정은 CLI가 읽지 못하며, 외부 수정 후 S를 누르면 revision 충돌을 반환합니다. R은 미저장 변경을 버립니다.

복잡한 명령은 --request <UTF-8 JSON 절대 경로>로 전달합니다.

```json
{"command":"add","workspace":"C:/Games/MyGame/Content","arguments":{"beat":8,"lane":4}}
```

stdout은 {version:1,ok:true,result:...} 또는 {version:1,ok:false,error:...} JSON입니다. 종료 코드는 성공 0, 실패 1입니다. --result <절대 경로>는 같은 응답을 파일에 저장합니다. create는 기존 파일을 덮어쓰지 않습니다. add의 revision 인자는 inspect에서 읽은 revision과 같아야 합니다.

Stage.json: version=1, name=문자열, notes=[{beat=0 이상 수, lane=1~4 정수}]. 확장자나 도메인 형식은 게임이 정의합니다. 작업 폴더는 미리 생성하며 상대 파일 경로는 폴더 밖으로 나갈 수 없습니다. 작업 중 .labo-content.lock으로 같은 규칙을 사용하는 편집을 직렬화합니다. 강제 종료로 남은 잠금은 실행 중인 프로세스가 없을 때만 제거합니다.

배포용 Content/Stage.json은 빌드 예제의 초기 데이터입니다. 재Export는 이 파일을 다시 복사합니다. 제작한 콘텐츠는 별도 작업 폴더에서 관리하세요. --workspace를 생략한 게임은 저장 폴더 아래 자체 예제 데이터를 사용하고 화면에 경로를 표시합니다.
]=]
function Examples.create(project)
    local Fs = require("editor.HostFileSystem")
    local Workspace = require("project.Workspace")
    local root = Workspace.new(project.rootPath)
    local buildPath = require("editor.ProjectBuild").ensureScript(project)
    assert(assert(Fs.read(buildPath)) == require("editor.BuildTemplate").text, "Custom build script exists; example will not overwrite it")
    for name in pairs(SOURCES) do assert(not project:getAssetId("Assets/Examples/" .. name .. ".lua"), "CLI example already exists") end
    assert(not project:getAssetId("Assets/Examples/L_StageEditor.level"), "CLI example level already exists")
    for _, path in ipairs({"Docs/StageGuide.md", "Docs/StageSeed.json"}) do assert(not Fs.info(root:path(path)), "Example documentation already exists") end
    if not Fs.info(root:path("Assets/Examples")) then assert(project:createEntry("Assets", "folder", "Examples")) end
    for name, source in pairs(SOURCES) do
        assert(project:createEntry("Assets/Examples", "lua", name, {scriptKind = "script"}))
        assert(Fs.writeAtomic(assert(project:resolveSourceFile("Assets/Examples/" .. name .. ".lua")), source))
    end
    assert(project:createEntry("Assets/Examples", "level", "L_StageEditor"))
    local level = require("editor.Level").new()
    level.scripts = {{id = require("project.AssetId").new(), name = "stageEditor", source = project:getAssetId("Assets/Examples/StageEditor.lua")}}
    assert(Fs.writeAtomic(assert(project:resolveAssetFile("Assets/Examples/L_StageEditor.level")), assert(require("editor.LevelFile").encode(level))))
    root:write("Docs/StageGuide.md", Examples.guide, false)
    root:writeJson("Docs/StageSeed.json", {version = 1, name = "CLI demo", notes = {{beat = 1, lane = 2}}}, false)
    root:write("Tools/Build.lua", Examples.buildScript)
    assert(project:rebuildAssetIndex())
    return {level = project:getAssetId("Assets/Examples/L_StageEditor.level"), entry = "Assets/Examples/StageCommands.lua", script = buildPath}
end
return Examples
