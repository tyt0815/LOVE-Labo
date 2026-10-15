local Assert = require("tests.Assert")
local Fs = require("editor.HostFileSystem")
local Browser = require("editor.ProjectStart")
local Recent = require("editor.RecentProjects")
local tests = {}
local function add(name, fn) tests[#tests + 1] = {name = name, fn = fn} end

add("Project Browser selects browses opens creates and cancels", function()
    local project = assert(require("editor.Project").create(Fs.join(love.filesystem.getSourceBaseDirectory(), "build"),
        "Browser_" .. os.time() .. "_" .. love.math.random(100000, 999999)))
    local opened, saved, canceled
    local browser = Browser.new(function(value) opened = value; return true end,
        function() return project.rootPath end,
        {entries = {{path = project.rootPath, name = project.name}},
            saveRecent = function(entries) saved = entries end, cancel = function() canceled = true end})
    Assert.equal("open", browser.mode)
    local card = browser:layout().cards[2]
    browser:mousepressed(card.x + 10, card.y + 10, 1)
    Assert.equal(project.rootPath, browser.path); Assert.equal(project.name, browser.name)
    browser:draw()
    assert(browser:submit()); Assert.equal(project.rootPath, opened.rootPath); Assert.equal(1, #saved)
    browser:setPath(Fs.join(project.rootPath, "missing")); Assert.equal("", browser.name)
    Assert.equal(false, browser:submit()); Assert.truthy(browser.error)
    browser:browse(); Assert.equal(project.name, browser.name); Assert.equal(nil, browser.error)
    browser:selectEntry(1); browser:setPath(project.rootPath); browser.name = "Child"
    assert(browser:submit()); Assert.equal("Child", opened.name)
    local cancel = browser:layout().cancel
    browser:mousepressed(cancel.x + 1, cancel.y + 1, 1); Assert.equal(true, canceled)
end)

add("Empty recent history still allows switching from creation to opening", function()
    local project = assert(require("editor.Project").create(Fs.join(love.filesystem.getSourceBaseDirectory(), "build"),
        "BrowserMode_" .. os.time() .. "_" .. love.math.random(100000, 999999)))
    local opened
    local browser = Browser.new(function(value) opened = value; return true end,
        function() return project.rootPath end, {entries = {}, saveRecent = function() end})
    browser:selectEntry(1); Assert.equal("create", browser.mode)
    browser:draw()
    local button = browser:layout().openExisting
    browser:mousepressed(button.x + 1, button.y + 1, 1)
    Assert.equal("open", browser.mode); Assert.equal(nil, browser.selected)
    browser:browse(); Assert.equal(project.name, browser.name)
    Assert.equal(nil, opened)
    assert(browser:submit()); Assert.equal(project.rootPath, opened.rootPath)
end)

add("Browsing and canceling legacy projects does not migrate files before Open", function()
    local root = Fs.join(Fs.join(love.filesystem.getSourceBaseDirectory(), "build"),
        "BrowserReadOnly_" .. os.time() .. "_" .. love.math.random(100000, 999999))
    assert(Fs.mkdir(root)); assert(Fs.mkdir(Fs.join(root, "Sources")))
    local manifest = [[{"version":1,"name":"Legacy Browser"}]]
    local source = "return {}"
    assert(Fs.writeAtomic(Fs.join(root, "project.labo"), manifest))
    assert(Fs.writeAtomic(Fs.join(root, "Sources/Legacy.lua"), source))
    local canceled, opened
    local browser = Browser.new(function(value) opened = value; return true end, function() return root end,
        {entries = {}, saveRecent = function() end, cancel = function() canceled = true end})
    browser:browse(); Assert.equal("Legacy Browser", browser.name)
    browser:draw()
    local button = browser:layout().cancel
    browser:mousepressed(button.x + 1, button.y + 1, 1)
    Assert.equal(true, canceled); Assert.equal(nil, opened)
    Assert.equal(nil, Fs.info(Fs.join(root, "Assets")))
    Assert.equal(nil, Fs.info(Fs.join(root, "assets.json")))
    Assert.equal(manifest, assert(Fs.read(Fs.join(root, "project.labo"))))
    Assert.equal(source, assert(Fs.read(Fs.join(root, "Sources/Legacy.lua"))))
    assert(browser:submit())
    Assert.truthy(opened)
    Assert.truthy(Fs.info(Fs.join(root, "Assets")))
    Assert.equal(source, assert(Fs.read(Fs.join(root, "Assets/Scripts/Legacy.lua"))))
end)

add("Recent project history validates deduplicates caps and round trips", function()
    local entries = Recent.load(function() return [[{"version":1,"projects":[{"path":"C:\\Demo","name":"Demo"},{"path":"c:/Demo","name":"Duplicate"},{"path":5,"name":"Invalid"}]}]] end)
    Assert.equal(1, #entries); Assert.equal("C:/Demo", entries[1].path)
    entries = Recent.remember(entries, {rootPath = "c:/Demo", name = "Renamed"})
    Assert.equal(1, #entries); Assert.equal("Renamed", entries[1].name)
    for index = 1, 40 do entries = Recent.remember(entries, {rootPath = "C:/Project" .. index, name = "Project" .. index}) end
    Assert.equal(Recent.LIMIT, #entries)
    local bytes
    assert(Recent.save(entries, function(_, value) bytes = value; return true end))
    Assert.equal("Project40", Recent.load(function() return bytes end)[1].name)
    Assert.equal(0, #Recent.load(function() return "broken" end))
end)

add("Project Browser scroll bounds and footer fit the minimum window", function()
    local width, height, flags = love.window.getMode()
    local ok, err = xpcall(function()
        assert(love.window.setMode(800, 540, {resizable = true}))
        local entries = {}
        for index = 1, 30 do entries[index] = {path = "C:/Project" .. index, name = "Project" .. index} end
        local browser = Browser.new(function() end, nil, {entries = entries, saveRecent = function() end})
        browser:wheelmoved(0, -1000)
        local layout = browser:layout()
        Assert.equal(browser.maxScroll, browser.scroll)
        Assert.truthy(layout.cards[#layout.cards].y + layout.cardHeight <= layout.grid.y + layout.grid.h)
        Assert.truthy(layout.name.x >= layout.path.x + layout.path.w)
        browser:draw(); browser:wheelmoved(0, 1000); Assert.equal(0, browser.scroll)
    end, debug.traceback)
    love.window.setMode(width, height, flags)
    assert(ok, err)
end)

return tests
