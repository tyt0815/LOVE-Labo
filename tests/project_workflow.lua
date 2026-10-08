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
        Assert.equal(3, #entries)
        Assert.equal("directory", entries[1].type)
        Assert.equal("Assets/이미지.png", entries[3].reference)
        Assert.equal("image data", assert(FS.read(assert(reopened:resolvePath(entries[3].reference)))))
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

add("project creation cleans its level and directories on file creation failure", function()
    fixture(function(parent)
        local original = FS.createFile
        for _, target in ipairs({ Project.DEFAULT_SCRIPT_REFERENCE, Project.DEFAULT_LEVEL_REFERENCE, Project.FILE_NAME }) do
            FS.createFile = function(path, text)
                if path == FS.join(parent, "Failed/" .. target) then return false, "simulated write failure" end
                return original(path, text)
            end
            local ok, project, err = pcall(Project.create, parent, "Failed")
            FS.createFile = original
            Assert.truthy(ok)
            Assert.equal(nil, project)
            Assert.equal("simulated write failure", err)
            Assert.equal(nil, FS.info(FS.join(parent, "Failed")))
        end
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
        Assert.equal(5, #browser.tree)
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
        Assert.equal(1, #browser.entries)
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
        browser:setViewMode("list")
        browser:wheelmoved(400, 450, -1.5)
        Assert.equal(4, browser.fileScroll)
        browser:mousepressed(400, browser.fileSlot.widget.y + 5, 1, 1)
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
        local fileX, fileY = browser:treeWidth() + 20, browser.fileSlot.widget.y + 16
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

add("project creation writes an empty default level using the existing JSON format", function()
    fixture(function(parent)
        local project = assert(Project.create(parent, "기본 레벨"))
        local path = assert(project:resolvePath(Project.DEFAULT_LEVEL_REFERENCE))
        local text = assert(FS.read(path))
        local data = assert(require("editor.json").decode(text))
        Assert.equal(1, data.formatVersion)
        Assert.truthy(text:find('"lobjects": []', 1, true))
        local level = assert(require("editor.level_file").decode(text))
        Assert.equal(0, #level.lobjects)
        Assert.equal(1, level.nextAuthoringId)
        local browser = AssetBrowser.new(project)
        assert(browser:openFolder("Assets/Levels"))
        Assert.equal("Default.level", browser.entries[1].name)
        Assert.equal(Project.DEFAULT_LEVEL_REFERENCE, browser.entries[1].reference)
        assert(Project.open(project.rootPath))
        Assert.equal(text, assert(FS.read(path)))
    end)
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

add("asset view dropdown switches modes and protects scene input", function()
    fixture(function(parent)
        local project = assert(Project.create(parent, "Views"))
        local app = EditorApp.new(nil, project)
        local browser = app.assetBrowser
        local object = app.level:addLObject(0, 0)
        app.sceneView.selectedLObject = object
        Assert.equal("thumbnails", browser.viewMode)
        local dropdown = browser.viewDropdown
        app:mousepressed(dropdown.x + 10, dropdown.y + 10, 1)
        Assert.truthy(app.uiRoot.popup)
        app:keypressed("delete")
        Assert.equal(1, #app.level.lobjects)
        app:keypressed("down")
        app:keypressed("return")
        Assert.equal("list", browser.viewMode)
        Assert.equal(nil, app.uiRoot.popup)
        Assert.equal(object, app.sceneView.selectedLObject)
        app:mousepressed(dropdown.x + 10, dropdown.y + 10, 1)
        local menu = app.uiRoot.popup
        app:mousepressed(menu.x + 10, menu.y + 10, 1)
        Assert.equal("thumbnails", browser.viewMode)
        app:mousepressed(dropdown.x + 10, dropdown.y + 10, 1)
        local x, y = app.sceneView:worldToScreen(0, 0)
        app:mousepressed(x + 70, y, 1)
        Assert.equal(object, app.sceneView.selectedLObject)
        Assert.equal(nil, app.uiRoot.popup)
    end)
end)

add("thumbnail grid hit testing scroll and resizing agree on entry positions", function()
    fixture(function(parent)
        local project = assert(Project.create(parent, "Grid"))
        for i = 1, 30 do assert(FS.createFile(FS.join(project.rootPath, string.format("Assets/File%02d.txt", i)), "data")) end
        local browser = AssetBrowser.new(project)
        browser:setBounds(0, 400, 700, 220)
        local x, y = browser:treeWidth() + 20, browser.fileSlot.widget.y + 16
        Assert.equal("Assets/Levels", browser:getEntryAtPosition(x, y).reference)
        Assert.equal("Assets/File01.txt", browser:getEntryAtPosition(x + 112, y).reference)
        browser:wheelmoved(x, y, -1)
        local index = browser.fileScroll * browser:columns() + 1
        Assert.equal(browser.entries[index], browser:getEntryAtPosition(x, y))
        browser:setBounds(0, 400, 460, 220)
        index = browser.fileScroll * browser:columns() + 1
        Assert.equal(browser.entries[index], browser:getEntryAtPosition(browser:treeWidth() + 20, y))
        Assert.equal(nil, browser:getEntryAtPosition(browser.width - 1, y))
        local selected = browser.entries[index].reference
        browser.selectedReference = selected
        assert(browser:setViewMode("list"))
        Assert.equal(selected, browser.selectedReference)
        Assert.equal(0, browser.fileScroll)
    end)
end)

add("thumbnail previews load unicode images restore graphics and tolerate corrupt files", function()
    fixture(function(parent)
        local project = assert(Project.create(parent, "한글 이미지"))
        local data = love.image.newImageData(12, 6)
        for y = 0, 5 do for x = 0, 11 do data:setPixel(x, y, 0, 1, 0, 1) end end
        assert(FS.createFile(FS.join(project.rootPath, "Assets/미리보기.png"), data:encode("png"):getString()))
        data:release()
        assert(FS.createFile(FS.join(project.rootPath, "Assets/Broken.png"), "not an image"))
        local browser = AssetBrowser.new(project)
        local good, broken
        for _, entry in ipairs(browser.entries) do
            if entry.name == "미리보기.png" then good = entry end
            if entry.name == "Broken.png" then broken = entry end
        end
        local cache = browser.thumbnails
        local canvas = love.graphics.newCanvas(100, 100)
        love.graphics.setCanvas(canvas)
        love.graphics.setScissor(1, 2, 30, 40)
        cache:beginFrame()
        local image = cache:get(good)
        Assert.truthy(image)
        Assert.equal(88, image:getWidth())
        Assert.equal(canvas, love.graphics.getCanvas())
        Assert.equal(1, love.graphics.getScissor())
        Assert.equal(image, cache:get(good))
        Assert.equal(nil, cache:get(broken))
        love.graphics.setScissor()
        love.graphics.clear(0, 0, 0, 0)
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.draw(image)
        love.graphics.setCanvas()
        local rendered = canvas:newImageData()
        local r, g, b = rendered:getPixel(44, 44)
        Assert.truthy(g > 0.9 and r < 0.1 and b < 0.1)
        rendered:release(); canvas:release()
        browser:refresh()
        Assert.equal(nil, next(cache.entries))
        local original = FS.info
        FS.info = function(path)
            if path == FS.join(project.rootPath, good.reference) then return { type = "file", isLink = true } end
            return original(path)
        end
        cache:beginFrame()
        local ok, value = pcall(cache.get, cache, good)
        FS.info = original
        Assert.truthy(ok)
        Assert.equal(nil, value)
        cache:clear()
    end)
end)

add("editor shared borders resize panels with pointer capture and preserve centered viewport", function()
    fixture(function(parent)
        local app = EditorApp.new(nil, assert(Project.create(parent, "Resize")))
        local width, height = love.graphics.getDimensions()
        app:mousepressed(app.hierarchy.width, 150, 1)
        Assert.equal(app.sceneWidget, app.uiRoot.focused)
        app:mousemoved(300, 150, 80, 0)
        app:mousereleased(300, 150, 1)
        Assert.equal(300, app.hierarchy.width)
        Assert.equal(300, app.sceneView.viewportX)
        local edge = width - app.inspector.width
        app:mousepressed(edge, 150, 1)
        app:mousemoved(width - 280, 150, -40, 0)
        app:mousereleased(width - 280, 150, 1)
        Assert.equal(280, app.inspector.width)
        local top = app.assetBrowser.y
        app:mousepressed(300, top, 1)
        app:mousemoved(340, height - 300, 40, -80)
        app:mousereleased(-100, -100, 1)
        Assert.equal(340, app.hierarchy.width)
        Assert.equal(300, app.assetBrowser.height)
        Assert.equal(nil, app.uiRoot.captured)
        local x, y = app.sceneView:worldToScreen(0, 0)
        Assert.equal(app.sceneView.viewportX + app.sceneView.viewportWidth / 2, x)
        Assert.equal(app.sceneView.viewportHeight / 2, y)
    end)
end)

add("browser separates Assets and Sources and breadcrumb navigates without Up button", function()
    fixture(function(parent)
        local project = assert(Project.create(parent, "Navigation"))
        assert(FS.mkdir(FS.join(project.rootPath, "Sources/Levels/Extra")))
        local app = EditorApp.new(nil, project)
        local browser = app.assetBrowser
        local found = {}
        for _, node in ipairs(browser.tree) do found[node.reference] = true end
        Assert.truthy(found.Assets and found.Sources and found["Sources/Levels"])
        Assert.equal(nil, browser:buttons().up)
        Assert.equal(browser.x + browser.width - 218, browser.viewDropdown.x)
        Assert.truthy(browser.viewDropdown.x + browser.viewDropdown.width < browser:buttons().refresh.x)
        assert(browser:openFolder("Sources/Levels/Extra"))
        Assert.equal("Sources/Levels/Extra", browser.breadcrumb.path)
        local items = browser.breadcrumb:items()
        app:mousepressed(items[2].x + 4, items[2].y + 4, 1)
        Assert.equal("Sources/Levels", browser.folder)
        items = browser.breadcrumb:items()
        app:mousepressed(items[1].x + 4, items[1].y + 4, 1)
        Assert.equal("Sources", browser.folder)
        Assert.equal(false, browser:goUp())
        assert(browser:openFolder("Sources/Levels"))
        Assert.equal(Project.DEFAULT_SCRIPT_REFERENCE, browser.entries[2].reference)
        for _, reference in ipairs({ "Sources/../Assets", "Sources//Levels", "Other", "Sources/Levels/../../Other" }) do
            Assert.equal(nil, project:listDirectory(reference))
        end
    end)
end)

add("legacy projects keep working without Sources or script metadata", function()
    fixture(function(parent)
        assert(FS.mkdir(FS.join(parent, "Assets")))
        assert(FS.createFile(FS.join(parent, Project.FILE_NAME), '{"version":1,"name":"Legacy"}'))
        local project = assert(Project.open(parent))
        local app = EditorApp.new(nil, project)
        assert(app.assetBrowser:openFolder("Sources"))
        Assert.equal(0, #app.assetBrowser.entries)
        Assert.equal(nil, FS.info(FS.join(parent, "Sources")))
        Assert.equal(nil, app.level.scriptReference)
        Assert.equal(nil, app.document.path)
        assert(app:startPlay())
        assert(app:update(0.5))
        assert(app:stopPlay())
    end)
end)

add("default level links source script and runs only on independent runtime world", function()
    fixture(function(parent)
        local project = assert(Project.create(parent, "스크립트 테스트"))
        local app = EditorApp.new(nil, project)
        Assert.equal(Project.DEFAULT_LEVEL_REFERENCE, app.documentReference)
        Assert.equal(Project.DEFAULT_SCRIPT_REFERENCE, app.level.scriptReference)
        Assert.equal(false, app.document:isDirty())
        local sourcePath = assert(project:resolveSourceFile(Project.DEFAULT_SCRIPT_REFERENCE))
        assert(FS.removeFile(sourcePath))
        assert(FS.createFile(sourcePath, [[local Level = {}
local calls = 0
function Level.load(world)
    world:addLObject({transform = {x = 10, y = 20}})
end
function Level.update(world, dt)
    calls = calls + 1
    world.calls = calls
    world.lobjects[1].transform.x = world.lobjects[1].transform.x + dt * 10
end
return Level
]]))
        assert(app:startPlay())
        Assert.equal(1, #app.runtimeWorld.lobjects)
        assert(app:update(0.5))
        Assert.equal(15, app.runtimeWorld.lobjects[1].transform.x)
        Assert.equal(0, #app.level.lobjects)
        Assert.equal(false, app.document:isDirty())
        Assert.equal(1, app.runtimeWorld.calls)
        assert(app:stopPlay())
        assert(app:startPlay())
        assert(app:update(0.1))
        Assert.equal(1, app.runtimeWorld.calls)
        assert(app:stopPlay())
        app.level:addLObject(30, 40)
        assert(app:saveCurrentDocument())
        local loaded = assert(require("editor.level_file").load(app.document.path))
        Assert.equal(Project.DEFAULT_SCRIPT_REFERENCE, loaded.scriptReference)
        Assert.equal(1, #loaded.lobjects)
        assert(app:saveCurrentDocument())
        Assert.equal(nil, FS.info(app.document.path .. ".tmp"))
        Assert.equal(nil, FS.info(app.document.path .. ".bak"))
    end)
end)

add("script load update and path failures are contained in the editor", function()
    fixture(function(parent)
        local project = assert(Project.create(parent, "Failures"))
        local app = EditorApp.new(nil, project)
        local sourcePath = assert(project:resolveSourceFile(Project.DEFAULT_SCRIPT_REFERENCE))
        for _, source in ipairs({ "not valid Lua", "error('chunk failure')", "return 42", "return {load = 42}",
            "return {load = function() error('load failure') end}",
            "return setmetatable({}, {__index = function() error('property failure') end})" }) do
            assert(FS.removeFile(sourcePath))
            assert(FS.createFile(sourcePath, source))
            local playing, err = app:startPlay()
            Assert.equal(false, playing)
            Assert.truthy(err)
            Assert.equal(nil, app.runtimeWorld)
            Assert.truthy(app.runtimeError)
        end
        assert(FS.removeFile(sourcePath))
        assert(FS.createFile(sourcePath, "return {update = function() error('update failure') end}"))
        assert(app:startPlay())
        Assert.equal(false, app:update(0.1))
        Assert.equal(nil, app.runtimeWorld)
        Assert.truthy(app.runtimeError:find("update failure", 1, true))
        assert(FS.removeFile(sourcePath))
        Assert.equal(false, app:startPlay())
        for _, reference in ipairs({ "Assets/x.lua", "Sources/../outside.lua", "Sources//x.lua", "Sources/x.txt", "C:/x.lua" }) do
            Assert.equal(false, app.level:setScriptReference(reference))
            Assert.equal(nil, project:resolveSourceFile(reference))
        end
        local original = FS.info
        FS.info = function(path)
            if path == FS.join(project.rootPath, "Sources") then return { type = "directory", isLink = true } end
            return original(path)
        end
        local ok, path = pcall(project.resolveSourceFile, project, Project.DEFAULT_SCRIPT_REFERENCE)
        FS.info = original
        Assert.truthy(ok)
        Assert.equal(nil, path)
    end)
end)

add("level JSON preserves script references and rejects invalid references", function()
    local LevelFile = require("editor.level_file")
    local Level = require("editor.level")
    local level = Level.new()
    assert(level:setScriptReference(Project.DEFAULT_SCRIPT_REFERENCE))
    local loaded = assert(LevelFile.decode(assert(LevelFile.encode(level))))
    Assert.equal(Project.DEFAULT_SCRIPT_REFERENCE, loaded.scriptReference)
    Assert.equal(nil, LevelFile.decode('{"formatVersion":1,"lobjects":[],"scriptReference":"Sources/../bad.lua"}'))
    level.scriptReference = "Sources//bad.lua"
    Assert.equal(nil, LevelFile.encode(level))
    local legacy = assert(LevelFile.decode('{"formatVersion":1,"lobjects":[]}'))
    Assert.equal(nil, legacy.scriptReference)
end)

add("failed Unicode level replacement restores existing file", function()
    fixture(function(parent)
        local project = assert(Project.create(parent, "저장 복구"))
        local LevelFile = require("editor.level_file")
        local path = assert(project:resolveAssetFile(Project.DEFAULT_LEVEL_REFERENCE))
        local before = assert(FS.read(path))
        local level = assert(LevelFile.load(path))
        level:addLObject(10, 20)
        local original = FS.rename
        FS.rename = function(source, target)
            if source == path .. ".tmp" then return false, "simulated replacement failure" end
            return original(source, target)
        end
        local ok, saved, err = pcall(LevelFile.save, path, level)
        FS.rename = original
        Assert.truthy(ok)
        Assert.equal(false, saved)
        Assert.truthy(err)
        Assert.equal(before, assert(FS.read(path)))
        Assert.equal(nil, FS.info(path .. ".tmp"))
        Assert.equal(nil, FS.info(path .. ".bak"))
    end)
end)

add("new browser entries create linked levels and never overwrite files", function()
    fixture(function(parent)
        local project = assert(Project.create(parent, "Entries"))
        assert(project:createEntry("Assets", "folder", "한글"))
        local ok, reference = project:createEntry("Assets/한글", "level", "Stage.LEVEL")
        Assert.truthy(ok)
        Assert.equal("Assets/한글/Stage.level", reference)
        local level = assert(require("editor.level_file").load(assert(project:resolveAssetFile(reference))))
        Assert.equal("Sources/한글/Stage.lua", level.scriptReference)
        local source = assert(FS.read(assert(project:resolveSourceFile(level.scriptReference))))
        Assert.equal(require("editor.level_script_template"), source)
        Assert.equal(false, project:createEntry("Assets/한글", "level", "Stage"))
        Assert.equal(source, assert(FS.read(assert(project:resolveSourceFile(level.scriptReference)))))
        assert(project:createEntry("Sources/한글", "lua", "Extra"))
        Assert.equal(false, project:createEntry("Assets", "lua", "Bad"))
        Assert.equal(false, project:createEntry("Sources", "level", "Bad"))
        for _, name in ipairs({ "../escape", "CON", "bad/name", "trailing." }) do
            Assert.equal(false, project:createEntry("Assets", "folder", name))
        end
        Assert.equal(false, project:createEntry("Outside", "folder", "Bad"))
    end)
end)

add("new level failure rolls back its script and newly created source directories", function()
    fixture(function(parent)
        local project = assert(Project.create(parent, "Rollback"))
        assert(project:createEntry("Assets", "folder", "Nested"))
        local original = FS.createFile
        FS.createFile = function(path, text)
            if path == FS.join(project.rootPath, "Assets/Nested/Fail.level") then return false, "write failed" end
            return original(path, text)
        end
        local called, ok, err = pcall(project.createEntry, project, "Assets/Nested", "level", "Fail")
        FS.createFile = original
        Assert.truthy(called)
        Assert.equal(false, ok)
        Assert.equal("write failed", err)
        Assert.equal(nil, FS.info(FS.join(project.rootPath, "Sources/Nested")))
        Assert.truthy(FS.info(FS.join(project.rootPath, "Assets/Nested")))
    end)
end)

add("entry deletion removes nested contents but protects roots default level and links", function()
    fixture(function(parent)
        local project = assert(Project.create(parent, "Delete"))
        assert(project:createEntry("Sources", "folder", "Temporary"))
        assert(project:createEntry("Sources/Temporary", "lua", "A"))
        assert(project:createEntry("Sources/Temporary", "folder", "Nested"))
        assert(project:createEntry("Sources/Temporary/Nested", "lua", "B"))
        Assert.equal(false, project:deleteEntry("Assets"))
        Assert.equal(false, project:deleteEntry("Sources"))
        Assert.equal(false, project:deleteEntry("Assets/Levels"))
        project.defaultLevelReference = project.defaultLevelReference:lower()
        Assert.equal(false, project:deleteEntry("Assets/Levels/Default.level"))
        Assert.equal(false, project:deleteEntry("../outside"))
        local original = FS.info
        FS.info = function(path)
            if path == FS.join(project.rootPath, "Sources/Temporary/Nested") then return {type = "directory", isLink = true} end
            return original(path)
        end
        local called, ok = pcall(project.deleteEntry, project, "Sources/Temporary")
        FS.info = original
        Assert.truthy(called)
        Assert.equal(false, ok)
        Assert.truthy(FS.info(FS.join(project.rootPath, "Sources/Temporary/A.lua")))
        assert(project:deleteEntry("Sources/Temporary"))
        Assert.equal(nil, FS.info(FS.join(project.rootPath, "Sources/Temporary")))
    end)
end)

add("browser context menus create entries and delete only after confirmation", function()
    fixture(function(parent)
        local project = assert(Project.create(parent, "Menus"))
        local app = EditorApp.new(nil, project)
        local browser, root = app.assetBrowser, app.uiRoot
        local x, y = browser.fileSlot.widget.x + 20, browser.fileSlot.widget.y + 20
        app:mousepressed(x, y, 2)
        Assert.equal("Assets/Levels", browser.selectedReference)
        Assert.equal(2, #root.popup.panels[1].items)
        root:keypressed("escape")
        local gapX = browser.fileSlot.widget.x + 8 + 108
        app:mousepressed(gapX, y, 2)
        Assert.equal(1, #root.popup.panels[1].items)
        root:keypressed("escape")
        app:mousepressed(browser.x + browser.width - 20, y, 2)
        Assert.equal(1, #root.popup.panels[1].items)
        root:keypressed("right")
        Assert.equal(3, #root.popup.panels[2].items)
        root:keypressed("return")
        app:textinput("Temporary")
        app:keypressed("return")
        Assert.equal(nil, root.popup)
        Assert.truthy(FS.info(FS.join(project.rootPath, "Assets/Temporary")))
        browser:showDeleteDialog({reference = "Assets/Temporary", type = "directory"})
        root:keypressed("escape")
        Assert.truthy(FS.info(FS.join(project.rootPath, "Assets/Temporary")))
        browser:showDeleteDialog({reference = "Assets/Temporary", type = "directory"})
        root:keypressed("return")
        Assert.equal(nil, FS.info(FS.join(project.rootPath, "Assets/Temporary")))
        assert(project:createEntry("Assets", "level", "Open"))
        assert(app:openProjectDocument("Assets/Open.level"))
        browser:showDeleteDialog({reference = "Assets/Open.level", type = "file"})
        root:keypressed("return")
        Assert.truthy(root.popup.error:find("currently open", 1, true))
        Assert.truthy(FS.info(FS.join(project.rootPath, "Assets/Open.level")))
    end)
end)

return tests
