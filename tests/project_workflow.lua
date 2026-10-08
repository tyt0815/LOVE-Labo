local Assert = require("tests.assert")
local Project = require("editor.project")
local FS = require("editor.host_filesystem")
local AssetBrowser = require("editor.asset_browser")
local ProjectStart = require("editor.project_start")
local EditorApp = require("editor.app")
local tests = {}
local DEFAULT_LEVEL_REFERENCE = "Assets/Levels/StartLevel.level"
local DEFAULT_SCRIPT_REFERENCE = "Sources/Levels/StartLevel.lua"

-- 기본 레벨이 지정된 기존 프로젝트 흐름의 테스트 데이터를 명시적으로 구성한다.
local function createSampleProject(parent, name)
    local project = assert(Project.create(parent, name))
    assert(project:createEntry("Sources", "folder", "Levels"))
    assert(project:createEntry("Sources/Levels", "lua", "StartLevel", {scriptKind = "level"}))
    assert(project:createEntry("Assets", "folder", "Levels"))
    assert(project:createEntry("Assets/Levels", "level", "StartLevel", {scriptReference = DEFAULT_SCRIPT_REFERENCE}))
    local marker = FS.join(project.rootPath, Project.FILE_NAME)
    local Json = require("editor.json")
    local data = assert(Json.decode(assert(FS.read(marker))))
    data.defaultLevelReference = project:getAssetId(DEFAULT_LEVEL_REFERENCE)
    assert(FS.writeAtomic(marker, assert(Json.encode(data))))
    return assert(Project.open(project.rootPath))
end

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

add("project creation retains final composing Hangul with Enter or submit click", function()
    fixture(function(parent)
        local IME = require("editor.ui.ime")
        for _, mode in ipairs({"enter", "click"}) do
            IME.update()
            local created
            local start = ProjectStart.new(function(project) created = project; return true end)
            start:setPath(parent)
            start:textinput(mode .. "한")
            start:textedited("글")
            if mode == "enter" then start:keypressed("return")
            else
                local rect = start:layout().submit
                start:mousepressed(rect.x + 1, rect.y + 1, 1)
            end
            Assert.truthy(created)
            Assert.equal(mode .. "한글", assert(Project.open(created.rootPath)).name)
            IME.update()
        end
    end)
end)

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

add("project creation cleans its empty directories on marker creation failure", function()
    fixture(function(parent)
        local original = FS.createFile
        for _, target in ipairs({ Project.FILE_NAME }) do
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
        local project = assert(createSampleProject(parent, "Test"))
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
        local project = assert(createSampleProject(parent, "Test"))
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
        assert(FS.removeFile(FS.join(assets, "Sprites/a.png.meta")))
        assert(FS.removeFile(FS.join(assets, "Sprites/b.png.meta")))
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
        local project = assert(createSampleProject(parent, "Scroll"))
        for i = 1, 24 do
            assert(FS.mkdir(FS.join(project.rootPath, string.format("Assets/Folder%02d", i))))
        end
        local browser = AssetBrowser.new(project)
        browser:setBounds(0, 400, 900, 220)
        browser:setViewMode("list")
        browser:wheelmoved(400, browser.fileSlot.widget.y + 5, -1.5)
        Assert.equal(4, browser.fileScroll)
        browser:mousepressed(400, browser.fileSlot.widget.y + 5, 1, 1)
        Assert.equal("Assets/Folder05", browser.selectedReference)
        browser:wheelmoved(20, browser.treeSlot.widget.y + 5, -100)
        Assert.truthy(browser.treeScroll > 0)
        Assert.equal(4, browser.fileScroll)
        browser:mousepressed(70, browser.treeSlot.widget.y + 5, 1)
        browser.localRoot:mousereleased(70, browser.treeSlot.widget.y + 5, 1)
        Assert.truthy(browser.folder ~= "Assets")
        browser:wheelmoved(400, browser.fileSlot.widget.y + 5, -100)
        Assert.equal(0, browser.fileScroll)
    end)
end)

add("editor bottom Assets layout routes inputs without changing lobject selection", function()
    fixture(function(parent)
        local project = assert(createSampleProject(parent, "Layout"))
        assert(FS.mkdir(FS.join(project.rootPath, "Assets/Folder")))
        local app = EditorApp.new(nil, project)
        local object = app.level:addLObject(0, 0)
        app.sceneView.selectedLObject = object
        app:updateSceneViewport()
        local width, height = love.graphics.getDimensions()
        local browser = app.assetBrowser
        Assert.equal(width - app.inspector.width, browser.width)
        Assert.equal(height - app.statusHeight - browser.height, app.sceneView.viewportHeight)
        Assert.equal(false, app.hierarchy:containsPoint(10, browser.y + 40))
        Assert.equal(false, app.sceneView:containsPoint(400, browser.y + 40))
        local fileX, fileY = browser.fileSlot.widget.x + require("editor.ui").metrics.contentPaddingX + 4, browser.fileSlot.widget.y + 16
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
        Assert.equal(height - app.statusHeight - 38, app.hierarchy.height)
        app:mousepressed(buttons.fold.x + 4, browser.y + 12, 1)
        app:mousepressed(400, browser.y + 1, 1)
        app:mousemoved(400, height - 300, 0, -80)
        app:mousereleased(400, height - 300, 1)
        Assert.equal(300 - app.statusHeight, browser.height)
        Assert.equal(false, app.isResizingAssets)
    end)
end)

add("project start and editor UI render with isolated graphics state", function()
    fixture(function(parent)
        local project = assert(createSampleProject(parent, "Render"))
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

add("new projects open unsaved empty levels and create files only on first save", function()
    fixture(function(parent)
        local project = assert(Project.create(parent, "빈 프로젝트"))
        Assert.equal(nil, project.defaultLevelReference)
        Assert.equal(0, #assert(project:listDirectory("Assets")))
        Assert.equal(0, #assert(project:listDirectory("Sources")))
        local app = EditorApp.new(nil, project)
        Assert.equal(nil, app.document.path)
        Assert.equal(nil, app.level.scriptReference)
        assert(app:startPlay())
        assert(app:stopPlay())
        app.level:addLObject(12, 34)
        assert(app:saveCurrentDocument())
        app:textinput("Assets/First.level")
        app:keypressed("return")
        Assert.equal(nil, app.uiRoot.popup)
        Assert.equal(project:getAssetId("Assets/First.level"), app.documentAssetId)
        Assert.equal(false, app.document:isDirty())
        Assert.equal(1, #app.assetBrowser.entries)
        local saved = assert(require("editor.level_file").load(app.document.path))
        Assert.equal(12, saved.lobjects[1].transform.x)
        Assert.equal(nil, saved.scriptReference)
        app.level.lobjects[1].transform.x = 56
        assert(app:saveCurrentDocument())
        Assert.equal(56, assert(require("editor.level_file").load(app.document.path)).lobjects[1].transform.x)
        local reopened = assert(Project.open(project.rootPath))
        Assert.equal(nil, EditorApp.new(nil, reopened).document.path)
        assert(app:openProjectDocument("Assets/First.level"))
        Assert.equal(56, app.level.lobjects[1].transform.x)
    end)
end)

add("first save cancellation conflicts and failures preserve the unsaved level", function()
    fixture(function(parent)
        local project = assert(Project.create(parent, "SaveErrors"))
        local app = EditorApp.new(nil, project)
        app.level:addLObject(1, 2)
        assert(app:saveCurrentDocument())
        app:keypressed("escape")
        Assert.equal(nil, app.document.path)
        Assert.truthy(app.document:isDirty())
        assert(project:createEntry("Assets", "level", "Existing"))
        local before = assert(FS.read(assert(project:resolvePath("Assets/Existing.level"))))
        Assert.equal(false, app:saveNewLevel("Assets/Existing.level"))
        Assert.equal(before, assert(FS.read(assert(project:resolvePath("Assets/Existing.level")))))
        for _, reference in ipairs({"Sources/Bad.level", "Assets/../Bad.level", "Assets/Missing/Bad.level", "Assets/Bad.lua"}) do
            Assert.equal(false, app:saveNewLevel(reference))
        end
        local original = FS.createFile
        FS.createFile = function(path, text)
            if path:match("First.level.meta$") then return false, "metadata failed" end
            return original(path, text)
        end
        local called, saved = pcall(app.saveNewLevel, app, "Assets/First.level")
        FS.createFile = original
        Assert.truthy(called)
        Assert.equal(false, saved)
        Assert.equal(nil, FS.info(assert(project:resolvePath("Assets/First.level"))))
        Assert.equal(nil, app.document.path)
        Assert.equal(1, #app.level.lobjects)
        Assert.truthy(app.document:isDirty())
    end)
end)

add("startup opens absolute and relative project paths with spaces and unicode", function()
    fixture(function(parent)
        local project = assert(createSampleProject(parent, "테스트 프로젝트"))
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
        local project = assert(createSampleProject(parent, "Retry"))
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
        local project = assert(createSampleProject(parent, "Views"))
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
        local project = assert(createSampleProject(parent, "Grid"))
        for i = 1, 30 do assert(FS.createFile(FS.join(project.rootPath, string.format("Assets/File%02d.txt", i)), "data")) end
        local browser = AssetBrowser.new(project)
        browser:setBounds(0, 400, 700, 220)
        local x, y = browser.fileSlot.widget.x + require("editor.ui").metrics.contentPaddingX + 4, browser.fileSlot.widget.y + 16
        Assert.equal("Assets/Levels", browser:getEntryAtPosition(x, y).reference)
        Assert.equal("Assets/File01.txt", browser:getEntryAtPosition(x + 112, y).reference)
        browser:wheelmoved(x, y, -1)
        local index = browser.fileScroll * browser:columns() + 1
        Assert.equal(browser.entries[index], browser:getEntryAtPosition(x, y))
        browser:setBounds(0, 400, 460, 220)
        index = browser.fileScroll * browser:columns() + 1
        Assert.equal(browser.entries[index], browser:getEntryAtPosition(browser.fileSlot.widget.x + require("editor.ui").metrics.contentPaddingX + 4, y))
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
        local project = assert(createSampleProject(parent, "한글 이미지"))
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
        local app = EditorApp.new(nil, assert(createSampleProject(parent, "Resize")))
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
        Assert.equal(300 - app.statusHeight, app.assetBrowser.height)
        Assert.equal(nil, app.uiRoot.captured)
        local x, y = app.sceneView:worldToScreen(0, 0)
        Assert.equal(app.sceneView.viewportX + app.sceneView.viewportWidth / 2, x)
        Assert.equal(app.sceneView.viewportHeight / 2, y)
    end)
end)

add("browser separates Assets and Sources and breadcrumb navigates without Up button", function()
    fixture(function(parent)
        local project = assert(createSampleProject(parent, "Navigation"))
        assert(FS.mkdir(FS.join(project.rootPath, "Sources/Levels/Extra")))
        local app = EditorApp.new(nil, project)
        local browser = app.assetBrowser
        local found = {}
        for _, node in ipairs(browser.tree) do found[node.reference] = true end
        Assert.truthy(found.Assets and found.Sources and found["Sources/Levels"])
        Assert.equal(nil, browser:buttons().up)
        Assert.equal(browser:buttons().refresh.x - browser.viewDropdown.width - 8, browser.viewDropdown.x)
        Assert.truthy(browser.viewDropdown.x + browser.viewDropdown.width < browser:buttons().refresh.x)
        assert(browser:openFolder("Sources/Levels/Extra"))
        Assert.equal("Sources/Levels/Extra", browser.breadcrumb.path)
        local items = browser.breadcrumb:items()
        local onSelect = browser.breadcrumb.onSelect
        browser.breadcrumb.onSelect = function() error("Current folder must not navigate") end
        app:mousepressed(items[#items].x + 4, items[#items].y + 4, 1)
        browser.breadcrumb.onSelect = onSelect
        app:mousepressed(items[2].x + 4, items[2].y + 4, 1)
        Assert.equal("Sources/Levels", browser.folder)
        items = browser.breadcrumb:items()
        app:mousepressed(items[1].x + 4, items[1].y + 4, 1)
        Assert.equal("Sources", browser.folder)
        Assert.equal(false, browser:goUp())
        assert(browser:openFolder("Sources/Levels"))
        Assert.equal(DEFAULT_SCRIPT_REFERENCE, browser.entries[2].reference)
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
        local project = assert(createSampleProject(parent, "스크립트 테스트"))
        local app = EditorApp.new(nil, project)
        Assert.equal(project:getAssetId(DEFAULT_LEVEL_REFERENCE), app.documentReference)
        Assert.equal(project:getAssetId(DEFAULT_SCRIPT_REFERENCE), app.level.scriptReference)
        Assert.equal(false, app.document:isDirty())
        local sourcePath = assert(project:resolveSourceFile(DEFAULT_SCRIPT_REFERENCE))
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
        Assert.equal(project:getAssetId(DEFAULT_SCRIPT_REFERENCE), loaded.scriptReference)
        Assert.equal(1, #loaded.lobjects)
        assert(app:saveCurrentDocument())
        Assert.equal(nil, FS.info(app.document.path .. ".tmp"))
        Assert.equal(nil, FS.info(app.document.path .. ".bak"))
    end)
end)

add("script load update and path failures are contained in the editor", function()
    fixture(function(parent)
        local project = assert(createSampleProject(parent, "Failures"))
        local app = EditorApp.new(nil, project)
        local sourcePath = assert(project:resolveSourceFile(DEFAULT_SCRIPT_REFERENCE))
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
        local ok, path = pcall(project.resolveSourceFile, project, DEFAULT_SCRIPT_REFERENCE)
        FS.info = original
        Assert.truthy(ok)
        Assert.equal(nil, path)
    end)
end)

add("level JSON preserves script references and rejects invalid references", function()
    local LevelFile = require("editor.level_file")
    local Level = require("editor.level")
    local level = Level.new()
    assert(level:setScriptReference(DEFAULT_SCRIPT_REFERENCE))
    local loaded = assert(LevelFile.decode(assert(LevelFile.encode(level))))
    Assert.equal(DEFAULT_SCRIPT_REFERENCE, loaded.scriptReference)
    Assert.equal(nil, LevelFile.decode('{"formatVersion":1,"lobjects":[],"scriptReference":"Sources/../bad.lua"}'))
    level.scriptReference = "Sources//bad.lua"
    Assert.equal(nil, LevelFile.encode(level))
    local legacy = assert(LevelFile.decode('{"formatVersion":1,"lobjects":[]}'))
    Assert.equal(nil, legacy.scriptReference)
end)

add("failed Unicode level replacement restores existing file", function()
    fixture(function(parent)
        local project = assert(createSampleProject(parent, "저장 복구"))
        local LevelFile = require("editor.level_file")
        local path = assert(project:resolveAssetFile(DEFAULT_LEVEL_REFERENCE))
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

add("new browser entries select existing scripts and never overwrite files", function()
    fixture(function(parent)
        local project = assert(createSampleProject(parent, "Entries"))
        assert(project:createEntry("Assets", "folder", "한글"))
        local options = {scriptReference = DEFAULT_SCRIPT_REFERENCE}
        local ok, reference = project:createEntry("Assets/한글", "level", "Stage.LEVEL", options)
        Assert.truthy(ok)
        Assert.equal("Assets/한글/Stage.level", reference)
        local level = assert(require("editor.level_file").load(assert(project:resolveAssetFile(reference))))
        Assert.equal(project:getAssetId(DEFAULT_SCRIPT_REFERENCE), level.scriptReference)
        local source = assert(FS.read(assert(project:resolveSourceFile(level.scriptReference))))
        Assert.equal(require("editor.level_script_template"), source)
        Assert.equal(false, project:createEntry("Assets/한글", "level", "Stage", options))
        Assert.equal(source, assert(FS.read(assert(project:resolveSourceFile(level.scriptReference)))))
        assert(project:createEntry("Sources", "lua", "Extra", {scriptKind = "level"}))
        Assert.equal(false, project:createEntry("Assets", "lua", "Bad"))
        Assert.equal(false, project:createEntry("Sources", "level", "Bad"))
        for _, name in ipairs({ "../escape", "CON", "bad/name", "trailing." }) do
            Assert.equal(false, project:createEntry("Assets", "folder", name))
        end
        Assert.equal(false, project:createEntry("Outside", "folder", "Bad"))
    end)
end)

add("new level write failure leaves its selected script untouched", function()
    fixture(function(parent)
        local project = assert(createSampleProject(parent, "Rollback"))
        assert(project:createEntry("Assets", "folder", "Nested"))
        local original = FS.createFile
        FS.createFile = function(path, text)
            if path == FS.join(project.rootPath, "Assets/Nested/Fail.level") then return false, "write failed" end
            return original(path, text)
        end
        local originalScript = assert(FS.read(assert(project:resolveSourceFile(DEFAULT_SCRIPT_REFERENCE))))
        local called, ok, err = pcall(project.createEntry, project, "Assets/Nested", "level", "Fail",
            {scriptReference = DEFAULT_SCRIPT_REFERENCE})
        FS.createFile = original
        Assert.truthy(called)
        Assert.equal(false, ok)
        Assert.equal("write failed", err)
        Assert.equal(nil, FS.info(FS.join(project.rootPath, "Sources/Nested")))
        Assert.truthy(FS.info(FS.join(project.rootPath, "Assets/Nested")))
        Assert.equal(originalScript, assert(FS.read(assert(project:resolveSourceFile(DEFAULT_SCRIPT_REFERENCE)))))
    end)
end)

add("entry deletion removes nested contents but protects roots default level and links", function()
    fixture(function(parent)
        local project = assert(createSampleProject(parent, "Delete"))
        assert(project:createEntry("Sources", "folder", "Temporary"))
        assert(project:createEntry("Sources/Temporary", "lua", "A", {scriptKind = "level"}))
        assert(project:createEntry("Sources/Temporary", "folder", "Nested"))
        assert(project:createEntry("Sources/Temporary/Nested", "lua", "B", {scriptKind = "level"}))
        Assert.equal(false, project:deleteEntry("Assets"))
        Assert.equal(false, project:deleteEntry("Sources"))
        Assert.equal(false, project:deleteEntry("Assets/Levels"))
        project.defaultLevelReference = project.defaultLevelReference:lower()
        Assert.equal(false, project:deleteEntry("Assets/Levels/StartLevel.level"))
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
        local project = assert(createSampleProject(parent, "Menus"))
        local app = EditorApp.new(nil, project)
        local browser, root = app.assetBrowser, app.uiRoot
        local x, y = browser.fileSlot.widget.x + 20, browser.fileSlot.widget.y + 20
        app:mousepressed(x, y, 2)
        Assert.equal("Assets/Levels", browser.selectedReference)
        Assert.equal(4, #root.popup.panels[1].items)
        root:keypressed("escape")
        local gapX = browser.fileSlot.widget.x + require("editor.ui").metrics.contentPaddingX + 108
        app:mousepressed(gapX, y, 2)
        Assert.equal(1, #root.popup.panels[1].items)
        root:keypressed("escape")
        app:mousepressed(browser.x + browser.width - 20, y, 2)
        Assert.equal(1, #root.popup.panels[1].items)
        root:keypressed("right")
        Assert.equal(3, #root.popup.panels[2].items)
        Assert.equal("Level", root.popup.panels[2].items[2].label)
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
        assert(project:createEntry("Assets", "level", "Open", {scriptReference = DEFAULT_SCRIPT_REFERENCE}))
        assert(app:openProjectDocument("Assets/Open.level"))
        browser:showDeleteDialog({reference = "Assets/Open.level", type = "file"})
        root:keypressed("return")
        Assert.truthy(root.popup.error:find("currently open", 1, true))
        Assert.truthy(FS.info(FS.join(project.rootPath, "Assets/Open.level")))
    end)
end)

add("browser replaces context menu on right click and hides unavailable creation types", function()
    fixture(function(parent)
        local app = EditorApp.new(nil, assert(createSampleProject(parent, "RetargetMenu")))
        local browser, root = app.assetBrowser, app.uiRoot
        local x, y = browser.fileSlot.widget.x + 20, browser.fileSlot.widget.y + 20
        app:mousepressed(x, y, 2)
        local first = root.popup
        Assert.equal(4, #first.panels[1].items)
        local emptyX = browser.x + browser.width - 20
        app:mousepressed(emptyX, y, 2)
        Assert.truthy(root.popup ~= first)
        Assert.equal(nil, browser.selectedReference)
        Assert.equal(1, #root.popup.panels[1].items)
        root:keypressed("right")
        local assetsItems = root.popup.panels[2].items
        Assert.equal(3, #assetsItems)
        Assert.equal("Folder", assetsItems[1].label)
        Assert.equal("Level", assetsItems[2].label)
        Assert.equal("Prefab", assetsItems[3].label)
        local sourceIndex
        for i, node in ipairs(browser.tree) do if node.reference == "Sources" then sourceIndex = i end end
        local sourceY = browser.treeSlot.widget.y + (sourceIndex - 1) * 26 + 13
        app:mousepressed(browser.x + 70, sourceY, 2)
        root:keypressed("right")
        local sourcesItems = root.popup.panels[2].items
        Assert.equal(2, #sourcesItems)
        Assert.equal("Folder", sourcesItems[1].label)
        Assert.equal("Lua Class", sourcesItems[2].label)
        root:keypressed("down")
        root:keypressed("return")
        local dialog = root.popup
        Assert.equal("Sources", dialog.options.message)
        -- 입력·삭제 확인 창의 우클릭은 메뉴 교체 동작에 포함하지 않는다.
        app:mousepressed(x, y, 2)
        Assert.equal(dialog, root.popup)
        root:keypressed("escape")
        app:mousepressed(x, y, 2)
        local selected = browser.selectedReference
        app:mousepressed(emptyX, y, 1)
        Assert.equal(nil, root.popup)
        Assert.equal(selected, browser.selectedReference)
    end)
end)

add("typed scripts are discovered without execution and legacy scripts remain levels", function()
    fixture(function(parent)
        local project = assert(createSampleProject(parent, "ScriptTypes"))
        assert(project:createEntry("Sources", "folder", "한글"))
        assert(project:createEntry("Sources/한글", "lua", "Actor", {scriptKind = "lobject"}))
        assert(project:createEntry("Sources/한글", "lua", "Stage", {scriptKind = "level"}))
        assert(FS.createFile(assert(project:resolvePath("Sources/Legacy.lua")), 'error("must not execute")'))
        assert(FS.createFile(assert(project:resolvePath("Sources/Unexecuted.lua")), '-- labo-script: lobject\nerror("must not execute")'))
        Assert.equal("level", project:getScriptKind(DEFAULT_SCRIPT_REFERENCE))
        Assert.equal("level", project:getScriptKind("Sources/Legacy.lua"))
        local levels = assert(project:listScripts("level"))
        local objects = assert(project:listScripts("lobject"))
        Assert.equal(3, #levels)
        Assert.equal(2, #objects)
        Assert.equal(false, project:createEntry("Sources", "lua", "Untyped"))
        assert(FS.createFile(assert(project:resolvePath("Sources/Bad.lua")), '-- labo-script: unknown\nreturn {}'))
        Assert.equal(nil, project:getScriptKind("Sources/Bad.lua"))
        Assert.equal(nil, project:listScripts("level"))
    end)
end)

add("Level and Prefab allow no class but reject wrong kinds and persist IDs", function()
    fixture(function(parent)
        local project = assert(createSampleProject(parent, "TypedAssets"))
        assert(project:createEntry("Sources", "lua", "Enemy", {scriptKind = "lobject"}))
        local objectOptions = {scriptReference = "Sources/Enemy.lua"}
        local levelOptions = {scriptReference = DEFAULT_SCRIPT_REFERENCE}
        assert(project:createEntry("Assets", "level", "Unbound"))
        assert(project:createEntry("Assets", "prefab", "Unbound"))
        Assert.equal(nil, assert(require("editor.level_file").load(assert(project:resolveAssetFile("Assets/Unbound.level")))).scriptReference)
        Assert.equal(nil, assert(require("editor.prefab").decode(assert(FS.read(assert(project:resolveAssetFile("Assets/Unbound.prefab")))))).definitionReference)
        Assert.equal(false, project:createEntry("Assets", "level", "Wrong", objectOptions))
        Assert.equal(false, project:createEntry("Assets", "prefab", "Wrong", levelOptions))
        Assert.equal(false, project:createEntry("Assets", "prefab", "Outside", {scriptReference = "Sources/../Outside.lua"}))
        local before = assert(FS.read(assert(project:resolveSourceFile("Sources/Enemy.lua"))))
        assert(project:createEntry("Assets", "prefab", "Enemy", objectOptions))
        assert(project:createEntry("Assets", "prefab", "OtherEnemy", objectOptions))
        local data = assert(require("editor.json").decode(assert(FS.read(assert(project:resolveAssetFile("Assets/Enemy.prefab"))))))
        Assert.equal(2, data.formatVersion)
        Assert.equal(project:getAssetId("Sources/Enemy.lua"), data.definitionReference)
        Assert.equal(nil, next(data.overrides))
        Assert.equal(false, project:createEntry("Assets", "prefab", "Enemy", objectOptions))
        Assert.equal(before, assert(FS.read(assert(project:resolveSourceFile("Sources/Enemy.lua")))))
        assert(project:createEntry("Assets", "level", "Stage", levelOptions))
        Assert.equal(nil, FS.info(assert(project:resolvePath("Sources/Stage.lua"))))
        local level = assert(require("editor.level_file").load(assert(project:resolveAssetFile("Assets/Stage.level"))))
        Assert.equal(project:getAssetId(DEFAULT_SCRIPT_REFERENCE), level.scriptReference)
        assert(level:setScriptReference("Sources/Enemy.lua"))
        local app = EditorApp.new(assert(require("editor.level_document").new(level)), project)
        Assert.equal(false, app:startPlay())
        Assert.equal(nil, app.runtimeWorld)
    end)
end)

add("creation dialogs choose script type and filter scrollable Level and Prefab sources", function()
    fixture(function(parent)
        local project = assert(createSampleProject(parent, "Pickers"))
        local app = EditorApp.new(nil, project)
        local browser, root = app.assetBrowser, app.uiRoot
        browser:showCreateDialog("Sources", "lua")
        app:textinput("Enemy")
        app:keypressed("down")
        app:keypressed("return")
        Assert.equal(nil, root.popup)
        Assert.equal("lobject", project:getScriptKind("Sources/Enemy.lua"))
        for i = 1, 8 do assert(project:createEntry("Sources", "lua", "Stage" .. i, {scriptKind = "level"})) end
        browser:showCreateDialog("Assets", "level")
        local dialog = root.popup
        Assert.equal(10, #dialog.options.choices)
        Assert.equal(false, dialog.options.choices[1].value)
        for i = 2, #dialog.options.choices do Assert.equal("level", project:getScriptKind(dialog.options.choices[i].value)) end
        root:wheelmoved(dialog.choicesRect.x + 5, dialog.choicesRect.y + 5, -2)
        Assert.truthy(dialog.choiceScroll > 0)
        local selectedIndex = dialog.choiceScroll + 2
        root:mousepressed(dialog.choicesRect.x + 5, dialog.choicesRect.y + 35, 1)
        local reference = dialog.options.choices[selectedIndex].value
        root:mousepressed(dialog.field.x + 5, dialog.field.y + 5, 1)
        app:textinput("SelectedStage")
        app:keypressed("return")
        Assert.equal(nil, root.popup)
        local level = assert(require("editor.level_file").load(assert(project:resolveAssetFile("Assets/SelectedStage.level"))))
        Assert.equal(project:getAssetId(reference), level.scriptReference)
        browser:showCreateDialog("Assets", "prefab")
        Assert.equal(2, #root.popup.options.choices)
        Assert.equal("Sources/Enemy.lua", root.popup.options.choices[2].value)
        app:textinput("EnemyPrefab")
        app:keypressed("down")
        app:keypressed("return")
        Assert.equal(nil, root.popup)
        local data = assert(require("editor.json").decode(assert(FS.read(assert(project:resolveAssetFile("Assets/EnemyPrefab.prefab"))))))
        Assert.equal(project:getAssetId("Sources/Enemy.lua"), data.definitionReference)
        assert(project:deleteEntry("Sources/Enemy.lua"))
        browser:showCreateDialog("Assets", "prefab")
        Assert.equal(1, #root.popup.options.choices)
        app:keypressed("return")
        Assert.equal(nil, root.popup)
        Assert.equal(nil, assert(require("editor.prefab").decode(assert(FS.read(assert(project:resolveAssetFile("Assets/NewPrefab.prefab")))))).definitionReference)
    end)
end)

add("legacy paths migrate to sidecar IDs and cache rebuild never changes identity", function()
    fixture(function(parent)
        assert(FS.mkdir(FS.join(parent, "Assets")))
        assert(FS.mkdir(FS.join(parent, "Sources")))
        assert(FS.createFile(FS.join(parent, "Sources/Stage.lua"), require("editor.level_script_template")))
        assert(FS.createFile(FS.join(parent, "Sources/Enemy.lua"), require("editor.lobject_script_template")))
        assert(FS.createFile(FS.join(parent, "Assets/Enemy.prefab"), '{"formatVersion":1,"definitionReference":"Sources/Enemy.lua","overrides":{}}'))
        assert(FS.createFile(FS.join(parent, "Assets/Stage.level"), '{"formatVersion":1,"scriptReference":"Sources/stage.lua","lobjects":[{"authoringId":1,"definitionReference":"Assets/Enemy.prefab","transform":{"x":0,"y":0}}]}'))
        assert(FS.createFile(FS.join(parent, "project.labo"), '{"version":1,"name":"LegacyIds","defaultLevelReference":"Assets/Stage.level"}'))
        local project = assert(Project.open(parent))
        local Json = require("editor.json")
        local scriptId = project:getAssetId("Sources/Stage.lua")
        local levelId = project:getAssetId("Assets/Stage.level")
        Assert.truthy(require("editor.asset_id").isValid(scriptId))
        Assert.equal(levelId, project.defaultLevelReference)
        local metaBytes = assert(FS.read(FS.join(parent, "Sources/Stage.lua.meta")))
        local meta = assert(Json.decode(metaBytes))
        Assert.equal(scriptId, meta.id)
        Assert.equal("level", meta.scriptKind)
        local level = assert(require("editor.level_file").load(assert(project:resolveAssetFile(levelId))))
        Assert.equal(scriptId, level.scriptReference)
        Assert.equal(project:getAssetId("Assets/Enemy.prefab"), level.lobjects[1].definitionReference)
        local prefab = assert(Json.decode(assert(FS.read(FS.join(parent, "Assets/Enemy.prefab")))))
        Assert.equal(project:getAssetId("Sources/Enemy.lua"), prefab.definitionReference)
        Assert.equal(2, prefab.formatVersion)
        assert(FS.writeAtomic(FS.join(parent, "asset-index.json"), 'broken cache'))
        project = assert(Project.open(parent))
        Assert.equal(scriptId, project:getAssetId("Sources/Stage.lua"))
        Assert.equal(metaBytes, assert(FS.read(FS.join(parent, "Sources/Stage.lua.meta"))))
        local cache = assert(Json.decode(assert(FS.read(FS.join(parent, "asset-index.json")))))
        Assert.equal("Sources/Stage.lua", cache.paths[scriptId])
        assert(FS.removeFile(FS.join(parent, "asset-index.json")))
        project = assert(Project.open(parent))
        Assert.equal(scriptId, project:getAssetId("Sources/Stage.lua"))
        Assert.equal(2, #assert(project:listDirectory("Assets")))
    end)
end)

add("duplicate and malformed sidecar IDs stop import without rewriting originals", function()
    fixture(function(parent)
        local project = assert(createSampleProject(parent, "BadMeta"))
        local originalMeta = assert(FS.read(assert(project:resolvePath(DEFAULT_SCRIPT_REFERENCE)) .. ".meta"))
        local path = assert(project:resolvePath("Sources/Copy.lua"))
        assert(FS.createFile(path, require("editor.level_script_template")))
        assert(FS.createFile(path .. ".meta", originalMeta))
        local reopened, err = Project.open(project.rootPath)
        Assert.equal(nil, reopened)
        Assert.truthy(err:find("Duplicate asset ID", 1, true))
        Assert.equal(originalMeta, assert(FS.read(path .. ".meta")))
        assert(FS.writeAtomic(path .. ".meta", 'not json'))
        Assert.equal(nil, Project.open(project.rootPath))
        Assert.equal('not json', assert(FS.read(path .. ".meta")))
    end)
end)

add("moves preserve IDs and dependent asset bytes across rename folder move and reopen", function()
    fixture(function(parent)
        local project = assert(createSampleProject(parent, "Moves"))
        assert(project:createEntry("Sources", "lua", "Enemy", {scriptKind = "lobject"}))
        assert(project:createEntry("Assets", "prefab", "Enemy", {scriptReference = "Sources/Enemy.lua"}))
        local sourceId = project:getAssetId("Sources/Enemy.lua")
        local prefabPath = assert(project:resolveAssetFile("Assets/Enemy.prefab"))
        local bytes = assert(FS.read(prefabPath))
        assert(project:createEntry("Sources", "folder", "Enemies"))
        assert(project:moveEntry("Sources/Enemy.lua", "Sources/Enemies/Renamed.lua"))
        Assert.equal("Sources/Enemies/Renamed.lua", project:getAssetReference(sourceId))
        Assert.equal(bytes, assert(FS.read(prefabPath)))
        Assert.equal(nil, FS.info(assert(project:resolvePath("Sources/Enemy.lua.meta"))))
        assert(project:moveEntry("Sources/Enemies", "Sources/Units"))
        Assert.equal("Sources/Units/Renamed.lua", project:getAssetReference(sourceId))
        Assert.equal(bytes, assert(FS.read(prefabPath)))
        Assert.equal(false, project:moveEntry("Sources/Units", "Sources/Units/Inside"))
        Assert.equal(false, project:moveEntry("Sources/Units/Renamed.lua", "Assets/Renamed.lua"))
        local app = EditorApp.new(nil, project)
        local levelId, scriptId = project.defaultLevelReference, app.level.scriptReference
        app.assetBrowser:showRenameDialog({reference = "Assets/Levels", type = "directory"})
        app:textinput("Stages")
        app:keypressed("return")
        Assert.equal(nil, app.uiRoot.popup)
        Assert.equal(false, app.document:isDirty())
        Assert.equal(assert(project:resolvePath("Assets/Stages/StartLevel.level")), app.document.path)
        Assert.equal(levelId, app.documentReference)
        app.level:addLObject(10, 20)
        assert(app:saveCurrentDocument())
        assert(app:startPlay())
        assert(app:stopPlay())
        local reopened = assert(Project.open(project.rootPath))
        Assert.equal("Assets/Stages/StartLevel.level", reopened:getAssetReference(levelId))
        local editor = EditorApp.new(nil, reopened)
        Assert.equal(scriptId, editor.level.scriptReference)
        Assert.equal(1, #editor.level.lobjects)
    end)
end)

add("failed metadata rename rolls back and interrupted file moves recover from journal", function()
    fixture(function(parent)
        local project = assert(createSampleProject(parent, "MoveRecovery"))
        local reference = DEFAULT_SCRIPT_REFERENCE
        local target = "Sources/Levels/Renamed.lua"
        local sourcePath, targetPath = assert(project:resolvePath(reference)), assert(project:resolvePath(target))
        local id = project:getAssetId(reference)
        local original = FS.rename
        FS.rename = function(source, destination)
            if source == sourcePath .. ".meta" then return false, "metadata move failed" end
            return original(source, destination)
        end
        local called, moved, err = pcall(project.moveEntry, project, reference, target)
        FS.rename = original
        Assert.truthy(called)
        Assert.equal(false, moved)
        Assert.equal("metadata move failed", err)
        Assert.truthy(FS.info(sourcePath))
        Assert.truthy(FS.info(sourcePath .. ".meta"))
        Assert.equal(nil, FS.info(targetPath))
        Assert.equal(nil, FS.info(FS.join(project.rootPath, "asset-move.json")))
        assert(FS.createFile(FS.join(project.rootPath, "asset-move.json"), assert(require("editor.json").encode({version = 1, id = id, source = reference, destination = target}))))
        assert(FS.rename(sourcePath, targetPath))
        local reopened = assert(Project.open(project.rootPath))
        Assert.equal(target, reopened:getAssetReference(id))
        Assert.truthy(FS.info(targetPath .. ".meta"))
        Assert.equal(nil, FS.info(sourcePath .. ".meta"))
        Assert.equal(nil, FS.info(FS.join(project.rootPath, "asset-move.json")))
        local app = EditorApp.new(nil, reopened)
        assert(app:startPlay())
    end)
end)

add("live index refresh recovers pending moves before assigning new identities", function()
    fixture(function(parent)
        local project = assert(createSampleProject(parent, "LiveRecovery"))
        local source = DEFAULT_SCRIPT_REFERENCE
        local target = "Sources/Levels/Moved.lua"
        local id = project:getAssetId(source)
        assert(FS.createFile(FS.join(project.rootPath, "asset-move.json"), assert(require("editor.json").encode({version = 1, id = id, source = source, destination = target}))))
        assert(FS.rename(assert(project:resolvePath(source)), assert(project:resolvePath(target))))
        assert(project:rebuildAssetIndex())
        Assert.equal(id, project:getAssetId(target))
        Assert.equal("level", project:getScriptKind(id))
    end)
end)

add("metadata import failure preserves assets and cache write failure keeps IDs usable", function()
    fixture(function(parent)
        local project = assert(createSampleProject(parent, "ImportErrors"))
        local image = assert(project:resolvePath("Assets/Image.png"))
        assert(FS.createFile(image, "original bytes"))
        local originalCreate = FS.createFile
        FS.createFile = function(path, text)
            if path == image .. ".meta" then return false, "metadata write failed" end
            return originalCreate(path, text)
        end
        local called, indexed, err = pcall(project.rebuildAssetIndex, project)
        FS.createFile = originalCreate
        Assert.truthy(called)
        Assert.equal(false, indexed)
        Assert.equal("metadata write failed", err)
        Assert.equal("original bytes", assert(FS.read(image)))
        assert(project:rebuildAssetIndex())
        local id = project:getAssetId("Assets/Image.png")
        Assert.equal(false, project:deleteEntry("Assets/Image.png.meta"))
        local originalAtomic = FS.writeAtomic
        FS.writeAtomic = function(path, text)
            if path == FS.join(project.rootPath, "asset-index.json") then return false, "cache write failed" end
            return originalAtomic(path, text)
        end
        local callOk, rebuilt = pcall(project.rebuildAssetIndex, project)
        FS.writeAtomic = originalAtomic
        Assert.truthy(callOk)
        Assert.truthy(rebuilt)
        Assert.equal("cache write failed", project.assetIndexError)
        Assert.equal(id, project:getAssetId("Assets/Image.png"))
        Assert.equal(image, assert(project:resolveAssetFile(id)))
        assert(project:deleteEntry("Assets/Image.png"))
        Assert.equal(nil, FS.info(image .. ".meta"))
        Assert.equal(nil, project:getAssetReference(id))
    end)
end)

add("failed file deletion keeps its original metadata and identity", function()
    fixture(function(parent)
        local project = assert(createSampleProject(parent, "DeleteLocked"))
        assert(project:createEntry("Sources", "lua", "Locked", {scriptKind = "lobject"}))
        local path = assert(project:resolvePath("Sources/Locked.lua"))
        local id = project:getAssetId("Sources/Locked.lua")
        local meta = assert(FS.read(path .. ".meta"))
        local original = FS.removeFile
        FS.removeFile = function(target)
            if target == path then return false, "file is locked" end
            return original(target)
        end
        local called, removed, err = pcall(project.deleteEntry, project, "Sources/Locked.lua")
        FS.removeFile = original
        Assert.truthy(called)
        Assert.equal(false, removed)
        Assert.equal("file is locked", err)
        Assert.equal(meta, assert(FS.read(path .. ".meta")))
        assert(project:rebuildAssetIndex())
        Assert.equal(id, project:getAssetId("Sources/Locked.lua"))
    end)
end)

add("Lua Classes inherit properties callbacks and super across source moves", function()
    fixture(function(parent)
        local project = assert(Project.create(parent, "Inheritance"))
        assert(project:createEntry("Sources", "lua", "Base", {scriptKind = "level"}))
        assert(project:createEntry("Sources", "lua", "Child", {scriptKind = "level"}))
        local baseId, childId = project:getAssetId("Sources/Base.lua"), project:getAssetId("Sources/Child.lua")
        assert(FS.writeAtomic(assert(project:resolveSourceFile(baseId)), [[return {
properties = {speed = {type = "number", default = 100}, title = {type = "string", default = "Base"}, enabled = {type = "boolean", default = true}},
load = function(world) world.loaded = true end,
update = function(world, dt) world.moved = (world.moved or 0) + world.properties.speed * dt end
}]]))
        assert(FS.writeAtomic(assert(project:resolveSourceFile(childId)), 'local Child = {extends = "' .. baseId .. [[", properties = {speed = {type = "number", default = 200}}}
function Child.load(world) Child.super.load(world); world.childLoaded = true end
return Child]]))
        local app = EditorApp.new(nil, project)
        assert(app.level:setScriptReference(childId))
        app.level.propertyOverrides.speed = 300
        assert(app:saveNewLevel("Assets/Stage.level"))
        assert(project:createEntry("Sources", "folder", "Classes"))
        assert(project:moveEntry("Sources/Base.lua", "Sources/Classes/Renamed.lua"))
        local reopened = assert(Project.open(project.rootPath))
        local editor = EditorApp.new(nil, reopened)
        assert(editor:openProjectDocument("Assets/Stage.level"))
        assert(editor:startPlay())
        Assert.truthy(editor.runtimeWorld.loaded and editor.runtimeWorld.childLoaded)
        Assert.equal("Base", editor.runtimeWorld.properties.title)
        assert(editor:update(0.5))
        Assert.equal(150, editor.runtimeWorld.moved)
        editor.runtimeWorld.properties.speed = 1
        Assert.equal(300, editor.level.propertyOverrides.speed)
        assert(editor:stopPlay())
        assert(editor:startPlay())
        Assert.equal(300, editor.runtimeWorld.properties.speed)
    end)
end)

add("invalid inheritance declarations and overrides fail without entering Play", function()
    fixture(function(parent)
        local project = assert(Project.create(parent, "BadClasses"))
        assert(project:createEntry("Sources", "lua", "A", {scriptKind = "level"}))
        assert(project:createEntry("Sources", "lua", "B", {scriptKind = "level"}))
        assert(project:createEntry("Sources", "lua", "Object", {scriptKind = "lobject"}))
        local a, b = project:getAssetId("Sources/A.lua"), project:getAssetId("Sources/B.lua")
        local path = assert(project:resolveSourceFile(a))
        local app = EditorApp.new(nil, project)
        assert(app.level:setScriptReference(a))
        assert(FS.writeAtomic(path, 'return {extends="' .. b .. '"}'))
        assert(FS.writeAtomic(assert(project:resolveSourceFile(b)), 'return {extends="' .. a .. '"}'))
        local ok, err = app:startPlay()
        Assert.equal(false, ok)
        Assert.truthy(err:find("cycle", 1, true))
        for _, text in ipairs({
            'return {extends="' .. project:getAssetId("Sources/Object.lua") .. '"}',
            'return {extends="Sources/B.lua"}',
            'return {properties={x={type="table",default={}}}}',
            'return {properties={x={type="number",default="bad"}}}',
            'return {load=42}', 'error("broken class")',
        }) do
            assert(FS.writeAtomic(path, text))
            Assert.equal(false, app:startPlay())
            Assert.equal(nil, app.runtimeWorld)
        end
        assert(FS.writeAtomic(path, 'return {properties={x={type="number",default=1}}}'))
        app.level.propertyOverrides.x = "wrong"
        Assert.equal(false, app:startPlay())
        app.level.propertyOverrides = {missing = true}
        Assert.equal(false, app:startPlay())
    end)
end)

add("Inspector identifies assets and keeps the opened level editable", function()
    fixture(function(parent)
        local project = assert(Project.create(parent, "InspectorNames"))
        local app = EditorApp.new(nil, project)
        Assert.equal("Untitled Level", app.levelInspectorTarget:getDisplayName())
        assert(app:saveNewLevel("Assets/Stage.level"))
        Assert.equal("Stage", app.levelInspectorTarget:getDisplayName())
        app.activePanel = "assets"
        app.assetBrowser.selectedReference = "Assets/Stage.level"
        app:updateInspectorTarget()
        Assert.equal(nil, app.inspector.assetSummary)
        Assert.equal(app.levelInspectorTarget, app.inspector.classInspector.target)
        assert(project:moveEntry("Assets/Stage.level", "Assets/Renamed.level"))
        Assert.equal("Renamed", app.levelInspectorTarget:getDisplayName())
        assert(project:createEntry("Sources", "lua", "Actor", {scriptKind = "lobject"}))
        app.assetBrowser.selectedReference = "Sources/Actor.lua"
        app:updateInspectorTarget()
        Assert.equal("Actor", app.inspector.assetSummary.name)
        Assert.equal("LObject Class", app.inspector.assetSummary.kind)
        Assert.equal(nil, app.inspector.classInspector.target)
        app.level:addLObject(0, 0)
        app.sceneView.selectedLObject = app.level.lobjects[1]
        app.activePanel = "scene"
        Assert.equal(app.sceneView.selectedLObject, app:updateInspectorTarget())
        Assert.equal(nil, app.inspector.assetSummary)
    end)
end)

add("Level inspector edits basic properties resets defaults and clears parent", function()
    fixture(function(parent)
        local project = assert(Project.create(parent, "InspectorProperties"))
        assert(project:createEntry("Sources", "lua", "Stage", {scriptKind = "level"}))
        local id = project:getAssetId("Sources/Stage.lua")
        assert(FS.writeAtomic(assert(project:resolveSourceFile(id)), [[return {properties = {
enabled = {type="boolean",default=true}, name = {type="string",default="Stage"}, speed = {type="number",default=10}}}]]))
        local app = EditorApp.new(nil, project)
        local inspector = app.inspector.classInspector
        local x, y = inspector.dropdown.x + 5, inspector.dropdown.y + 5
        app:mousepressed(x, y, 1)
        app:keypressed("down")
        app:keypressed("return")
        Assert.equal(id, app.level.scriptReference)
        app:draw()
        local fieldX = love.graphics.getWidth() - app.inspector.width + 20
        app:mousepressed(fieldX, 195, 1)
        Assert.equal(false, app.level.propertyOverrides.enabled)
        app:mousepressed(fieldX, 251, 1)
        app:textinput("한글 이름")
        app:keypressed("return")
        Assert.equal("한글 이름", app.level.propertyOverrides.name)
        app:mousepressed(fieldX, 307, 1)
        app:textinput("25.5")
        app:keypressed("return")
        Assert.equal(25.5, app.level.propertyOverrides.speed)
        assert(app:saveNewLevel("Assets/Stage.level"))
        assert(app:startPlay())
        Assert.equal(false, app.runtimeWorld.properties.enabled)
        Assert.equal("한글 이름", app.runtimeWorld.properties.name)
        Assert.equal(25.5, app.runtimeWorld.properties.speed)
        assert(app:stopPlay())
        app:mousepressed(fieldX, 307, 1)
        app:textinput("bad number")
        app:keypressed("return")
        Assert.equal(25.5, app.level.propertyOverrides.speed)
        app:mousepressed(love.graphics.getWidth() - 25, 307, 1)
        Assert.equal(nil, app.level.propertyOverrides.speed)
        app:mousepressed(x, y, 1)
        app:keypressed("up")
        app:keypressed("return")
        Assert.equal(nil, app.level.scriptReference)
        Assert.equal(nil, next(app.level.propertyOverrides))
        app.level:addLObject(0, 0)
        app.sceneView.selectedLObject = app.level.lobjects[1]
        app.activePanel = "scene"
        app:draw()
        assert(app:saveInspectedDocument())
        Assert.equal(app.level.lobjects[1], app.inspector.classInspector.target.data)
    end)
end)

add("Prefab inspector saves inherited values and Play creates independent objects", function()
    fixture(function(parent)
        local project = assert(Project.create(parent, "PrefabProperties"))
        assert(project:createEntry("Sources", "lua", "Actor", {scriptKind = "lobject"}))
        local id = project:getAssetId("Sources/Actor.lua")
        assert(FS.writeAtomic(assert(project:resolveSourceFile(id)), [[return {
properties={speed={type="number",default=10}},
load=function(self, world) self.loaded=true end,
update=function(self,dt) self.transform.x=self.transform.x+self.properties.speed*dt end}]]))
        assert(project:createEntry("Assets", "prefab", "Actor"))
        assert(project:createEntry("Assets", "prefab", "Other"))
        local app = EditorApp.new(nil, project)
        local browser = app.assetBrowser
        app:mousepressed(browser.fileSlot.widget.x + 20, browser.fileSlot.widget.y + 20, 1)
        app:draw()
        local inspector = app.inspector.classInspector
        Assert.equal("Prefab", inspector.target.label)
        assert(inspector:selectParent(id))
        assert(inspector:setProperty("speed", 30))
        Assert.equal(false, app:inspectAsset("Assets/Other.prefab"))
        assert(app:saveInspectedDocument())
        local prefabId = project:getAssetId("Assets/Actor.prefab")
        assert(project:moveEntry("Assets/Actor.prefab", "Assets/Renamed.prefab"))
        assert(inspector:setProperty("speed", 40))
        assert(app:saveInspectedDocument())
        local data = assert(require("editor.prefab").decode(assert(FS.read(assert(project:resolveAssetFile(prefabId))))))
        Assert.equal(id, data.definitionReference)
        Assert.equal(40, data.overrides.properties.speed)
        app.level:addLObject(0, 0, prefabId)
        app.level:addLObject(0, 0, prefabId)
        assert(app:startPlay())
        Assert.truthy(app.runtimeWorld.lobjects[1].loaded)
        assert(app:update(0.5))
        Assert.equal(20, app.runtimeWorld.lobjects[1].transform.x)
        app.runtimeWorld.lobjects[1].properties.speed = 5
        Assert.equal(40, app.runtimeWorld.lobjects[2].properties.speed)
        Assert.equal(40, app.prefabDocument.data.overrides.properties.speed)
        assert(app:stopPlay())
        assert(inspector:selectParent(false))
        assert(app:saveInspectedDocument())
        assert(app:startPlay())
        assert(app:update(1))
        Assert.equal(0, app.runtimeWorld.lobjects[1].transform.x)
    end)
end)

add("Move selects destination folders while Rename changes only the name", function()
    fixture(function(parent)
        local project = assert(Project.create(parent, "SeparateMoveRename"))
        assert(project:createEntry("Sources", "lua", "Actor", {scriptKind = "lobject"}))
        assert(project:createEntry("Sources", "folder", "Classes"))
        assert(project:createEntry("Sources/Classes", "folder", "Nested"))
        assert(project:createEntry("Assets", "prefab", "Actor", {scriptReference="Sources/Actor.lua"}))
        local id = project:getAssetId("Sources/Actor.lua")
        local app = EditorApp.new(nil, project)
        local browser, root = app.assetBrowser, app.uiRoot
        browser:showMoveDialog({reference="Sources/Actor.lua",type="file"})
        local dialog, tree = root.popup, root.popup.options.content
        Assert.equal("Sources", tree.root)
        root:mousepressed(tree.x + 50, tree.y + 28 + 10, 1)
        Assert.equal("Sources/Classes", dialog.text)
        app:keypressed("return")
        Assert.equal(nil, root.popup)
        Assert.equal(id, project:getAssetId("Sources/Classes/Actor.lua"))
        browser:showRenameDialog({reference="Sources/Classes/Actor.lua",type="file"})
        app:textinput("Renamed")
        app:keypressed("return")
        Assert.equal(id, project:getAssetId("Sources/Classes/Renamed.lua"))
        browser:showRenameDialog({reference="Sources/Classes/Renamed.lua",type="file"})
        app:textinput("../escape")
        app:keypressed("return")
        Assert.truthy(root.popup.error)
        app:keypressed("escape")
        browser:showMoveDialog({reference="Sources/Classes",type="directory"})
        for _, node in ipairs(root.popup.options.content.nodes) do
            Assert.equal(nil, node.reference:find("Sources/Classes", 1, true))
        end
        app:keypressed("escape")
        browser:showMoveDialog({reference="Sources/Classes/Renamed.lua",type="file"})
        app:textinput("Sources")
        app:keypressed("return")
        Assert.equal(id, project:getAssetId("Sources/Renamed.lua"))
        local prefab = assert(require("editor.prefab").decode(assert(FS.read(assert(project:resolveAssetFile("Assets/Actor.prefab"))))))
        Assert.equal(id, prefab.definitionReference)
    end)
end)

local function treePoint(browser, reference)
    for i, node in ipairs(browser.tree) do
        if node.reference == reference then
            return browser.treeSlot.widget.x + 60 + node.depth * 14,
                browser.treeSlot.widget.y + (i - 1 - browser.treeScroll) * 26 + 13
        end
    end
    error("Tree entry not found: " .. reference)
end

local function filePoint(browser, reference)
    for i, entry in ipairs(browser.entries) do
        if entry.reference == reference then
            local view = browser.fileSlot.widget
            if browser.viewMode == "list" then return view.x + 20, view.y + (i - 1 - browser.fileScroll) * 26 + 13 end
            return view.x + 28 + (i - 1) % browser:columns() * 112,
                view.y + 28 + (math.floor((i - 1) / browser:columns()) - browser.fileScroll) * 138
        end
    end
    error("File entry not found: " .. reference)
end

local function dragEntry(app, sx, sy, tx, ty)
    app:mousepressed(sx, sy, 1)
    app:mousemoved(tx, ty, tx - sx, ty - sy)
    Assert.truthy(app.uiRoot.captured)
    Assert.truthy(app.assetBrowser.drag.active)
    app:mousereleased(tx, ty, 1)
    Assert.equal(nil, app.uiRoot.captured)
    Assert.equal(nil, app.assetBrowser.drag)
end

add("drag moves between file and tree views in every direction and keeps IDs", function()
    fixture(function(parent)
        local project = assert(Project.create(parent, "DragViews"))
        for _, name in ipairs({"A", "B"}) do assert(project:createEntry("Assets", "folder", name)) end
        assert(project:createEntry("Assets/A", "folder", "C"))
        assert(project:createEntry("Assets", "level", "Item"))
        local id = project:getAssetId("Assets/Item.level")
        local app = EditorApp.new(nil, project)
        local browser = app.assetBrowser
        browser:setViewMode("list")
        local sx, sy = filePoint(browser, "Assets/Item.level")
        local tx, ty = treePoint(browser, "Assets/A")
        dragEntry(app, sx, sy, tx, ty)
        Assert.equal(id, project:getAssetId("Assets/A/Item.level"))
        assert(browser:openFolder("Assets/A"))
        browser:setViewMode("thumbnails")
        sx, sy = filePoint(browser, "Assets/A/Item.level")
        tx, ty = filePoint(browser, "Assets/A/C")
        dragEntry(app, sx, sy, tx, ty)
        Assert.equal(id, project:getAssetId("Assets/A/C/Item.level"))
        assert(browser:openFolder("Assets/A/C"))
        assert(browser:openFolder("Assets/B"))
        sx, sy = treePoint(browser, "Assets/A/C")
        tx, ty = browser.fileSlot.widget.x + 50, browser.fileSlot.widget.y + 60
        dragEntry(app, sx, sy, tx, ty)
        Assert.equal(id, project:getAssetId("Assets/B/C/Item.level"))
        assert(browser:openFolder("Assets/B/C"))
        sx, sy = treePoint(browser, "Assets/B/C")
        tx, ty = treePoint(browser, "Assets/A")
        dragEntry(app, sx, sy, tx, ty)
        Assert.equal(id, project:getAssetId("Assets/A/C/Item.level"))
        Assert.equal("Assets/A/C", browser.folder)
        local reopened = assert(Project.open(project.rootPath))
        Assert.equal(id, reopened:getAssetId("Assets/A/C/Item.level"))
    end)
end)

add("drag cancels safely and rejects roots self drops wrong roots and conflicts", function()
    fixture(function(parent)
        local project = assert(Project.create(parent, "DragGuards"))
        assert(project:createEntry("Assets", "folder", "A"))
        assert(project:createEntry("Assets/A", "folder", "Child"))
        assert(project:createEntry("Assets", "level", "Item"))
        assert(project:createEntry("Assets/A", "level", "Item"))
        local id = project:getAssetId("Assets/Item.level")
        local app = EditorApp.new(nil, project)
        local browser = app.assetBrowser
        browser:setViewMode("list")
        local sx, sy = treePoint(browser, "Assets")
        app:mousepressed(sx, sy, 1)
        Assert.equal(nil, browser.drag)
        sx, sy = filePoint(browser, "Assets/Item.level")
        for _, destination in ipairs({"Assets", "Assets/A", "Sources"}) do
            local tx, ty = treePoint(browser, destination)
            dragEntry(app, sx, sy, tx, ty)
            Assert.truthy(browser.error)
            Assert.equal(id, project:getAssetId("Assets/Item.level"))
        end
        app:mousepressed(sx, sy, 1)
        app:mousemoved(sx + 10, sy, 10, 0)
        app:keypressed("escape")
        Assert.equal(nil, browser.drag)
        Assert.equal(nil, app.uiRoot.captured)
        app:mousereleased(-10, -10, 1)
        Assert.equal(id, project:getAssetId("Assets/Item.level"))
        dragEntry(app, sx, sy, -20, -20)
        Assert.equal(id, project:getAssetId("Assets/Item.level"))
        assert(browser:openFolder("Assets/A/Child"))
        sx, sy = treePoint(browser, "Assets/A")
        local tx, ty = treePoint(browser, "Assets/A/Child")
        dragEntry(app, sx, sy, tx, ty)
        Assert.truthy(FS.info(assert(project:resolvePath("Assets/A/Child"))))
        Assert.equal("Assets/A/Child", browser.folder)
        app:mousepressed(sx, sy, 1)
        app:mousereleased(sx, sy, 1)
        Assert.equal("Assets/A", browser.folder)
    end)
end)

add("dragging a source preserves open document references and move failures", function()
    fixture(function(parent)
        local project = assert(Project.create(parent, "DragSource"))
        assert(project:createEntry("Sources", "folder", "Classes"))
        assert(project:createEntry("Sources", "lua", "Stage", {scriptKind="level"}))
        assert(project:createEntry("Assets", "level", "Stage", {scriptReference="Sources/Stage.lua"}))
        local id = project:getAssetId("Sources/Stage.lua")
        local app = EditorApp.new(nil, project)
        assert(app:openProjectDocument("Assets/Stage.level"))
        app.level:addLObject(1, 2)
        local browser = app.assetBrowser
        assert(browser:openFolder("Sources"))
        browser:setViewMode("list")
        local sx, sy = filePoint(browser, "Sources/Stage.lua")
        local tx, ty = treePoint(browser, "Sources/Classes")
        local original = FS.rename
        FS.rename = function() return false, "locked source" end
        local called, err = pcall(dragEntry, app, sx, sy, tx, ty)
        FS.rename = original
        Assert.truthy(called, err)
        Assert.equal("locked source", browser.error)
        Assert.equal(id, project:getAssetId("Sources/Stage.lua"))
        dragEntry(app, sx, sy, tx, ty)
        Assert.equal(id, project:getAssetId("Sources/Classes/Stage.lua"))
        Assert.equal(id, app.level.scriptReference)
        Assert.truthy(app.document:isDirty())
        assert(app:saveCurrentDocument())
        assert(app:startPlay())
        Assert.equal(1, #app.runtimeWorld.lobjects)
    end)
end)

add("Lua thumbnails classify metadata without running code and use distinct theme colors", function()
    fixture(function(parent)
        local project = assert(Project.create(parent, "IconTypes"))
        for _, item in ipairs({{"Level", "level"}, {"Object", "lobject"}, {"Component", "component"}}) do
            assert(FS.createFile(assert(project:resolvePath("Sources/" .. item[1] .. ".lua")),
                "-- labo-script: " .. item[2] .. '\nerror("must not execute")'))
        end
        local browser = AssetBrowser.new(project)
        local seen = {}
        for _, item in ipairs({
            {"Stage.level", "Assets/Stage.level", "Lv", "assetLevel"},
            {"Object.prefab", "Assets/Object.prefab", "Pf", "assetPrefab"},
            {"Level.lua", "Sources/Level.lua", "Lv", "classLevel", "Lua"},
            {"Object.lua", "Sources/Object.lua", "LO", "classLObject", "Lua"},
            {"Component.lua", "Sources/Component.lua", "Cp", "classComponent", "Lua"},
        }) do
            local label, role, badge = browser:iconStyle({name=item[1], reference=item[2], type="file"})
            Assert.equal(item[3], label)
            Assert.equal(item[4], role)
            Assert.equal(item[5], badge)
            local color = require("editor.theme").color(role)
            local key = table.concat(color, ",")
            Assert.equal(nil, seen[key])
            seen[key] = true
        end
        Assert.equal("component", project:getScriptKind("Sources/Component.lua"))
    end)
end)

add("drag hover expands folders and scrolling refreshes the live drop target", function()
    fixture(function(parent)
        local project = assert(Project.create(parent, "DragHover"))
        assert(project:createEntry("Assets", "level", "Item"))
        for i = 1, 24 do assert(project:createEntry("Assets", "folder", string.format("Folder%02d", i))) end
        assert(project:createEntry("Assets/Folder01", "folder", "Nested"))
        local app = EditorApp.new(nil, project)
        local browser = app.assetBrowser
        browser:setViewMode("list")
        browser.fileScroll = 24
        local sx, sy = filePoint(browser, "Assets/Item.level")
        local tx, ty = treePoint(browser, "Assets/Folder01")
        app:mousepressed(sx, sy, 1)
        app:mousemoved(tx, ty, tx - sx, ty - sy)
        app:update(0.65)
        Assert.truthy(browser.expanded["Assets/Folder01"])
        Assert.truthy(treePoint(browser, "Assets/Folder01/Nested"))
        local view = browser.treeSlot.widget
        app:mousemoved(view.x + 60, view.y + view.height - 5, 0, 0)
        local before = browser.treeScroll
        app:update(0.2)
        Assert.truthy(browser.treeScroll > before)
        local destination = browser.drag.destination
        Assert.equal(browser:dropTargetAt(browser.drag.x, browser.drag.y), destination)
        app:keypressed("escape")
        Assert.equal(nil, app.uiRoot.captured)
        Assert.truthy(project:getAssetId("Assets/Item.level"))
    end)
end)

add("global status bar shows live control hints and isolates modal and footer input", function()
    fixture(function(parent)
        local project = assert(Project.create(parent, "StatusHints"))
        assert(project:createEntry("Assets", "folder", "Folder"))
        local app = EditorApp.new(nil, project)
        local browser = app.assetBrowser
        local function hover(x, y)
            local original = love.mouse.getPosition
            love.mouse.getPosition = function() return x, y end
            local ok, err = pcall(app.draw, app)
            love.mouse.getPosition = original
            if not ok then error(err, 0) end
            return app.statusHint
        end
        local refresh = browser:buttons().refresh
        Assert.truthy(hover(refresh.x + 10, refresh.y + 10):find("Rescan", 1, true))
        local dropdown = browser.viewDropdown
        Assert.truthy(hover(dropdown.x + 10, dropdown.y + 10):find("Thumbnails or List", 1, true))
        local x, y = filePoint(browser, "Assets/Folder")
        Assert.truthy(hover(x, y):find("Assets/Folder", 1, true))
        Assert.truthy(hover(x, y):find("Drag: move", 1, true))
        local parentClass = app.inspector.classInspector.dropdown
        Assert.truthy(hover(parentClass.x + 5, parentClass.y + 5):find("Parent Class", 1, true))
        browser:showCreateDialog("Assets", "folder")
        Assert.equal("Choose an option or edit this dialog. Esc: close.", hover(refresh.x + 10, refresh.y + 10))
        local cancel = app.uiRoot.popup.cancel
        Assert.truthy(hover(cancel.x + 5, cancel.y + 5):find("without applying", 1, true))
        app:keypressed("escape")
        Assert.truthy(hover(refresh.x + 10, refresh.y + 10):find("Rescan", 1, true))
        local width, height = love.graphics.getDimensions()
        Assert.equal(height - app.statusHeight, browser.y + browser.height)
        Assert.equal(height - app.statusHeight, app.inspector.height)
        Assert.equal(nil, app.uiLayout:edgesAt(width - app.inspector.width, height - 5))
        app:mousepressed(width - app.inspector.width, height - 5, 1)
        Assert.equal(nil, app.uiRoot.captured)
        Assert.equal(0, #app.level.lobjects)
        browser.error = "move failed"
        Assert.truthy(hover(x, y):find("move failed", 1, true))
    end)
end)

local function componentProject(parent)
    local project = assert(Project.create(parent, "Components"))
    assert(project:createEntry("Sources", "lua", "Actor", {scriptKind = "lobject"}))
    local id = project:getAssetId("Sources/Actor.lua")
    assert(FS.writeAtomic(assert(project:resolveSourceFile(id)), [[
local Engine = require("engine")
local Counter = Engine.LObjectComponent:extend({properties = {count = {type = "number", default = 0}}})
function Counter:Load(world) self.properties.count = self.properties.count + 1 end
function Counter:Update(dt) self.properties.count = self.properties.count + dt end
local Actor = {properties = {
    speed = {type = "number", default = 10}, title = {type = "string", default = "Actor"},
    enabled = {type = "boolean", default = true}, target = {type = "object", default = false}
}}
function Actor.build(self)
    self:addComponent("sprite", Engine.SpriteComponent, {x = 3})
    self:addComponent("counter", Counter)
end
function Actor.load(self, world)
    if self.properties.target then assert(self.properties.target.components.sprite.owner == self.properties.target) end
end
return Actor
]]))
    assert(project:createEntry("Assets", "prefab", "Actor", {scriptReference = id}))
    return project, project:getAssetId("Assets/Actor.prefab")
end

add("Prefab drag places at zoomed viewport coordinates without moving the source", function()
    fixture(function(parent)
        local project, prefabId = componentProject(parent)
        local app = EditorApp.new(nil, project)
        app:draw()
        app.sceneView.zoom, app.sceneView.cameraX, app.sceneView.cameraY = 2, 17, -9
        local browser = app.assetBrowser
        browser:setViewMode("list")
        browser:openFolder("Assets")
        local source = browser.fileSlot.widget
        local x, y = source.x + 20, source.y + 4
        app:mousepressed(x, y, 1)
        local dx, dy = app.sceneView:worldToScreen(24, -12)
        app:mousemoved(dx, dy, dx - x, dy - y)
        Assert.equal("scene", browser.drag.destination)
        app:mousereleased(dx, dy, 1)
        Assert.equal(1, #app.level.lobjects)
        local object = app.level.lobjects[1]
        Assert.equal(24, object.transform.x)
        Assert.equal(-12, object.transform.y)
        Assert.equal(prefabId, object.definitionReference)
        Assert.equal(object, app.sceneView.selectedLObject)
        Assert.truthy(project:resolveAssetFile(prefabId))
        Assert.equal(nil, browser.drag)
        Assert.equal(nil, app.uiRoot.captured)
        assert(app.sceneView:setSnap("translate", true, 10))
        assert(app:placePrefab(prefabId, dx, dy))
        Assert.equal(24, app.level.lobjects[2].transform.x)
        Assert.equal(-12, app.level.lobjects[2].transform.y)
        assert(app:startPlay())
        Assert.equal(false, app:placePrefab(prefabId, dx, dy))
        Assert.equal(2, #app.level.lobjects)
    end)
end)

add("Instance Inspector persists basic component and cyclic object reference overrides", function()
    fixture(function(parent)
        local project, prefabId = componentProject(parent)
        local app = EditorApp.new(nil, project)
        local a, b = app.level:addLObject(0, 0, prefabId), app.level:addLObject(20, 0, prefabId)
        app.sceneView.selectedLObject, app.activePanel = a, "scene"
        app:updateInspectorTarget()
        local inspector = app.inspector.classInspector
        assert(inspector:setProperty("speed", 42))
        assert(inspector:setProperty("title", "한글"))
        assert(inspector:setProperty("enabled", false))
        assert(inspector:setProperty("sprite.x", 13))
        assert(inspector:setProperty("target", b.authoringId))
        b.propertyOverrides = {target = a.authoringId}
        Assert.equal(2, #inspector:choices("target", b.authoringId).options - 1)
        local copy = app.level:duplicateLObject(a)
        Assert.equal(13, copy.componentOverrides.sprite.x)
        copy.componentOverrides.sprite.x = 99
        Assert.equal(13, a.componentOverrides.sprite.x)
        local file = FS.join(project.rootPath, "Assets/Placed.level")
        assert(app:saveCurrentDocument(file))
        local loaded = assert(require("editor.level_document").load(file))
        Assert.equal(42, loaded.level.lobjects[1].propertyOverrides.speed)
        Assert.equal(false, loaded.level.lobjects[1].propertyOverrides.enabled)
        Assert.equal(b.authoringId, loaded.level.lobjects[1].propertyOverrides.target)
        app:setDocument(loaded)
        assert(app:startPlay())
        local ra, rb = app.runtimeWorld.lobjects[1], app.runtimeWorld.lobjects[2]
        Assert.equal(rb, ra.properties.target)
        Assert.equal(ra, rb.properties.target)
        Assert.equal(13, ra.components.sprite.properties.x)
        Assert.equal(1, ra.components.counter.properties.count)
        assert(app.runtimeWorld:update(0.5))
        Assert.equal(1.5, ra.components.counter.properties.count)
        ra.properties.speed = 999
        assert(app:stopPlay())
        Assert.equal(42, app.level.lobjects[1].propertyOverrides.speed)
        app.level:removeLObject(app.level.lobjects[2])
        local ok, err = app:startPlay()
        Assert.equal(false, ok)
        Assert.truthy(err:find("Missing LObject reference", 1, true))
        Assert.equal(nil, app.runtimeWorld)
    end)
end)

add("Sprite image choices use movable asset IDs and render in edit and Play", function()
    fixture(function(parent)
        local project, prefabId = componentProject(parent)
        local imageData = love.image.newImageData(32, 20)
        imageData:mapPixel(function() return 1, 0, 0, 1 end)
        local bytes = imageData:encode("png"):getString()
        imageData:release()
        assert(FS.writeAtomic(assert(project:resolvePath("Assets/Sprite.png")), bytes))
        assert(project:rebuildAssetIndex())
        local imageId = project:getAssetId("Assets/Sprite.png")
        local app = EditorApp.new(nil, project)
        local a = app.level:addLObject(0, 0, prefabId)
        app.sceneView.selectedLObject, app.activePanel = a, "scene"
        app:updateInspectorTarget()
        local inspector = app.inspector.classInspector
        Assert.equal(imageId, inspector:choices("sprite.image", false).options[2].value)
        assert(inspector:setProperty("sprite.image", imageId))
        assert(inspector:setProperty("sprite.x", 30))
        assert(project:moveEntry("Assets/Sprite.png", "Assets/Renamed.png"))
        local preview = assert(app.spriteAssets:preview(a))
        local sprite = preview.components.sprite
        Assert.truthy(sprite:isA(require("engine").SceneComponent))
        Assert.truthy(sprite:isA(require("engine").LObjectComponent))
        Assert.equal(30, sprite:getWorldPosition())
        Assert.equal(a, app.sceneView:findLObjectAtWorldPosition(40, 0))
        local canvas = love.graphics.newCanvas(64, 64)
        love.graphics.push("all")
        love.graphics.setCanvas(canvas)
        love.graphics.clear(0, 0, 0, 0)
        assert(require("core.sprite_renderer").draw(preview, function(ref) return app.spriteAssets:image(ref) end, function() return 32, 32 end, 1))
        love.graphics.setCanvas()
        local pixels = canvas:newImageData()
        local r, g, b, alpha = pixels:getPixel(32, 32)
        Assert.equal(1, r); Assert.equal(0, g); Assert.equal(0, b); Assert.equal(1, alpha)
        pixels:release(); canvas:release(); love.graphics.pop()
        assert(app:startPlay())
        Assert.equal(imageId, app.runtimeWorld.lobjects[1].components.sprite.properties.image)
        app:draw()
        assert(app:stopPlay())
        app:draw()
        app.spriteAssets:clear()
    end)
end)

add("Prefab component defaults can be edited and instance reset restores Prefab values", function()
    fixture(function(parent)
        local project, prefabId = componentProject(parent)
        local app = EditorApp.new(nil, project)
        assert(app:inspectAsset("Assets/Actor.prefab"))
        app.assetBrowser.selectedReference, app.activePanel = "Assets/Actor.prefab", "assets"
        app:updateInspectorTarget()
        local inspector = app.inspector.classInspector
        assert(inspector:setProperty("sprite.x", 8))
        assert(app:saveInspectedDocument())
        local prefab = assert(require("editor.prefab").decode(assert(FS.read(assert(project:resolveAssetFile(prefabId))))))
        Assert.equal(8, prefab.overrides.components.sprite.x)
        local object = app.level:addLObject(0, 0, prefabId)
        app.sceneView.selectedLObject, app.activePanel = object, "scene"
        app:updateInspectorTarget()
        Assert.equal(8, inspector.class.properties["sprite.x"].default)
        assert(inspector:setProperty("sprite.x", 12))
        assert(inspector:setProperty("sprite.x", 8))
        Assert.equal(nil, object.componentOverrides.sprite)
        assert(app:startPlay())
        Assert.equal(8, app.runtimeWorld.lobjects[1].components.sprite.properties.x)
    end)
end)

add("Instance Inspector routes text and reference dropdown input through the UI", function()
    fixture(function(parent)
        local project, prefabId = componentProject(parent)
        local app = EditorApp.new(nil, project)
        local a, b = app.level:addLObject(0, 0, prefabId), app.level:addLObject(20, 0, prefabId)
        app.sceneView.selectedLObject, app.activePanel = a, "scene"
        app:draw()
        local inspector = app.inspector.classInspector
        local function field(name)
            for index, key in ipairs(inspector.names) do
                if key == name then
                    inspector.scroll = math.max(0, index - inspector.visibleRows)
                    local y = inspector.propertyTop + 20 + (index - inspector.scroll - 1) * 56
                    return inspector.left + 20, y + 3
                end
            end
            error("Missing field " .. name)
        end
        local x, y = field("title")
        app:mousepressed(x, y, 1)
        app:textinput("새 이름")
        app:keypressed("return")
        Assert.equal("새 이름", a.propertyOverrides.title)
        x, y = field("target")
        app:mousepressed(x, y, 1)
        Assert.truthy(app.uiRoot.popup)
        app:keypressed("down")
        app:keypressed("down")
        app:keypressed("return")
        Assert.equal(b.authoringId, a.propertyOverrides.target)
        Assert.equal(nil, app.uiRoot.popup)
        app:mousepressed(x, y, 1)
        app:keypressed("escape")
        Assert.equal(b.authoringId, a.propertyOverrides.target)
        local spriteX, spriteY = field("sprite.x")
        app:mousepressed(spriteX, spriteY, 1)
        app:textinput("17")
        app:keypressed("return")
        Assert.equal(17, a.componentOverrides.sprite.x)
    end)
end)

add("Prefab asset selection cannot replace the instance Inspector when editing after selection", function()
    fixture(function(parent)
        local project, prefabId = componentProject(parent)
        local app = EditorApp.new(nil, project)
        local a, b = app.level:addLObject(0, 0, prefabId), app.level:addLObject(80, 0, prefabId)
        local browser = app.assetBrowser
        browser:setViewMode("list"); browser:openFolder("Assets")
        local bx, by = browser.fileSlot.widget.x + 20, browser.fileSlot.widget.y + 5
        app:mousepressed(bx, by, 1); app:mousereleased(bx, by, 1); app:draw()
        Assert.equal(app.prefabInspectorTarget, app.inspector.classInspector.target)
        assert(app.inspector.classInspector:setProperty("speed", 77))
        local function editSpeed(object, value)
            app:draw()
            local inspector = app.inspector.classInspector
            Assert.equal(object, inspector.target.data)
            local index
            for i, name in ipairs(inspector.names) do if name == "speed" then index = i end end
            inspector.scroll = math.max(0, index - inspector.visibleRows)
            local y = inspector.propertyTop + 23 + (index - inspector.scroll - 1) * 56
            app:mousepressed(inspector.left + 20, y, 1)
            Assert.equal(object, inspector.target.data)
            app:textinput(tostring(value)); app:keypressed("return")
            Assert.equal(value, object.propertyOverrides.speed)
            Assert.equal(77, app.prefabDocument.data.overrides.properties.speed)
            app:draw()
            Assert.equal(object, inspector.target.data)
        end
        local x, y = app.sceneView:worldToScreen(0, 0)
        app:mousepressed(x, y, 1); app:mousereleased(x, y, 1)
        editSpeed(a, 55)
        app:mousepressed(bx, by, 1); app:mousereleased(bx, by, 1); app:draw()
        Assert.equal(app.prefabInspectorTarget, app.inspector.classInspector.target)
        app:mousepressed(20, 76, 1)
        Assert.equal(b, app.sceneView.selectedLObject)
        editSpeed(b, 66)
    end)
end)

add("Invalid Prefab placement preserves the scene and component errors contain Play", function()
    fixture(function(parent)
        local project, prefabId = componentProject(parent)
        local app = EditorApp.new(nil, project)
        local x, y = app.sceneView:worldToScreen(0, 0)
        assert(FS.writeAtomic(assert(project:resolveAssetFile(prefabId)), "invalid json"))
        local ok = app:placePrefab(prefabId, x, y)
        Assert.equal(false, ok)
        Assert.equal(0, #app.level.lobjects)
        assert(FS.writeAtomic(assert(project:resolveAssetFile(prefabId)), assert(require("editor.prefab").encode(project:getAssetId("Sources/Actor.lua")))))
        app.level:addLObject(0, 0, prefabId).componentOverrides = {missing = {x = 1}}
        local started, err = app:startPlay()
        Assert.equal(false, started)
        Assert.truthy(err:find("Unknown component", 1, true))
        Assert.equal(nil, app.runtimeWorld)
        app.level.lobjects[1].componentOverrides = nil
        local source = assert(project:resolveSourceFile("Sources/Actor.lua"))
        assert(FS.writeAtomic(source, [[
local E = require("engine")
local Bad = E.LObjectComponent:extend()
function Bad:Load() error("component load error") end
return {build = function(self) self:addComponent("bad", Bad) end}
]]))
        started, err = app:startPlay()
        Assert.equal(false, started)
        Assert.truthy(err:find("component load error", 1, true))
        Assert.equal(nil, app.runtimeWorld)
        assert(FS.writeAtomic(source, [[
local E = require("engine")
local Bad = E.LObjectComponent:extend()
function Bad:Update() return false, "component update error" end
return {build = function(self) self:addComponent("bad", Bad) end}
]]))
        assert(app:startPlay())
        app:update(0.1)
        Assert.equal(nil, app.runtimeWorld)
        Assert.truthy(app.runtimeError:find("component update error", 1, true))
    end)
end)

return tests
