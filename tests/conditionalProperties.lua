local Assert = require("tests.Assert")
local Script = require("core.Script")
local Fs = require("editor.HostFileSystem")
local tests = {}
local function add(name, fn) tests[#tests + 1] = {name = name, fn = fn} end
add("Conditional property declarations validate dependencies and preserve inheritance", function()
    local condition = {manual = true, mode = "fixed", count = 2}
    local base = Script:extend({properties = {
        manual = {type = "boolean", default = false},
        mode = {type = "string", default = "fixed", options = {"fixed", "auto"}},
        count = {type = "number", default = 2},
        size = {type = "number", default = 10, enabledIf = condition}
    }})
    condition.manual = false
    Assert.equal(true, base.properties.size.enabledIf.manual)
    local derived = base:extend({properties = {size = {type = "number", default = 20}}})
    Assert.equal(true, derived.properties.size.enabledIf.manual)
    local unrestricted = derived:extend({properties = {size = {type = "number", default = 30, enabledIf = false}}})
    Assert.equal(false, unrestricted.properties.size.enabledIf)
    local instance = derived:new()
    instance.size = 42
    Assert.equal(42, instance.size)
    for _, invalid in ipairs({true, "manual", {}, {missing = true}, {size = 10}, {manual = 1}, {mode = "other"}}) do
        Assert.equal(false, pcall(function()
            base:extend({properties = {size = {type = "number", default = 10, enabledIf = invalid}}})
        end))
    end
end)
local function fixture()
    local project = assert(require("editor.Project").create(Fs.join(love.filesystem.getSourceBaseDirectory(), "build"),
        "AttachedTest_Conditions_" .. os.time() .. "_" .. love.math.random(100000, 999999)))
    assert(project:createEntry("Assets", "lua", "Conditional", {scriptKind = "script"}))
    assert(Fs.writeAtomic(assert(project:resolveSourceFile("Assets/Conditional.lua")), [[
return {properties = {
    manual = {type = "boolean", default = true},
    mode = {type = "string", default = "fixed", options = {"fixed", "auto"}},
    size = {type = "number", default = 10, enabledIf = {manual = true, mode = "fixed"}},
    caption = {type = "string", default = "Saved", enabledIf = {manual = true}},
    image = {type = "image", default = false, enabledIf = {manual = true}},
    choice = {type = "string", default = "a", options = {"a", "b"}, enabledIf = {manual = true}},
    inverse = {type = "boolean", default = false, enabledIf = {manual = false}}
}}
]]))
    local source = project:getAssetId("Assets/Conditional.lua")
    local app = require("editor.EditorApp").new(nil, project)
    local object = app.level:addLObject(0, 0, nil, "Conditional")
    object.scripts = {{id = "first", name = "First", source = source}, {id = "second", name = "Second", source = source}}
    app.sceneView:setSelection({object}); app.inspectorSource = "scene"; app:updateInspectorTarget(); app:draw()
    return project, app, object
end
add("Inspector conditions isolate attachments and preserve disabled overrides across reload", function()
    local _, app, object = fixture()
    local inspector = app.inspector.classInspector
    assert(inspector:setProperty("first.size", 35))
    local pendingChoice = inspector:choices("first.choice", "a")
    assert(inspector:setProperty("first.manual", false))
    Assert.equal(false, inspector:propertyEditable("first.size"))
    Assert.equal(true, inspector:propertyEditable("second.size"))
    Assert.equal(true, inspector:propertyEditable("first.inverse"))
    Assert.equal(false, inspector:setProperty("first.size", 99))
    Assert.equal(false, inspector:applyPicked("first.image", false))
    Assert.equal(nil, inspector:pickCandidate("first.image", "Assets/Conditional.lua"))
    Assert.equal(false, pendingChoice:setValue("b"))
    Assert.equal(35, object.scriptOverrides.first.size)
    inspector:reload()
    Assert.equal(false, inspector:propertyEditable("first.size"))
    assert(inspector:setProperty("first.manual", true))
    assert(inspector:setProperty("first.mode", "auto"))
    Assert.equal(false, inspector:propertyEditable("first.size"))
    assert(inspector:setProperty("first.mode", "fixed"))
    Assert.equal(true, inspector:propertyEditable("first.size"))
    Assert.equal(35, object.scriptOverrides.first.size)
end)
add("Disabled Inspector rows block reset picking dropdown and stale text edits", function()
    local _, app = fixture()
    local inspector = app.inspector.classInspector
    assert(inspector:setProperty("first.size", 35))
    local size = assert(inspector:ensurePropertyVisible("first.size"))
    inspector:mousepressed(size.x + 5, size.y + 5, 1)
    Assert.equal(true, inspector:isEditing())
    assert(inspector:setProperty("first.manual", false))
    Assert.equal(false, inspector:textinput("99"))
    Assert.equal(false, inspector:isEditing())
    local picks = 0
    inspector.onPick = function() picks = picks + 1; return true end
    assert(inspector:ensurePropertyVisible("first.image"))
    local imageRow
    for _, candidate in ipairs(inspector.rows) do if candidate.name == "first.image" then imageRow = candidate end end
    local image = inspector:imageRects(inspector.propertyTop + imageRow.offset - inspector.scroll).assign
    inspector:mousepressed(image.x + 5, image.y + 5, 1)
    Assert.equal(0, picks)
    size = assert(inspector:ensurePropertyVisible("first.size"))
    local row
    for _, candidate in ipairs(inspector.rows) do if candidate.name == "first.size" then row = candidate end end
    local reset = inspector:resetRect("first.size", inspector.propertyTop + row.offset - inspector.scroll + 3)
    inspector:mousepressed(reset.x + 5, reset.y + 5, 1)
    Assert.equal(35, inspector.target:getOverrides()["first.size"])
    local choice = assert(inspector:ensurePropertyVisible("first.choice"))
    inspector:mousepressed(choice.x + 5, choice.y + 5, 1)
    Assert.equal(nil, inspector.propertyChoice)
    app:draw()
end)
add("Project and Level Inspector conditions use current scoped values", function()
    local project, app, object = fixture()
    for _, label in ipairs({"Project", "Level"}) do
        local data = {scripts = object.scripts, scriptOverrides = {first = {manual = false, size = 24}}}
        local target = assert(require("project.ScopedScripts").inspectorTarget(project, data, app.level, label))
        local inspector = app.inspector.classInspector
        inspector:setTarget(target)
        Assert.equal(false, inspector:propertyEditable("first.size"))
        Assert.equal(true, inspector:propertyEditable("second.size"))
        assert(inspector:setProperty("first.manual", true))
        Assert.equal(true, inspector:propertyEditable("first.size"))
        Assert.equal(24, data.scriptOverrides.first.size)
    end
end)
add("Legacy Level class loading retains and validates enabledIf metadata", function()
    local project = fixture()
    assert(project:createEntry("Assets", "lua", "LegacyConditions", {scriptKind = "level"}))
    local path = assert(project:resolveSourceFile("Assets/LegacyConditions.lua"))
    assert(Fs.writeAtomic(path, [[return {properties = {
        manual = {type = "boolean", default = true},
        size = {type = "number", default = 10, enabledIf = {manual = true}}
    }}]]))
    local class = assert(require("project.LuaScript").load(project, "Assets/LegacyConditions.lua", "level"))
    Assert.equal(true, class.properties.size.enabledIf.manual)
    assert(Fs.writeAtomic(path, [[return {properties = {
        size = {type = "number", default = 10, enabledIf = {missing = true}}
    }}]]))
    local invalid, err = require("project.LuaScript").load(project, "Assets/LegacyConditions.lua", "level")
    Assert.equal(nil, invalid); assert(err:find("enabledIf", 1, true))
end)
add("CLI can prepare disabled values and derived Prefabs preserve conditional defaults", function()
    local project, app, object = fixture()
    local Cli, source = require("editor.Cli"), object.scripts[1].source
    local function run(command, fields)
        fields = fields or {}; fields.command, fields.project = command, project.rootPath
        return Cli.execute(fields)
    end
    run("project.script.add", {source = source, script = "settings"})
    run("project.script.set", {property = "settings.manual", value = false})
    run("project.script.set", {property = "settings.size", value = 67})
    Assert.equal(67, run("project.script.get").values["settings.size"])
    run("project.script.reset", {property = "settings.size"})
    Assert.equal(10, run("project.script.get").values["settings.size"])
    run("prefab.create", {name = "PF_Base"})
    run("prefab.script.add", {prefab = "Assets/PF_Base.prefab", source = source, script = "settings"})
    run("prefab.set", {prefab = "Assets/PF_Base.prefab", property = "settings.manual", value = false})
    run("prefab.set", {prefab = "Assets/PF_Base.prefab", property = "settings.size", value = 33})
    assert(project:rebuildAssetIndex())
    run("prefab.create", {name = "PF_Derived", class = project:getAssetId("Assets/PF_Base.prefab")})
    assert(project:rebuildAssetIndex()); assert(app:inspectAsset("Assets/PF_Derived.prefab")); app:updateInspectorTarget()
    local inspector = app.inspector.classInspector
    local id = inspector.preview:getScriptByName("settings").id
    Assert.equal(false, inspector:propertyEditable(id .. ".size"))
    assert(inspector:setProperty(id .. ".manual", true))
    Assert.equal(true, inspector:propertyEditable(id .. ".size"))
    Assert.equal(33, inspector.class.properties[id .. ".size"].default)
end)
add("Runtime Inspector reevaluates conditions after direct script assignment", function()
    local _, app, authored = fixture()
    assert(app:startPlay()); assert(app:setFreeExplore(true))
    app.sceneView:setSelection({app.runtimeScene.lobjects[1]}); app:updateInspectorTarget()
    local inspector = app.inspector.classInspector
    local script = app.runtimeScene.lobjects[1].runtimeObject.scripts.first
    assert(inspector:setProperty("first.size", 45))
    script.manual = false
    Assert.equal(false, inspector:propertyEditable("first.size"))
    Assert.equal(false, inspector:setProperty("first.size", 99))
    script.size = 52
    script.manual = true
    Assert.equal(true, inspector:propertyEditable("first.size"))
    Assert.equal(52, inspector.target:getOverrides()["first.size"])
    assert(app:stopPlay())
    Assert.equal(nil, authored.scriptOverrides and authored.scriptOverrides.first)
end)
return tests
