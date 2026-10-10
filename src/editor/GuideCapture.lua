local Capture = {}
function Capture.run(args)
    local Fs, Json = require("editor.HostFileSystem"), require("project.Json")
    local directory
    for index, value in ipairs(args) do if value == "--capture-guide" then directory = args[index + 1] end end
    local ok, err = xpcall(function()
        assert(directory and directory:sub(1, 2) ~= "--", "--capture-guide requires a new output directory")
        assert(not Fs.info(directory), "Capture directory must not exist")
        assert(Fs.mkdir(directory))
        assert(love.window.setMode(1440, 900, {resizable = false}))
        local project = assert(require("editor.Project").create(directory, "GuideExample"))
        assert(project:createEntry("Assets", "level", "L_Start"))
        local app = require("editor.EditorApp").new(nil, project)
        assert(app:openProjectDocument("Assets/L_Start.level", true))
        app.sceneView.zoom = 0.5
        local report = {width = 1440, height = 900, images = {}}
        local function shot(name)
            local canvas = love.graphics.newCanvas(1440, 900)
            love.graphics.push("all"); love.graphics.setCanvas(canvas); love.graphics.clear(0.1, 0.1, 0.1, 1)
            app:draw(); love.graphics.setCanvas(); love.graphics.pop()
            local pixels = canvas:newImageData(); local png = pixels:encode("png")
            assert(Fs.writeAtomic(Fs.join(directory, name .. ".png"), png:getString()))
            png:release(); pixels:release(); canvas:release()
            report.images[#report.images + 1] = name
        end
        app:draw(); shot("level-details")
        app.sceneView:setSelection({app.level.lobjects[1]}); app.inspectorSource = "scene"; app:updateInspectorTarget()
        app.inspector.classInspector:selectComponent("camera"); shot("camera-details")
        assert(project:createEntry("Sources", "lua", "Player", {scriptKind = "lobject"}))
        assert(Fs.writeAtomic(assert(project:resolveSourceFile("Sources/Player.lua")), [[-- labo-script: lobject
local Engine = require("Engine")
local Player = {properties = {speed = {type = "number", default = 100, group = "Movement"}}}
function Player.build(self) self:setRootComponent("sprite", Engine.SpriteComponent) end
return Player
]]))
        local image = love.image.newImageData(64, 64)
        image:mapPixel(function() return 0.1, 0.65, 0.95, 1 end)
        local png = image:encode("png"); assert(Fs.writeAtomic(project:resolvePath("Assets/Player.png"), png:getString()))
        png:release(); image:release(); assert(project:rebuildAssetIndex())
        assert(project:createEntry("Assets", "prefab", "PF_Player", {scriptReference = project:getAssetId("Sources/Player.lua")}))
        local prefab = assert(require("editor.PrefabDocument").load(project, "Assets/PF_Player.prefab"))
        prefab.data.overrides.components = {sprite = {image = project:getAssetId("Assets/Player.png")}}
        assert(prefab:save(project))
        local object = app.level:addLObject(150, 0, project:getAssetId("Assets/PF_Player.prefab"), "PF_Player")
        app.assetBrowser:refresh(); app.sceneView:setSelection({object}); app:updateInspectorTarget()
        app.inspector.classInspector:selectComponent("sprite"); shot("sprite-details")
        assert(app.document:save())
        assert(app:inspectAsset("Assets/PF_Player.prefab")); shot("prefab-details")
        assert(app:startPlay()); shot("game-view"); app:stopPlay()
        assert(Fs.writeAtomic(Fs.join(directory, "report.json"), assert(Json.encode(report, true))))
    end, debug.traceback)
    if not ok then print(err) end
    love.event.quit(ok and 0 or 1)
end
return Capture
