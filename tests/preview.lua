local Assert = require("tests.Assert")
local Fs = require("editor.HostFileSystem")
local tests = {}
local function add(name, fn) tests[#tests + 1] = {name = name, fn = fn} end
local function fixture()
    local p = assert(require("editor.Project").create(Fs.join(love.filesystem.getSourceBaseDirectory(), "build"),
        "PreviewTest_" .. os.time() .. "_" .. love.math.random(100000, 999999)))
    assert(p:createEntry("Assets", "lua", "Visual", {scriptKind = "script"}))
    assert(Fs.writeAtomic(assert(p:resolveSourceFile("Assets/Visual.lua")), [[local Visual = {properties = {width = {type = "number", default = 10}}}
function Visual.load() error("Preview must not load") end
function Visual.update() error("Preview must not update") end
function Visual.getLocalBounds(self) return -self.width / 2, -5, self.width, 10 end
function Visual.draw(self) love.graphics.setColor(1, 0, 0, 1); love.graphics.rectangle("fill", -self.width / 2, -5, self.width, 10) end
return Visual
]]))
    assert(p:rebuildAssetIndex()); assert(p:createEntry("Assets", "prefab", "PF_Visual"))
    local doc = assert(require("editor.PrefabDocument").load(p, "Assets/PF_Visual.prefab"))
    p.draftAssets = {[doc.assetId] = doc}
    local editor = require("editor.PrefabEditor").new(p, doc, function() p.draftRevision = (p.draftRevision or 0) + 1 end, function() end)
    assert(editor:addScript("root", p:getAssetId("Assets/Visual.lua"), "visual"))
    return p, doc, editor
end
add("Live previews use draft values without lifecycle callbacks or authoring mutations", function()
    local p, doc, editor = fixture()
    local target = assert(editor:target("root")); local values = target:getOverrides(); values["visual.width"] = 30
    target:setOverrides(values)
    local model = require("editor.Preview").new(p, {reference = doc.assetId})
    Assert.equal(30, model.objects[1]:getScriptByName("visual").width)
    Assert.equal(false, model.objects[1]:getScriptByName("visual").hasLoaded == true)
    local before = assert(require("project.Prefab").encodeData(doc.data))
    local canvas = love.graphics.newCanvas(80, 80); love.graphics.setCanvas(canvas)
    assert(model:draw({x = 0, y = 0, w = 80, h = 80})); love.graphics.setCanvas()
    Assert.equal(before, require("project.Prefab").encodeData(doc.data))
    model:release(); canvas:release()
end)
add("Prefab thumbnails stay at saved values and become invalid when dependencies change", function()
    local p, doc, editor = fixture(); doc.data.previewBackground = {0, 100, 200}
    assert(doc:save(p)); Assert.truthy(require("editor.PreviewCache").read(p, doc.assetId))
    local png = require("editor.PreviewCache").paths(p, doc.assetId)
    local image = love.image.newImageData(love.filesystem.newFileData(assert(Fs.read(png)), "preview.png"))
    local r, g, b = image:getPixel(0, 0); Assert.equal(0, r); Assert.truthy(g > 0.38 and g < 0.40); Assert.truthy(b > 0.78 and b < 0.79)
    image:release()
    local bytes = Fs.read(png)
    local target = assert(editor:target("root")); local values = target:getOverrides(); values["visual.width"] = 50
    target:setOverrides(values); Assert.equal(bytes, require("editor.PreviewCache").read(p, doc.assetId))
    assert(Fs.writeAtomic(assert(p:resolveSourceFile("Assets/Visual.lua")), "local Visual = {properties = {}}\nreturn Visual"))
    Assert.equal(nil, require("editor.PreviewCache").read(p, doc.assetId))
end)
add("Preview is independent from Inspector scrolling and supports resizing and CLI PNG", function()
    local p, doc = fixture(); assert(doc:save(p))
    local app = require("editor.EditorApp").new(nil, p); assert(app:inspectAsset("Assets/PF_Visual.prefab")); app:draw()
    local top = app.previewPanel.y
    app.inspector.classInspector.scroll = 100; app:draw(); Assert.equal(top, app.previewPanel.y)
    app.uiLayout.drag = {preview = true}; app.uiLayout:resize(app.previewPanel.x + 30, top + 40); app.uiLayout.drag = nil
    Assert.truthy(app.previewPanel.y > top)
    assert(app.previewPanel:setBackground({10, 20, 30})); Assert.equal(10, app.prefabDocument.data.previewBackground[1])
    Assert.equal(false, app.previewPanel:setBackground({-1, 20, 30}))
    local output = Fs.join(p.rootPath, "Preview.png")
    local result = require("editor.Cli").execute({command = "asset.preview", project = p.rootPath, asset = doc.assetId, output = output})
    Assert.equal(false, result.lifecycleExecuted); Assert.truthy(Fs.info(output))
end)
add("Inspector wheel scroll survives drawing with a large independent preview panel", function()
    local p, doc = fixture(); assert(doc:save(p))
    local app = require("editor.EditorApp").new(nil, p)
    app.previewHeight = love.graphics.getHeight() - 200
    assert(app:inspectAsset("Assets/PF_Visual.prefab")); app:draw()
    local function scrollAndDraw()
        local inspector = app.inspector.classInspector
        local x, y = app.inspectorWidget.x + 40, inspector.propertyTop + inspector.propertyHeight - 4
        app.uiRoot:wheelmoved(x, y, -2)
        local scroll = inspector.scroll; Assert.truthy(scroll > 0, "scroll=" .. scroll .. ", max=" .. inspector.maxScroll .. ", height=" .. inspector.propertyHeight .. ", widget=" .. app.inspectorWidget.height .. ", inspector=" .. tostring(app.inspector.height) .. ", bottom=" .. inspector.propertyBottom)
        app:draw(); Assert.equal(scroll, inspector.scroll)
        app:updateInspectorTarget(); Assert.equal(scroll, inspector.scroll)
        app.uiRoot:wheelmoved(app.previewPanel.x + 40, app.previewPanel.y + 60, -2)
        Assert.equal(scroll, inspector.scroll)
    end
    scrollAndDraw()
    local object = app.level:addLObject(0, 0, doc.assetId)
    app.inspectorSource = "scene"; app.sceneView:setSelection({object}); app:updateInspectorTarget(); app:draw()
    scrollAndDraw()
end)
add("Visual Prefabs with the core Script attachment generate saved thumbnails", function()
    local p, doc, editor = fixture()
    assert(editor:addScript("root", "Script", "base")); assert(doc:save(p))
    assert(require("editor.PreviewCache").save(p, doc.assetId))
    Assert.truthy(require("editor.PreviewCache").read(p, doc.assetId))
end)
add("Browser generates missing saved thumbnails without including drafts or clearing frame caches", function()
    local p, doc = fixture()
    local cache = require("editor.PreviewCache")
    doc.data.previewBackground = {0, 100, 200}
    assert(Fs.writeAtomic(assert(p:resolveAssetFile(doc.assetId)), assert(require("project.Prefab").encodeData(doc.data))))
    Assert.equal(nil, cache.read(p, doc.assetId))
    doc.data.previewBackground = {200, 0, 0}
    local revision = p.thumbnailRevision
    local thumbnails = require("editor.AssetThumbnail").new(p)
    thumbnails:beginFrame()
    local entry = {type = "file", name = "PF_Visual.prefab", reference = "Assets/PF_Visual.prefab"}
    local thumbnail = thumbnails:get(entry)
    Assert.truthy(thumbnail); Assert.equal(revision, p.thumbnailRevision)
    local bytes = assert(cache.read(p, doc.assetId))
    local image = love.image.newImageData(love.filesystem.newFileData(bytes, "thumbnail.png"))
    local r, g, b = image:getPixel(0, 0)
    Assert.equal(0, r); Assert.truthy(g > 0.38 and g < 0.40); Assert.truthy(b > 0.78 and b < 0.79)
    image:release()
    thumbnails:beginFrame(); Assert.equal(thumbnail, thumbnails:get(entry))
    local reused, err, generated = cache.ensure(p, doc.assetId)
    Assert.equal(bytes, reused); Assert.equal(nil, err); Assert.equal(false, generated)
    local source = assert(Fs.read(assert(p:resolveSourceFile("Assets/Visual.lua"))))
    assert(Fs.writeAtomic(assert(p:resolveSourceFile("Assets/Visual.lua")), source:gsub("default = 10", "default = 40")))
    thumbnails:clear(); thumbnails:beginFrame(); Assert.truthy(thumbnails:get(entry))
    Assert.truthy(bytes ~= cache.read(p, doc.assetId)); thumbnails:clear()
end)
add("Empty Prefabs are attempted once per browser cache and CLI creates saved visual thumbnails", function()
    local p, doc = fixture()
    assert(Fs.writeAtomic(assert(p:resolveAssetFile(doc.assetId)), assert(require("project.Prefab").encodeData(doc.data))))
    local first = require("editor.Cli").execute({command = "asset.thumbnail", project = p.rootPath, asset = doc.assetId})
    Assert.equal(true, first.generated); Assert.equal(false, first.lifecycleExecuted); Assert.truthy(Fs.info(first.output))
    local second = require("editor.Cli").execute({command = "asset.thumbnail", project = p.rootPath, asset = doc.assetId})
    Assert.equal(false, second.generated)
    assert(p:createEntry("Assets", "prefab", "PF_Empty"))
    local thumbnails = require("editor.AssetThumbnail").new(p)
    local entry = {type = "file", name = "PF_Empty.prefab", reference = "Assets/PF_Empty.prefab"}
    local cache, attempts = require("editor.PreviewCache"), 0
    local ensure = cache.ensure
    cache.ensure = function(...) attempts = attempts + 1; return ensure(...) end
    local ok, err = pcall(function()
        thumbnails:beginFrame(); Assert.equal(nil, thumbnails:get(entry))
        thumbnails:beginFrame(); Assert.equal(nil, thumbnails:get(entry)); Assert.equal(1, attempts)
    end)
    cache.ensure = ensure; thumbnails:clear(); assert(ok, err)
end)
return tests
