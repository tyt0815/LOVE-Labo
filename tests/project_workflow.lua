local Assert = require("tests.assert")
local Project = require("editor.project")
local FS = require("editor.host_filesystem")
local AssetBrowser = require("editor.asset_browser")
local ProjectStart = require("editor.project_start")
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

add("project start creates and reopens project and contains failures", function()
    fixture(function(parent)
        local opened
        local projectStart = ProjectStart.new(function(project) opened = EditorApp.new(nil, project); return true end)
        projectStart.path, projectStart.name = parent, "Launch"
        assert(projectStart:submit())
        Assert.equal("Launch", opened.project.name)
        Assert.truthy(opened.assetBrowser)
        Assert.equal(0, #opened.level.lobjects)
        local first = opened
        projectStart.mode, projectStart.path = "open", first.project.rootPath
        assert(projectStart:submit())
        Assert.equal(first.project.rootPath, opened.project.rootPath)
        projectStart.path = FS.join(parent, "Missing")
        local current = opened
        Assert.equal(false, projectStart:submit())
        Assert.equal(current, opened)
        Assert.truthy(projectStart.error)
        projectStart.path = "invalid\0path"
        Assert.equal(false, projectStart:submit())
        Assert.equal(current, opened)
    end)
end)

add("project start native Browse applies selection and preserves path on cancel or failure", function()
    fixture(function(parent)
        local chosen = FS.join(parent, "한글 폴더")
        assert(FS.mkdir(chosen))
        local nextPath, nextError, receivedPath, receivedTitle = (chosen:gsub("/", "\\"))
        local projectStart = ProjectStart.new(function() return true end, function(path, title)
            receivedPath, receivedTitle = path, title
            return nextPath, nextError
        end)
        projectStart.path = parent
        local browse = projectStart:layout().browse
        projectStart:mousepressed(browse.x + 5, browse.y + 5, 1)
        Assert.equal(parent, receivedPath)
        Assert.equal("새 프로젝트의 부모 폴더 선택", receivedTitle)
        Assert.equal(chosen, projectStart.path)
        Assert.equal("path", projectStart.activeField)
        nextPath = nil
        projectStart.mode = "open"
        projectStart:mousepressed(browse.x + 5, browse.y + 5, 1)
        Assert.equal("프로젝트 폴더 열기", receivedTitle)
        Assert.equal(chosen, projectStart.path)
        Assert.equal(nil, projectStart.error)
        nextError = "dialog failure"
        projectStart:mousepressed(browse.x + 5, browse.y + 5, 1)
        Assert.equal(chosen, projectStart.path)
        Assert.equal("dialog failure", projectStart.error)
        projectStart.selectFolder = function() error("unexpected dialog error") end
        projectStart:browse()
        Assert.equal(chosen, projectStart.path)
        Assert.truthy(projectStart.error:find("unexpected dialog error", 1, true))
        projectStart.activeField, projectStart.replace = "name", true
        projectStart:textinput("테스트")
        projectStart:keypressed("backspace")
        Assert.equal("테스", projectStart.name)
        projectStart:textinput("트")
        Assert.equal("테스트", projectStart.name)
        projectStart.activeField, projectStart.replace = "path", true
        projectStart:textinput("C:\\Projects\\테스트")
        Assert.equal("C:/Projects/테스트", projectStart.path)
        projectStart:textinput("\\Assets")
        Assert.equal("C:/Projects/테스트/Assets", projectStart.path)
        local originalIsDown, originalClipboard = love.keyboard.isDown, love.system.getClipboardText
        love.keyboard.isDown = function() return true end
        love.system.getClipboardText = function() return "D:\\붙여넣기\\Project" end
        projectStart.replace = true
        local ok, err = pcall(projectStart.keypressed, projectStart, "v")
        love.keyboard.isDown, love.system.getClipboardText = originalIsDown, originalClipboard
        if not ok then error(err, 0) end
        Assert.equal("D:/붙여넣기/Project", projectStart.path)
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

add("project start and editor UI render with isolated graphics state", function()
    fixture(function(parent)
        local project = assert(Project.create(parent, "Render"))
        local app = EditorApp.new(nil, project)
        local projectStart = ProjectStart.new(function() return true end)
        local width, height = love.graphics.getDimensions()
        local canvas = love.graphics.newCanvas(width, height)
        love.graphics.setCanvas(canvas)
        local ok, err = pcall(function()
            love.graphics.setColor(0.3, 0.4, 0.5, 1)
            local before = love.graphics.getColor()
            projectStart:draw()
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

add("startup without project option keeps project start screen", function()
    local startup = require("editor.startup")
    local projectStart = ProjectStart.new(function() error("unexpected open") end)
    local path = projectStart.path
    Assert.equal(nil, path:find("\\", 1, true))
    Assert.equal(false, startup.openRequestedProject({}, projectStart, "C:/Workspace"))
    Assert.equal("create", projectStart.mode)
    Assert.equal(path, projectStart.path)
    Assert.equal(nil, projectStart.error)
end)

add("startup opens absolute and relative project paths with spaces and unicode", function()
    fixture(function(parent)
        local project = assert(Project.create(parent, "테스트 프로젝트"))
        local opened
        local projectStart = ProjectStart.new(function(value)
            opened = EditorApp.new(nil, value)
            return true
        end)
        local startup = require("editor.startup")
        assert(startup.openRequestedProject({ "--project", project.rootPath:gsub("/", "\\") }, projectStart, "C:/Other"))
        Assert.equal(project.rootPath, opened.project.rootPath)
        Assert.truthy(opened.assetBrowser)
        opened = nil
        assert(startup.openRequestedProject({ "--project", "테스트 프로젝트" }, projectStart, parent))
        Assert.equal(project.rootPath, opened.project.rootPath)
        Assert.equal("open", projectStart.mode)
        Assert.equal(project.rootPath, projectStart.path)
        Assert.equal(nil, projectStart.error)
    end)
end)

add("startup rejects missing duplicate and invalid project paths without opening", function()
    fixture(function(parent)
        local startup = require("editor.startup")
        for _, args in ipairs({
            { "--project" }, { "--project", "" }, { "--project", "--other" },
            { "--project", "one", "--project", "two" }, { "--project", "Missing" }
        }) do
            local projectStart = ProjectStart.new(function() error("unexpected open") end)
            local opened, err = startup.openRequestedProject(args, projectStart, parent)
            Assert.equal(false, opened)
            Assert.truthy(err)
            Assert.equal("open", projectStart.mode)
            Assert.equal(err, projectStart.error)
        end
        Assert.equal(nil, FS.info(FS.join(parent, "Missing")))
        local project = assert(Project.create(parent, "Retry"))
        local opened
        local projectStart = ProjectStart.new(function(value) opened = value; return true end)
        startup.openRequestedProject({ "--project", "Missing" }, projectStart, parent)
        projectStart.path = project.rootPath
        assert(projectStart:submit())
        Assert.equal(project.rootPath, opened.rootPath)
        Assert.equal(nil, projectStart.error)
    end)
end)

return tests
