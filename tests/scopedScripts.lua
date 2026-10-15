local Assert = require("tests.Assert")
local Fs = require("editor.HostFileSystem")
local Loader = require("runtime.WorldLoader")
local tests = {}
local function add(name, fn) tests[#tests + 1] = {name = name, fn = fn} end
local function fixture()
    local project = assert(require("editor.Project").create(Fs.join(love.filesystem.getSourceBaseDirectory(), "build"),
        "Scopes_" .. os.time() .. "_" .. love.math.random(100000, 999999)))
    assert(project:createEntry("Assets", "lua", "Trace", {scriptKind = "script"}))
    assert(Fs.writeAtomic(project:resolveSourceFile("Assets/Trace.lua"), [[
local Trace = {properties = {count = {type = "number", default = 0, group = "Counters"}}}
local function record(self, kind)
    local project = self:getProject()
    project.trace = project.trace or {}
    project.trace[#project.trace + 1] = (self.owner.scope or "object") .. ":" .. kind
end
function Trace:load() record(self, "load"); self.initialized = (self.initialized or 0) + 1 end
function Trace:update(dt) self.count = self.count + 1; record(self, "update") end
function Trace:unload() record(self, "unload") end
function Trace:keypressed(key) self.lastKey = key; record(self, "key") end
function Trace:draw() record(self, "draw"); self.drawX, self.drawY = love.graphics.transformPoint(0, 0) end
function Trace:drawScreen() record(self, "screen"); self.screenX, self.screenY = love.graphics.transformPoint(0, 0) end
return Trace
]]))
    assert(project:rebuildAssetIndex())
    local source = project:getAssetId("Assets/Trace.lua")
    local function attachment(name) return {id = require("project.AssetId").new(), name = name, source = source} end
    project.scripts = {attachment("manager")}; assert(project:saveScripts())
    local level = require("editor.Level").new(); level.scripts = {attachment("levelManager")}
    level:addLObject(30, 40).scripts = {attachment("actor")}
    return project, level, source
end
add("Scopes share lookup lifecycle events and ordered updates", function()
    local project, level = fixture(); local world = assert(Loader.create(project, level:toData()))
    local session = world:getProject()
    Assert.equal("project:load,level:load,object:load", table.concat(session.trace, ","))
    local manager, current, actor = session:getScriptByName("manager"), world:getScriptByName("levelManager"), world.lobjects[1]:getScriptByName("actor")
    Assert.equal(world, manager:getWorld()); Assert.equal(session, actor:getProject())
    Assert.equal(manager, session:getScriptById(manager.id)); Assert.equal(manager, session:getScriptByClass(getmetatable(manager)))
    Assert.equal(1, #world:getScriptsByClass(getmetatable(current))); Assert.equal(1, #world:getObjects())
    assert(world:update(0.1)); Assert.equal("project:update,level:update,object:update", table.concat(session.trace, ",", 4))
    assert(world:dispatchEvent("keypressed", "space")); Assert.equal("space", manager.lastKey); Assert.equal("space", current.lastKey)
    actor.enabled = false; assert(world:update(0.1)); Assert.equal(1, actor.count); Assert.equal(2, manager.count)
    assert(world:dispose()); Assert.equal(nil, session:getWorld())
    Assert.equal("object:unload,level:unload,project:unload", table.concat(session.trace, ",", #session.trace - 2))
end)
add("Transitions retain project instances and replace level instances with shared class identity", function()
    local project, level = fixture(); assert(project:createEntry("Assets", "level", "L_Next", {empty = true}))
    assert(require("editor.LevelFile").save(project:resolveAssetFile("Assets/L_Next.level"), level))
    local world = assert(Loader.create(project, level:toData()))
    local session, previous = world.project, world:getScriptByName("levelManager"); local manager = session:getScriptByName("manager")
    assert(world:openLevel("Assets/L_Next.level")); local nextWorld = assert(world:takeLevelTransition())
    Assert.equal(session, nextWorld.project); Assert.equal(nextWorld, manager:getWorld()); Assert.equal(1, manager.initialized)
    Assert.truthy(previous.hasUnloaded); Assert.truthy(previous ~= nextWorld:getScriptByName("levelManager"))
    Assert.equal(getmetatable(manager), getmetatable(nextWorld:getScriptByName("levelManager")))
    assert(nextWorld:dispose()); Assert.truthy(manager.hasUnloaded)
end)
add("World and screen drawing prepare different coordinates and restore graphics state", function()
    local project, level = fixture(); local world = assert(Loader.create(project, level:toData()))
    local viewport = require("core.Viewport").new(world, 10, 20, 400, 300)
    love.graphics.push("all"); love.graphics.origin(); love.graphics.translate(7, 8)
    local x, y = love.graphics.transformPoint(0, 0); require("core.Renderer").drawWorld(world, function() end, viewport)
    local ax, ay = love.graphics.transformPoint(0, 0); love.graphics.pop(); Assert.equal(x, ax); Assert.equal(y, ay)
    local manager, actor = world.project:getScriptByName("manager"), world.lobjects[1]:getScriptByName("actor")
    Assert.equal(210, manager.drawX); Assert.equal(170, manager.drawY); Assert.equal(240, actor.drawX); Assert.equal(210, actor.drawY)
    Assert.equal(10, actor.screenX); Assert.equal(20, actor.screenY)
    Assert.equal("project:draw,level:draw,object:draw,object:screen,level:screen,project:screen", table.concat(world.project.trace, ",", 4)); assert(world:dispose())
end)
add("Scope CLI persists overrides names order and enforces revisions", function()
    local project, level, source = fixture(); assert(project:createEntry("Assets", "level", "L_Test", {empty = true}))
    local function run(command, fields)
        fields = fields or {}; fields.command, fields.project, fields.level = command, project.rootPath, "Assets/L_Test.level"
        return require("editor.Cli").execute(fields)
    end
    local before = run("project.script.get"); run("project.script.add", {source = source, script = "second"})
    run("project.script.move", {script = "second", index = 1}); run("project.script.rename", {script = "second", name = "renamed"})
    run("project.script.set", {property = "renamed.count", value = 12}); Assert.equal(12, run("project.script.get").values["renamed.count"])
    Assert.equal(false, pcall(run, "project.script.remove", {script = "renamed", revision = before.revision}))
    run("level.script.add", {source = source, script = "level"}); run("level.script.set", {property = "level.count", value = 4})
    Assert.equal(4, run("level.script.get").values["level.count"]); run("level.script.reset", {property = "level.count"})
    Assert.equal(0, run("level.script.get").values["level.count"])
    local fresh = assert(require("editor.Project").open(project.rootPath)); Assert.equal("renamed", fresh.scripts[1].name)
    local world = assert(Loader.create(fresh, level:toData())); Assert.equal(12, world.project:getScriptByName("renamed").count); assert(world:dispose())
end)
add("Scope Inspector tabs edit save undo separate documents and nest property groups", function()
    local project, level = fixture(); assert(project:createEntry("Assets", "level", "L_Test", {empty = true}))
    assert(require("editor.LevelFile").save(project:resolveAssetFile("Assets/L_Test.level"), level))
    local app = require("editor.EditorApp").new(nil, project); app:draw(); Assert.equal(nil, app.inspector.classInspector.target)
    app.inspector.tab = "Project"; app:updateInspectorTarget(); app:draw(); local inspector = app.inspector.classInspector
    local stable = inspector.target
    app:updateInspectorTarget(); app:draw(); Assert.equal(stable, inspector.target)
    inspector.editing, inspector.text, inspector.replace = project.scripts[1].id .. ".count", "12", false
    app:updateInspectorTarget(); app:draw(); Assert.equal(project.scripts[1].id .. ".count", inspector.editing)
    inspector:cancelEdit()
    Assert.equal("Project", inspector.target.label); app:recordHistory(); assert(inspector:setProperty("manager.count", 9)); app:recordHistory()
    assert(app:undoRedo(-1)); Assert.equal(nil, project.scriptOverrides[project.scripts[1].id]); assert(app:undoRedo(1)); assert(app:saveInspectedDocument())
    Assert.equal(9, assert(require("editor.Project").open(project.rootPath)).scriptOverrides[project.scripts[1].id].count)
    assert(app:inspectAsset("Assets/L_Test.level")); app:draw(); Assert.equal("Selection", app.inspector.tab)
    local headers, nested = 0, false
    for _, row in ipairs(inspector.rows) do
        if row.scriptId then headers = headers + 1; Assert.truthy(inspector:scriptSource(row.scriptId)) end
        if row.label == "Counters" then nested = row.depth == 1 end
    end
    Assert.equal(1, headers); Assert.equal(true, nested)
    assert(inspector:setProperty("levelManager.count", 7)); assert(app:saveInspectedDocument())
    Assert.equal(7, assert(require("editor.LevelDocument").load(project:resolveAssetFile("Assets/L_Test.level"))).level.scriptOverrides[level.scripts[1].id].count)
end)
add("Asset summaries stay below Inspector tabs and respect the panel offset", function()
    local Ui = require("editor.Ui")
    local inspector = require("editor.Inspector").new(nil)
    inspector.y = 37
    local originalLabel, originalText = Ui.label, Ui.text
    local rows = {}
    local function capture(text, x, y) rows[text] = y end
    Ui.label, Ui.text = capture, capture
    local ok, message = xpcall(function()
        for _, kind in ipairs({"Image", "Lua", "Folder"}) do
            inspector.assetSummary = {name = "Summary name", kind = kind, reference = "Assets/Summary"}
            for _, tabs in ipairs({false, true}) do
                inspector.onTabChanged = tabs and function() end or nil
                rows = {}
                inspector:draw()
                local top = inspector.y + (tabs and 32 or 0) + Ui.METRICS.contentPaddingY
                Assert.equal(top + 44, rows["Summary name"])
                Assert.equal(top + 60, rows[kind])
                Assert.equal(top + 86, rows["Assets/Summary"])
                local hint = kind == "Folder" and "Double-click to browse" or "Read-only asset information"
                Assert.equal(top + 110, rows[hint])
                if tabs then Assert.truthy(rows["Summary name"] > inspector.y + 60) end
            end
        end
    end, debug.traceback)
    Ui.label, Ui.text = originalLabel, originalText
    assert(ok, message)
end)
add("Missing registrations support ordinary delete Undo Redo and reference protection", function()
    local project = fixture(); assert(project:createEntry("Assets", "lua", "Gone", {scriptKind = "script"}))
    local reference = "Assets/Gone.lua"; local id = project:getAssetId(reference)
    assert(Fs.removeFile(project:resolvePath(reference))); assert(project:rebuildAssetIndex())
    local app = require("editor.EditorApp").new(nil, project)
    assert(app.assetBrowser.assetOperations:delete(reference)); Assert.equal(nil, project:getAssetReference(id))
    assert(app:undoRedo(-1)); Assert.equal(reference, project:getAssetReference(id)); Assert.equal(nil, Fs.info(project:resolvePath(reference)))
    assert(app:undoRedo(1)); Assert.equal(nil, project:getAssetReference(id)); assert(app:undoRedo(-1))
    project.scripts[#project.scripts + 1] = {id = require("project.AssetId").new(), source = id, name = "missing"}
    Assert.equal(false, project:deleteEntry(reference))
end)
add("Failed candidate initialization preserves the active project and current World", function()
    local project, level = fixture()
    assert(project:createEntry("Assets", "lua", "Broken", {scriptKind = "script"}))
    assert(Fs.writeAtomic(project:resolveSourceFile("Assets/Broken.lua"), "return {load = function() error('candidate failed') end}"))
    local failed = require("editor.Level").new()
    failed.scripts = {{id = require("project.AssetId").new(), name = "broken", source = project:getAssetId("Assets/Broken.lua")}}
    assert(project:createEntry("Assets", "level", "L_Broken", {empty = true}))
    assert(require("editor.LevelFile").save(project:resolveAssetFile("Assets/L_Broken.level"), failed))
    local world = assert(Loader.create(project, level:toData()))
    local manager = world.project:getScriptByName("manager")
    assert(world:openLevel("Assets/L_Broken.level")); local nextWorld, err = world:takeLevelTransition()
    Assert.equal(nil, nextWorld); Assert.truthy(err:find("candidate failed", 1, true))
    Assert.equal(world, manager:getWorld()); Assert.equal(nil, manager.hasUnloaded)
    Assert.equal(nil, world:getScriptByName("levelManager").hasUnloaded)
    assert(world:update(0.1)); Assert.equal(1, manager.count); assert(world:dispose())
end)
add("Screen drawing errors restore state and scoped Pointer callbacks participate in captures", function()
    local project, level = fixture(); local world = assert(Loader.create(project, level:toData()))
    local manager = world.project:getScriptByName("manager")
    manager.pointer = true
    manager.getBoundsSource = function(self) return self end
    manager.hitTest = function() return true, 0, 0 end
    manager.onPointerDown = function(self, event) self.pressed = true; return true end
    manager.onPointerUp = function(self, event) self.released = true; return true end
    assert(world:dispatchPointer("down", 0, 0, 1)); Assert.equal(true, manager.pressed)
    Assert.equal(manager, world.pointerCaptures[1]); assert(world:dispatchPointer("up", 100, 100, 1)); Assert.equal(true, manager.released)
    local viewport = require("core.Viewport").new(world, 0, 0, 400, 300)
    manager.drawScreen = function() love.graphics.translate(999, 999); error("screen failure") end
    love.graphics.push("all"); love.graphics.origin(); love.graphics.translate(13, 14)
    Assert.equal(false, pcall(require("core.Renderer").drawWorld, world, function() end, viewport))
    local x, y = love.graphics.transformPoint(0, 0); love.graphics.pop()
    Assert.equal(13, x); Assert.equal(14, y); assert(world:dispose())
end)
add("Unopened level reference picking stays within its document and preserves the current scene", function()
    local project, level = fixture()
    assert(project:createEntry("Assets", "level", "L_Detached", {empty = true}))
    assert(require("editor.LevelFile").save(project:resolveAssetFile("Assets/L_Detached.level"), level))
    local app = require("editor.EditorApp").new(nil, project)
    local original = app.level
    assert(app:inspectAsset("Assets/L_Detached.level")); app:draw()
    local target = app.inspector.classInspector.target
    Assert.truthy(target.level ~= original)
    assert(app:beginObjectPick("$mainCamera"))
    Assert.truthy(app.uiRoot.popup); Assert.equal(nil, app.objectPick)
    app.uiRoot.popup:submit(); Assert.equal(original, app.level)
    assert(app.inspector.classInspector:setProperty("levelManager.count", 11))
    local bytes = assert(project:readAsset(project:getAssetId("Assets/L_Detached.level")))
    local draft = assert(require("editor.LevelFile").decode(bytes))
    Assert.equal(11, draft.scriptOverrides[level.scripts[1].id].count)
    assert(app:openProjectDocument("Assets/L_Detached.level", true))
    Assert.equal(target.level, app.level)
end)
add("Cached level paths follow rename folder moves Undo Redo and Save All by asset ID", function()
    local project, level = fixture()
    assert(project:createEntry("Assets", "folder", "Drafts"))
    assert(project:createEntry("Assets/Drafts", "level", "L_Cached", {empty = true}))
    local original = "Assets/Drafts/L_Cached.level"
    assert(require("editor.LevelFile").save(project:resolveAssetFile(original), level))
    local id = project:getAssetId(original)
    local app = require("editor.EditorApp").new(nil, project)
    assert(app:inspectAsset(original)); app:draw()
    local inspector = app.inspector.classInspector
    local document = inspector.target.scopeDocument
    assert(inspector:setProperty("levelManager.count", 8)); app:recordHistory()
    local operations = app.assetBrowser.assetOperations
    local renamed = "Assets/Drafts/L_Renamed.level"
    assert(operations:move({reference = original}, renamed))
    Assert.equal(project:resolveAssetFile(id), document.path)
    assert(app:undoRedo(-1)); Assert.equal(project:resolveAssetFile(id), document.path)
    Assert.equal(original, project:getAssetReference(id))
    assert(app:undoRedo(1)); Assert.equal(project:resolveAssetFile(id), document.path)
    assert(app:saveInspectedDocument())
    Assert.equal(nil, Fs.info(project:resolvePath(original)))
    Assert.equal(8, assert(require("editor.LevelFile").load(project:resolveAssetFile(id))).scriptOverrides[level.scripts[1].id].count)
    assert(operations:move({reference = "Assets/Drafts"}, "Assets/MovedDrafts"))
    assert(app:undoRedo(-1)); assert(app:undoRedo(1))
    Assert.equal("Assets/MovedDrafts/L_Renamed.level", project:getAssetReference(id))
    Assert.equal(project:resolveAssetFile(id), document.path)
    assert(app.inspector.classInspector:setProperty("levelManager.count", 12)); app:recordHistory()
    assert(app:saveAllDocuments())
    assert(app.uiRoot.popup.options.onConfirm("", nil, {{scopeDocument = document}}))
    app.uiRoot:dismissPopup()
    Assert.equal(12, assert(require("editor.LevelFile").load(project:resolveAssetFile(id))).scriptOverrides[level.scripts[1].id].count)
    Assert.equal(nil, Fs.info(project:resolvePath("Assets/Drafts")))
end)
add("Clean cached levels reload CLI edits on reopen and discard stale document history", function()
    local project, level = fixture(); level.lobjects = {}
    assert(project:createEntry("Assets", "level", "L_Cached", {empty = true}))
    local reference = "Assets/L_Cached.level"
    assert(require("editor.LevelFile").save(project:resolveAssetFile(reference), level))
    local app = require("editor.EditorApp").new(nil, project)
    assert(app:inspectAsset(reference)); app:draw()
    local document = app.inspector.classInspector.target.scopeDocument
    assert(app.inspector.classInspector:setProperty("levelManager.count", 3)); app:recordHistory()
    assert(app:saveInspectedDocument()); Assert.equal(false, document:isDirty())
    require("editor.Cli").execute({command = "instance.add", project = project.rootPath, level = reference, name = "External"})
    Assert.equal(0, #document.level.lobjects)
    assert(app:openProjectDocument(reference, true))
    Assert.equal(document, app.document); Assert.equal(1, #app.level.lobjects)
    Assert.equal("External 1", app.level.lobjects[1].name)
    Assert.equal(false, app:undoRedo(-1))
    assert(app:saveCurrentDocument())
    Assert.equal(1, #assert(require("editor.LevelFile").load(project:resolveAssetFile(reference))).lobjects)
end)
add("Reselecting clean cached levels reloads the Inspector while dirty drafts survive external edits", function()
    local project, level = fixture(); level.lobjects = {}
    assert(project:createEntry("Assets", "level", "L_Cached", {empty = true}))
    local reference = "Assets/L_Cached.level"
    assert(require("editor.LevelFile").save(project:resolveAssetFile(reference), level))
    local app = require("editor.EditorApp").new(nil, project); local scene = app.level
    assert(app:inspectAsset(reference)); app:draw()
    require("editor.Cli").execute({command = "level.script.set", project = project.rootPath, level = reference, property = "levelManager.count", value = 6})
    assert(app:inspectAsset(reference)); app:draw()
    local target = app.inspector.classInspector.target
    Assert.equal(6, target:getOverrides()[level.scripts[1].id .. ".count"])
    Assert.equal(scene, app.level)
    assert(app.inspector.classInspector:setProperty("levelManager.count", 22))
    require("editor.Cli").execute({command = "instance.add", project = project.rootPath, level = reference, name = "External"})
    assert(app:openProjectDocument(reference, true))
    Assert.equal(target.level, app.level); Assert.equal(0, #app.level.lobjects)
    Assert.equal(22, app.level.scriptOverrides[level.scripts[1].id].count)
    Assert.equal(1, #assert(require("editor.LevelFile").load(project:resolveAssetFile(reference))).lobjects)
end)
add("Save As rebinds a cached document without aliasing the original level asset", function()
    local project = fixture(); assert(project:createEntry("Assets", "level", "L_Original", {empty = true}))
    local original = "Assets/L_Original.level"; local originalId = project:getAssetId(original)
    local app = require("editor.EditorApp").new(nil, project)
    assert(app:openProjectDocument(original, true)); assert(app:inspectAsset(original)); app:draw()
    local document = app.document
    app.level:addLObject(10, 20)
    local destination = "Assets/L_Copy.level"
    assert(app:saveCurrentDocument(project:resolvePath(destination)))
    local copyId = project:getAssetId(destination)
    Assert.equal(copyId, document.assetId)
    Assert.equal(nil, app.scopeInspector.levels[originalId])
    assert(app:inspectAsset(original)); app:draw()
    local originalDocument = app.inspector.classInspector.target.scopeDocument
    Assert.truthy(originalDocument ~= document); Assert.equal(0, #originalDocument.level.lobjects)
    Assert.equal(1, #document.level.lobjects)
    assert(app:saveNewLevel("Assets/L_SecondCopy.level"))
    Assert.equal(project:getAssetId("Assets/L_SecondCopy.level"), document.assetId)
    Assert.equal(nil, app.scopeInspector.levels[copyId])
    assert(app:inspectAsset(destination)); app:draw()
    Assert.truthy(app.inspector.classInspector.target.scopeDocument ~= document)
end)
return tests
