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
add("Project Inspector follows empty selection and the Project menu without scope tabs", function()
    local project = fixture()
    local app = require("editor.EditorApp").new(nil, project)
    app:draw(); Assert.equal("Project", app.inspector.classInspector.target.label)
    local object = app.level:addLObject(0, 0)
    app.sceneView:setSelection({object}); app.inspectorSource = "scene"
    app:updateInspectorTarget(); Assert.truthy(app.inspector.classInspector.target.instance)
    local menu
    for _, item in ipairs(app.menuBar:items("project")) do if item.label == "Inspector" then menu = item end end
    assert(menu); menu.action(); app:draw()
    Assert.equal("Project", app.inspector.classInspector.target.label)
    Assert.equal(object, app.sceneView.selectedLObject)
    Assert.equal(nil, app.previewPanel:descriptor().instance)
    assert(app:inspectAsset("Assets/Trace.lua")); app:draw()
    Assert.truthy(app.inspector.assetSummary)
    assert(app:selectAsset(nil)); app:draw()
    Assert.equal("Project", app.inspector.classInspector.target.label)
    app.inspectorSource = "scene"; app.sceneView:setSelection({object}); app:draw()
    local x, y = app.sceneView:getViewport()
    app:mousepressed(x + 20, y + 20, 1); app:mousereleased(x + 20, y + 20, 1); app:draw()
    Assert.equal(nil, app.sceneView.selectedLObject)
    Assert.equal("Project", app.inspector.classInspector.target.label)
end)
add("Level Camera uses the same section box and property columns as other Inspector roots", function()
    local project, level = fixture()
    assert(project:createEntry("Assets", "level", "L_Inspector", {empty = true}))
    assert(require("editor.LevelFile").save(project:resolveAssetFile("Assets/L_Inspector.level"), level))
    local app = require("editor.EditorApp").new(nil, project)
    assert(app:inspectAsset("Assets/L_Inspector.level")); app:draw()
    local inspector, cameraHeader, cameraRow = app.inspector.classInspector
    for _, row in ipairs(inspector.rows) do
        if row.label == "Camera" then cameraHeader = row end
        if row.name == "$mainCamera" then cameraRow = row end
    end
    assert(cameraHeader); assert(cameraRow)
    Assert.equal(true, cameraHeader.builtIn); Assert.equal(0, cameraRow.depth)
    local layout, Ui = require("editor.ui.PropertyLayout"), require("editor.Ui")
    local group, propertyGroup, text = layout.group, layout.propertyGroup, Ui.text
    local usedBox, labelX = false, nil
    layout.group = function(left, width, top, height, label, ...)
        if label == "Camera" then usedBox = true end
        return group(left, width, top, height, label, ...)
    end
    layout.propertyGroup = function(left, width, top, height, label, ...)
        Assert.truthy(label ~= "Camera")
        return propertyGroup(left, width, top, height, label, ...)
    end
    Ui.text = function(label, x, ...)
        if label == "Main Camera" then labelX = x end
        return text(label, x, ...)
    end
    local ok, err = pcall(app.draw, app)
    layout.group, layout.propertyGroup, Ui.text = group, propertyGroup, text
    assert(ok, err); Assert.equal(true, usedBox)
    Assert.equal(layout.cells(inspector.left, inspector.width, 0).x, labelX)
    inspector:mousepressed(inspector.left + Ui.METRICS.contentPaddingX + 1,
        inspector.propertyTop + cameraHeader.offset - inspector.scroll + 10, 1)
    Assert.equal(false, inspector.groupExpanded[cameraHeader.groupKey])
end)
add("Script property groups start collapsed preserve manual expansion and reveal hidden fields", function()
    local project = fixture()
    local app = require("editor.EditorApp").new(nil, project); app:draw()
    local inspector = app.inspector.classInspector
    local scriptId, header = project.scripts[1].id
    for _, row in ipairs(inspector.rows) do
        if row.label == "Counters" then header = row end
        Assert.truthy(row.name ~= scriptId .. ".count")
    end
    assert(header); Assert.equal(false, inspector.groupExpanded[header.groupKey])
    Assert.truthy(inspector.groupExpanded["script:" .. scriptId] ~= false)
    inspector:mousepressed(inspector.left + require("editor.Ui").METRICS.contentPaddingX + 1,
        inspector.propertyTop + header.offset - inspector.scroll + 10, 1)
    Assert.equal(true, inspector.groupExpanded[header.groupKey])
    inspector:reload(); Assert.equal(true, inspector.groupExpanded[header.groupKey])
    inspector.groupExpanded[header.groupKey] = false; inspector:rebuildRows()
    assert(inspector:ensurePropertyVisible(scriptId .. ".count"))
    Assert.equal(true, inspector.groupExpanded[header.groupKey])
    Assert.equal(false, app.scopeInspector.projectDocument:isDirty())
end)
add("Scope Inspectors edit save undo separate documents and nest property groups", function()
    local project, level = fixture(); assert(project:createEntry("Assets", "level", "L_Test", {empty = true}))
    assert(require("editor.LevelFile").save(project:resolveAssetFile("Assets/L_Test.level"), level))
    local app = require("editor.EditorApp").new(nil, project); app:draw(); Assert.equal("Project", app.inspector.classInspector.target.label)
    app:showProjectInspector(); app:draw(); local inspector = app.inspector.classInspector
    local stable = inspector.target
    app:updateInspectorTarget(); app:draw(); Assert.equal(stable, inspector.target)
    inspector.editing, inspector.text, inspector.replace = project.scripts[1].id .. ".count", "12", false
    app:updateInspectorTarget(); app:draw(); Assert.equal(project.scripts[1].id .. ".count", inspector.editing)
    inspector:cancelEdit()
    Assert.equal("Project", inspector.target.label); app:recordHistory(); assert(inspector:setProperty("manager.count", 9)); app:recordHistory()
    assert(app:undoRedo(-1)); Assert.equal(nil, project.scriptOverrides[project.scripts[1].id]); assert(app:undoRedo(1)); assert(app:saveInspectedDocument())
    Assert.equal(9, assert(require("editor.Project").open(project.rootPath)).scriptOverrides[project.scripts[1].id].count)
    assert(app:inspectAsset("Assets/L_Test.level")); app:draw(); Assert.equal("Level", app.inspector.classInspector.target.label)
    local headers, nested = 0, false
    for _, row in ipairs(inspector.rows) do
        if row.scriptId then headers = headers + 1; Assert.truthy(inspector:scriptSource(row.scriptId)) end
        if row.label == "Counters" then nested = row.depth == 0 end
    end
    Assert.equal(1, headers); Assert.equal(true, nested)
    assert(inspector:setProperty("levelManager.count", 7)); assert(app:saveInspectedDocument())
    Assert.equal(7, assert(require("editor.LevelDocument").load(project:resolveAssetFile("Assets/L_Test.level"))).level.scriptOverrides[level.scripts[1].id].count)
end)
add("Property group headers align with plain labels and indent only child names", function()
    local project = fixture()
    local sourcePath = project:resolveSourceFile("Assets/Trace.lua")
    local source = assert(Fs.read(sourcePath))
    source = source:gsub("properties = {count =", "properties = {plain = {type = 'number', default = 2}, count =", 1)
    assert(Fs.writeAtomic(sourcePath, source)); assert(project:rebuildAssetIndex())
    local app = require("editor.EditorApp").new(nil, project)
    app:showProjectInspector(); app:draw()
    local inspector, Ui = app.inspector.classInspector, require("editor.Ui")
    assert(inspector:ensurePropertyVisible(project.scripts[1].id .. ".count"))
    local layout = require("editor.ui.PropertyLayout")
    local group, propertyGroup, scriptHeader, propertyHeader = layout.group, layout.propertyGroup
    layout.group = function(left, width, top, height, value, ...)
        if value:find("manager", 1, true) then scriptHeader = true end
        return group(left, width, top, height, value, ...)
    end
    layout.propertyGroup = function(left, width, top, height, value, ...)
        if value == "Counters" then propertyHeader = true end
        return propertyGroup(left, width, top, height, value, ...)
    end
    local text, field, label, positions = Ui.text, Ui.field, nil, {}
    Ui.text = function(value, x, ...)
        label = value
        if value == "count" or value == "plain" or value == "Counters" then positions[value] = {name = x} end
        return text(value, x, ...)
    end
    Ui.field = function(value, rect, ...)
        if positions[label] then positions[label].value = rect.x end
        return field(value, rect, ...)
    end
    local ok, err = pcall(app.draw, app)
    Ui.text, Ui.field = text, field
    layout.group, layout.propertyGroup = group, propertyGroup
    assert(ok, err)
    Assert.equal(true, scriptHeader)
    Assert.equal(true, propertyHeader)
    Assert.equal(positions.plain.name, positions.Counters.name)
    Assert.equal(positions.plain.name + 14, positions.count.name)
    Assert.truthy(positions.plain.value)
    Assert.equal(positions.plain.value, positions.count.value)
    local header
    for _, row in ipairs(inspector.rows) do if row.label == "Counters" then header = row end end
    assert(header)
    inspector:mousepressed(inspector.left + Ui.METRICS.contentPaddingX + 1,
        inspector.propertyTop + header.offset - inspector.scroll + 10, 1)
    Assert.equal(false, inspector.groupExpanded[header.groupKey])
end)
add("Transform keeps its header while expanded property groups get inset bodies", function()
    local project, level = fixture()
    local sourcePath = project:resolveSourceFile("Assets/Trace.lua")
    local source = assert(Fs.read(sourcePath)):gsub("function Trace:draw%(%)[^\n]*", "function Trace:draw() end")
        :gsub("function Trace:drawScreen%(%)[^\n]*", "function Trace:drawScreen() end")
        :gsub("properties = {count =", "properties = {second = {type = 'number', default = 0, group = 'Counters'}, count =", 1)
    assert(Fs.writeAtomic(sourcePath, source)); assert(project:rebuildAssetIndex())
    local app = require("editor.EditorApp").new(require("editor.LevelDocument").new(level), project)
    app.sceneView:setSelection({level.lobjects[1]}); app.inspectorSource = "scene"; app:updateInspectorTarget()
    local inspector = app.inspector.classInspector
    assert(inspector:ensurePropertyVisible(level.lobjects[1].scripts[1].id .. ".count"))
    local layout = require("editor.ui.PropertyLayout")
    local group, propertyGroup, body = layout.group, layout.propertyGroup, layout.groupBody
    local transform, counters, bodies, childHeight = false, false, 0, nil
    layout.group = function(left, width, top, height, label, ...)
        if label == "Transform" then transform = true end
        return group(left, width, top, height, label, ...)
    end
    layout.propertyGroup = function(left, width, top, height, label, ...)
        if label == "Counters" then counters = true; childHeight = height - layout.HEADER_HEIGHT end
        Assert.truthy(label ~= "Transform")
        return propertyGroup(left, width, top, height, label, ...)
    end
    layout.groupBody = function(...) bodies = bodies + 1; return body(...) end
    local ok, err = pcall(app.draw, app)
    layout.group, layout.propertyGroup, layout.groupBody = group, propertyGroup, body
    assert(ok, err)
    Assert.equal(true, transform); Assert.equal(true, counters); Assert.truthy(bodies > 0)
    Assert.equal(2 * layout.ROW_HEIGHT, childHeight)
    local labelRect, valueRect = layout.cells(100, 400, 0)
    Assert.equal(100 + require("editor.Ui").METRICS.contentPaddingX + 26, labelRect.x)
    Assert.truthy(math.abs(labelRect.w / (labelRect.w + valueRect.w) - layout.NAME_COLUMN_RATIO) < 0.00001)
end)
add("Property column ratio changes both columns while inset bodies preserve the value edge", function()
    local layout = require("editor.ui.PropertyLayout")
    local original = layout.NAME_COLUMN_RATIO
    local ok, err = pcall(function()
        layout.NAME_COLUMN_RATIO = 0.5
        local label, value = layout.cells(100, 400, 0)
        Assert.equal(label.w, value.w)
        local body = layout.groupBodyRect(100, 400, 32, 64)
        local Ui = require("editor.Ui")
        Assert.equal(100 + Ui.METRICS.contentPaddingX + layout.GROUP_INDENT, body.x)
        Assert.equal(500 - Ui.METRICS.contentPaddingX, body.x + body.w)
        layout.NAME_COLUMN_RATIO = 0.35
        local changedLabel, changedValue = layout.cells(100, 400, 0)
        Assert.truthy(changedLabel.w < label.w); Assert.truthy(changedValue.w > value.w)
        Assert.truthy(math.abs(changedLabel.w / (changedLabel.w + changedValue.w) - 0.35) < 0.00001)
        Assert.equal(value.x + value.w, changedValue.x + changedValue.w)
    end)
    layout.NAME_COLUMN_RATIO = original
    assert(ok, err)
end)
add("Inspector resize hit testing tolerates empty selection and unlaid out targets", function()
    local project = fixture()
    local app = require("editor.EditorApp").new(nil, project)
    app:mousemoved(1200, 100, 1, 1)
    app:draw()
    app:mousemoved(1200, 100, 1, 1)
    assert(app:inspectAsset("Assets/Trace.lua"))
    app:draw()
    app:mousemoved(1200, 100, 1, 1)
    local inspector = app.inspector.classInspector
    Assert.equal(nil, inspector:resizeAt(1200, 100))
    app:showProjectInspector()
    app:mousemoved(1200, 100, 1, 1)
    app:draw()
    Assert.truthy(inspector.propertyTop)
    Assert.truthy(inspector.propertyHeight)
    inspector.treeResize = {kind = "script"}
    Assert.equal("script", inspector:resizeAt(1200, 100))
    inspector:setTarget(nil)
    Assert.equal(nil, inspector:resizeAt(1200, 100))
end)
add("Asset summaries respect the Inspector panel offset without scope tabs", function()
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
            rows = {}; inspector:draw()
            local top = inspector.y + Ui.METRICS.contentPaddingY
            Assert.equal(top + 44, rows["Summary name"])
            Assert.equal(top + 60, rows[kind])
            Assert.equal(top + 86, rows["Assets/Summary"])
            local hint = kind == "Folder" and "Double-click to browse" or "Read-only asset information"
            Assert.equal(top + 110, rows[hint])
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
