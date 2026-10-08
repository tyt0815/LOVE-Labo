local Assert = require("tests.assert")
local IME = require("editor.ui.ime")
local UI = require("editor.ui")
local Root = require("editor.ui.root")
local Canvas = require("editor.ui.canvas")
local Dialog = require("editor.ui.dialog")
local ProjectStart = require("editor.project_start")
local ClassInspector = require("editor.class_inspector")
local tests = {}
local function add(name, fn)
    tests[#tests + 1] = {name = name, fn = function()
        IME.update()
        local ok, err = pcall(fn)
        IME.update()
        if not ok then error(err, 0) end
    end}
end

add("Hangul composition displays immediately and commits each syllable once", function()
    local root = Root.new(Canvas.new())
    local dialog = Dialog.new(root, {input = true, value = "Default", onConfirm = function() return true end})
    dialog.contentFocused = true
    root:textedited("ㅎ", 0, 1)
    Assert.equal(false, dialog.contentFocused)
    Assert.equal("ㅎ", IME.display(dialog, dialog.text, dialog.replace))
    root:textedited("한", 0, 1)
    Assert.equal("Default", dialog.text)
    Assert.equal("한", IME.display(dialog, dialog.text, dialog.replace))
    root:textinput("한")
    root:textedited("글", 0, 1)
    Assert.equal("한글", IME.display(dialog, dialog.text, dialog.replace))
    root:textinput("글")
    root:textedited("", 0, 0)
    Assert.equal("한글", dialog.text)
    Assert.equal(nil, dialog.composition)
    root:dismissPopup()
end)

add("dialog click confirms final Hangul and late native input cannot leak to another field", function()
    local root, result = Root.new(Canvas.new())
    local dialog = Dialog.new(root, {input = true, value = "Old", onConfirm = function(text)
        result = text; return true
    end})
    root:textinput("한")
    root:textedited("글", 0, 1)
    root:mousepressed(dialog.confirm.x + 1, dialog.confirm.y + 1, 1)
    Assert.equal("한글", result)
    Assert.equal(nil, root.popup)
    local nextDialog = Dialog.new(root, {input = true, value = "Next", onConfirm = function() return true end})
    root:textinput("글")
    Assert.equal("Next", nextDialog.text)
    IME.update()
    root:textinput("글")
    Assert.equal("글", nextDialog.text)
    root:dismissPopup()
end)

add("IME backspace changes only the composing syllable and escape cancels", function()
    local root = Root.new(Canvas.new())
    local dialog = Dialog.new(root, {input = true, onConfirm = function() error("unexpected submit") end})
    root:textinput("한")
    root:textedited("글", 0, 1)
    root:keypressed("backspace")
    Assert.equal("한", dialog.text)
    root:textedited("그", 0, 1)
    Assert.equal("한그", IME.display(dialog, dialog.text, dialog.replace))
    root:textedited("", 0, 0)
    root:keypressed("backspace")
    Assert.equal("", dialog.text)
    root:textedited("글", 0, 1)
    root:keypressed("escape")
    Assert.equal(nil, root.popup)
    Assert.equal(nil, dialog.composition)
end)

add("project start preserves composition on Tab and ignores late input in destination field", function()
    local start = ProjectStart.new(function() return true end)
    start:textinput("한")
    start:textedited("글")
    start:keypressed("backspace")
    Assert.equal("한", start.name)
    start:keypressed("tab")
    Assert.equal("한글", start.name)
    Assert.equal("path", start.activeField)
    local path = start.path
    start:textinput("글")
    Assert.equal(path, start.path)
    start:textinput("C:\\한")
    start:textedited("글")
    start:keypressed("tab")
    Assert.equal("C:/한글", start.path)
end)

add("project start click commits composition and places caret without replacing text", function()
    local start = ProjectStart.new(function() return true end)
    local layout = start:layout()
    start:textinput("한")
    start:textedited("글")
    start:mousepressed(layout.name.x + 1, layout.name.y + 1, 1)
    Assert.equal(nil, start.composition)
    Assert.equal("한글", start.name)
    Assert.equal(false, start.replace)
    start:mousepressed(layout.path.x + 1, layout.path.y + 1, 1)
    Assert.equal("한글", start.name)
    Assert.equal("path", start.activeField)
end)

add("class choice arrows finish Hangul composition before changing selection", function()
    local root = Root.new(Canvas.new())
    local dialog = Dialog.new(root, {input = true,
        choices = {{label = "First", value = "first"}, {label = "Second", value = "second"}},
        onConfirm = function() return true end})
    root:textinput("한")
    for _, key in ipairs({"down", "up"}) do
        root:textedited("글", 0, 1)
        local expected = dialog.text .. "글"
        root:keypressed(key)
        Assert.equal(key == "down" and 2 or 1, dialog.selected)
        Assert.equal(expected, dialog.text)
        Assert.equal(nil, dialog.composition)
        root:textinput("글")
        Assert.equal(expected, dialog.text)
    end
    root:dismissPopup()
end)

add("focused folder tree arrows finish Hangul composition before navigating", function()
    local FolderTree = require("editor.ui.folder_tree")
    local project = {listDirectory = function(_, reference)
        if reference ~= "Assets" then return {} end
        return {{type = "directory", reference = "Assets/First"},
            {type = "directory", reference = "Assets/Second"}}
    end}
    local tree = FolderTree.new(project, "Assets", nil, "Assets/First")
    local root = Root.new(Canvas.new())
    local dialog = Dialog.new(root, {input = true, content = tree, onConfirm = function() return true end})
    root:textinput("한")
    for _, key in ipairs({"down", "up"}) do
        root:textedited("글", 0, 1)
        -- 트리 포커스 상태에서도 남아 있는 조합이 탐색 키를 가로채지 않아야 한다.
        dialog.contentFocused = true
        local expected = dialog.text .. "글"
        root:keypressed(key)
        Assert.equal(key == "down" and "Assets/Second" or "Assets/First", tree.selected)
        Assert.equal(expected, dialog.text)
        Assert.equal(nil, dialog.composition)
        root:textinput("글")
        Assert.equal(expected, dialog.text)
    end
    root:dismissPopup()
end)

local function inspector()
    local value
    local owner = ClassInspector.new(nil, nil)
    owner.class = {properties = {name = {type = "string", default = "Old"}}}
    owner.target = {getOverrides = function() return {} end,
        setOverrides = function(_, values) value = values.name end}
    owner.editing, owner.text, owner.replace = "name", "Old", true
    return owner, function() return value end
end

add("class properties keep final Hangul on Enter and blur and cancel on Escape", function()
    for _, mode in ipairs({"enter", "blur", "escape"}) do
        local owner, value = inspector()
        owner:textinput("한")
        owner:textedited("글")
        owner:keypressed("backspace")
        Assert.equal("한", owner.text)
        if mode == "blur" then owner:commitEdit()
        else owner:keypressed(mode == "enter" and "return" or "escape") end
        Assert.equal(mode ~= "escape" and "한글" or nil, value())
        Assert.equal(nil, owner.composition)
        IME.update()
    end
end)

add("editor routes composition through popup and focused inspector", function()
    local EditorApp = require("editor.app")
    local Widget = require("editor.ui.widget")
    local owner = inspector()
    local app = setmetatable({uiRoot = Root.new(Canvas.new()), inspector = owner}, EditorApp)
    app.inspectorWidget = Widget.new({textedited = function(_, text) return owner:textedited(text) end})
    app:textedited("한", 0, 1)
    Assert.equal("한", owner.composition)
    local dialog = Dialog.new(app.uiRoot, {input = true, onConfirm = function() return true end})
    app:textedited("글", 0, 1)
    Assert.equal("글", dialog.composition)
    Assert.equal("한", owner.composition)
    app.uiRoot:dismissPopup()
    owner:cancelEdit()
end)

add("project start renders preedit instead of lagging committed text", function()
    local start = ProjectStart.new(function() return true end)
    start:textedited("한")
    local original, shown = UI.field
    UI.field = function(text, _, focused, composition)
        if focused then shown = {text, composition} end
    end
    local ok, err = pcall(start.draw, start)
    UI.field = original
    if not ok then error(err, 0) end
    Assert.equal("한", shown[1])
    Assert.equal("한", shown[2])
    start:keypressed("escape")
    Assert.truthy(love.textedited)
end)

return tests
