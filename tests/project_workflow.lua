local Assert = require("tests.assert")
local Project = require("editor.project")
local FS = require("editor.host_filesystem")
local AssetBrowser = require("editor.asset_browser")
local Launcher = require("editor.launcher")
local EditorApp = require("editor.app")
local tests = {}

local function add(name, fn) tests[#tests + 1] = { name = name, fn = fn } end

local function fixture(fn)
    local path = FS.join(love.filesystem.getSaveDirectory(), "project-test-" .. tostring(love.timer.getTime()):gsub("%.", "-"))
    assert(FS.mkdir(path))
    local function clean(root)
        for _, entry in ipairs(assert(FS.list(root))) do
            local child = FS.join(root, entry.name)
            if entry.type == "directory" and not entry.isLink then clean(child)
            elseif entry.type == "directory" then assert(FS.removeDirectory(child))
            else assert(FS.removeFile(child)) end
        end
        assert(FS.removeDirectory(root))
    end
    local ok, err = pcall(fn, path)
    clean(path)
    if not ok then error(err, 0) end
end

add("project creation persists metadata and unicode Assets paths", function()
    fixture(function(parent)
        local project = assert(Project.create(parent, "한글 프로젝트"))
        Assert.equal("한글 프로젝트", project.name)
        local bytes = assert(FS.read(FS.join(project.rootPath, Project.FILE_NAME)))
        Assert.truthy(bytes:find("한글 프로젝트", 1, true))
        local assets = FS.join(project.rootPath, "Assets")
        assert(FS.mkdir(FS.join(assets, "텍스처")))
        assert(FS.createFile(FS.join(assets, "이미지.png"), "image data"))
        assert(FS.createFile(FS.join(project.rootPath, "hidden.txt"), "outside assets"))
        local reopened = assert(Project.open(project.rootPath))
        local entries = assert(reopened:listAssets())
        Assert.equal(2, #entries)
        Assert.equal("directory", entries[1].type)
        Assert.equal("Assets/이미지.png", entries[2].reference)
        Assert.equal("image data", assert(FS.read(assert(reopened:resolvePath(entries[2].reference)))))
    end)
end)

add("project creation rejects existing folders without overwriting", function()
    fixture(function(parent)
        local existing = FS.join(parent, "Existing")
        assert(FS.mkdir(existing))
        assert(FS.createFile(FS.join(existing, "keep.txt"), "keep"))
        local project, err = Project.create(parent, "Existing")
        Assert.equal(nil, project)
        Assert.truthy(err)
        Assert.equal("keep", assert(FS.read(FS.join(existing, "keep.txt"))))
        Assert.equal(nil, FS.info(FS.join(existing, "Assets")))
        for _, name in ipairs({ "", "../escape", "CON", "name.", "bad/name", "bad\\name", "x:y" }) do
            Assert.equal(nil, Project.create(parent, name))
        end
    end)
end)

add("project creation cleans only its new directories on metadata failure", function()
    fixture(function(parent)
        local original = FS.createFile
        FS.createFile = function() return false, "simulated write failure" end
        local ok, project, err = pcall(Project.create, parent, "Failed")
        FS.createFile = original
        Assert.truthy(ok)
        Assert.equal(nil, project)
        Assert.equal("simulated write failure", err)
        Assert.equal(nil, FS.info(FS.join(parent, "Failed")))
    end)
end)

add("project open rejects missing malformed and unsupported project data", function()
    fixture(function(parent)
        Assert.equal(nil, Project.open(parent))
        local marker = FS.join(parent, Project.FILE_NAME)
        assert(FS.createFile(marker, "invalid json"))
        Assert.equal(nil, Project.open(parent))
        assert(FS.removeFile(marker))
        assert(FS.createFile(marker, '{"version":99,"name":"Test"}'))
        Assert.equal(nil, Project.open(parent))
        assert(FS.removeFile(marker))
        assert(FS.createFile(marker, '{"version":1,"name":"Test"}'))
        Assert.equal(nil, Project.open(parent))
        assert(FS.mkdir(FS.join(parent, "Assets")))
        Assert.truthy(Project.open(parent))
    end)
end)

add("asset listing stays within Assets and does not traverse links", function()
    fixture(function(parent)
        local project = assert(Project.create(parent, "Test"))
        for _, reference in ipairs({ "project.labo", "Assets/../", "Assets/../outside", "Assets2", "Assets//folder", "Assets/C:/", "Assets/folder.", "Assets/folder:stream" }) do
            Assert.equal(nil, project:listAssets(reference))
        end
        -- 실제 junction 생성 권한에 의존하지 않고 segment 검사를 확인한다.
        local original = FS.info
        FS.info = function(path)
            if path == FS.join(project.rootPath, "Assets/Link") then return { type = "directory", isLink = true } end
            return original(path)
        end
        local ok, entries = pcall(project.listAssets, project, "Assets/Link/Outside")
        FS.info = original
        Assert.truthy(ok)
        Assert.equal(nil, entries)
    end)
end)

add("asset browser navigates folders refreshes changes and preserves state on failure", function()
    fixture(function(parent)
        local project = assert(Project.create(parent, "Test"))
        local assets = FS.join(project.rootPath, "Assets")
        assert(FS.mkdir(FS.join(assets, "Sprites")))
        assert(FS.createFile(FS.join(assets, "Sprites/a.png"), "a"))
        local browser = AssetBrowser.new(project)
        Assert.equal(2, #browser.tree)
        assert(browser:openFolder("Assets/Sprites"))
        browser.selectedReference = "Assets/Sprites/a.png"
        assert(FS.createFile(FS.join(assets, "Sprites/b.png"), "b"))
        browser:refresh()
        Assert.equal(2, #browser.entries)
        Assert.equal("Assets/Sprites/a.png", browser.selectedReference)
        Assert.equal(false, browser:openFolder("Assets/Missing"))
        Assert.equal("Assets/Sprites", browser.folder)
        Assert.equal(2, #browser.entries)
        browser:goUp()
        Assert.equal("Assets", browser.folder)
        Assert.equal(false, browser:goUp())
        assert(browser:openFolder("Assets/Sprites"))
        assert(FS.removeFile(FS.join(assets, "Sprites/a.png")))
        assert(FS.removeFile(FS.join(assets, "Sprites/b.png")))
        assert(FS.removeDirectory(FS.join(assets, "Sprites")))
        browser:refresh()
        Assert.equal("Assets", browser.folder)
        Assert.truthy(browser.error)
        Assert.equal(0, #browser.entries)
    end)
end)

add("launcher creates and reopens project and contains failures", function()
    fixture(function(parent)
        local opened
        local launcher = Launcher.new(function(project) opened = EditorApp.new(nil, project); return true end)
        launcher.path, launcher.name = parent, "Launch"
        assert(launcher:submit())
        Assert.equal("Launch", opened.project.name)
        Assert.truthy(opened.assetBrowser)
        Assert.equal(0, #opened.level.lobjects)
        local first = opened
        launcher.mode, launcher.path = "open", first.project.rootPath
        assert(launcher:submit())
        Assert.equal(first.project.rootPath, opened.project.rootPath)
        launcher.path = FS.join(parent, "Missing")
        local current = opened
        Assert.equal(false, launcher:submit())
        Assert.equal(current, opened)
        Assert.truthy(launcher.error)
        launcher.path = "invalid\0path"
        Assert.equal(false, launcher:submit())
        Assert.equal(current, opened)
    end)
end)

add("launcher native Browse applies selection and preserves path on cancel or failure", function()
    fixture(function(parent)
        local chosen = FS.join(parent, "한글 폴더")
        assert(FS.mkdir(chosen))
        local nextPath, nextError, receivedPath, receivedTitle = chosen
        local launcher = Launcher.new(function() return true end, function(path, title)
            receivedPath, receivedTitle = path, title
            return nextPath, nextError
        end)
        launcher.path = parent
        local browse = launcher:layout().browse
        launcher:mousepressed(browse.x + 5, browse.y + 5, 1)
        Assert.equal(parent, receivedPath)
        Assert.equal("새 프로젝트의 부모 폴더 선택", receivedTitle)
        Assert.equal(chosen, launcher.path)
        Assert.equal("path", launcher.activeField)
        nextPath = nil
        launcher.mode = "open"
        launcher:mousepressed(browse.x + 5, browse.y + 5, 1)
        Assert.equal("프로젝트 폴더 열기", receivedTitle)
        Assert.equal(chosen, launcher.path)
        Assert.equal(nil, launcher.error)
        nextError = "dialog failure"
        launcher:mousepressed(browse.x + 5, browse.y + 5, 1)
        Assert.equal(chosen, launcher.path)
        Assert.equal("dialog failure", launcher.error)
        launcher.selectFolder = function() error("unexpected dialog error") end
        launcher:browse()
        Assert.equal(chosen, launcher.path)
        Assert.truthy(launcher.error:find("unexpected dialog error", 1, true))
        launcher.activeField, launcher.replace = "name", true
        launcher:textinput("테스트")
        launcher:keypressed("backspace")
        Assert.equal("테스", launcher.name)
        launcher:textinput("트")
        Assert.equal("테스트", launcher.name)
    end)
end)

add("asset browser scrolls long lists and keeps fractional wheel input clickable", function()
    fixture(function(parent)
        local project = assert(Project.create(parent, "Scroll"))
        for i = 1, 24 do
            assert(FS.mkdir(FS.join(project.rootPath, string.format("Assets/Folder%02d", i))))
        end
        local browser = AssetBrowser.new(project)
        browser:setBounds(0, 400, 900, 220)
        browser:wheelmoved(400, 450, -1.5)
        Assert.equal(4, browser.fileScroll)
        browser:mousepressed(400, 445, 1, 1)
        Assert.equal("Assets/Folder05", browser.selectedReference)
        browser:wheelmoved(20, 450, -100)
        Assert.truthy(browser.treeScroll > 0)
        Assert.equal(4, browser.fileScroll)
        browser:mousepressed(70, 445, 1)
        Assert.truthy(browser.folder ~= "Assets")
        browser:wheelmoved(400, 450, -100)
        Assert.equal(0, browser.fileScroll)
    end)
end)

add("editor bottom Assets layout routes inputs without changing lobject selection", function()
    fixture(function(parent)
        local project = assert(Project.create(parent, "Layout"))
        assert(FS.mkdir(FS.join(project.rootPath, "Assets/Folder")))
        local app = EditorApp.new(nil, project)
        local object = app.level:addLObject(0, 0)
        app.sceneView.selectedLObject = object
        app:updateSceneViewport()
        local width, height = love.graphics.getDimensions()
        local browser = app.assetBrowser
        Assert.equal(width - app.inspector.width, browser.width)
        Assert.equal(height - browser.height, app.sceneView.viewportHeight)
        Assert.equal(false, app.hierarchy:containsPoint(10, browser.y + 40))
        Assert.equal(false, app.sceneView:containsPoint(400, browser.y + 40))
        local fileX, fileY = browser:treeWidth() + 20, browser.y + 45
        app:mousepressed(fileX, fileY, 1, 1)
        Assert.equal("Assets/Folder", browser.selectedReference)
        Assert.equal(object, app.sceneView.selectedLObject)
        app:keypressed("delete")
        Assert.equal(1, #app.level.lobjects)
        app:mousepressed(fileX, fileY, 1, 2)
        Assert.equal("Assets/Folder", browser.folder)
        local buttons = browser:buttons()
        app:mousepressed(buttons.fold.x + 4, buttons.fold.y + 4, 1)
        Assert.equal(38, browser.height)
        Assert.equal(height - 38, app.hierarchy.height)
        app:mousepressed(buttons.fold.x + 4, browser.y + 12, 1)
        app:mousepressed(400, browser.y + 1, 1)
        app:mousemoved(400, height - 300, 0, -80)
        app:mousereleased(400, height - 300, 1)
        Assert.equal(300, browser.height)
        Assert.equal(false, app.isResizingAssets)
    end)
end)

add("launcher and editor UI render with isolated graphics state", function()
    fixture(function(parent)
        local project = assert(Project.create(parent, "Render"))
        local app = EditorApp.new(nil, project)
        local launcher = Launcher.new(function() return true end)
        local width, height = love.graphics.getDimensions()
        local canvas = love.graphics.newCanvas(width, height)
        love.graphics.setCanvas(canvas)
        local ok, err = pcall(function()
            love.graphics.setColor(0.3, 0.4, 0.5, 1)
            local before = love.graphics.getColor()
            launcher:draw()
            local r = love.graphics.getColor()
            Assert.equal(before, r)
            app:draw()
            Assert.equal(nil, love.graphics.getScissor())
        end)
        love.graphics.setCanvas()
        canvas:release()
        if not ok then error(err, 0) end
    end)
end)

return tests
