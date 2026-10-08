local Assert = require("tests.assert")
local Edit = require("editor.ui.text_edit")
local IME = require("editor.ui.ime")
local UI = require("editor.ui")
local tests = {}
local modifiers = {}
local function add(name, fn)
    tests[#tests + 1] = {name = name, fn = function()
        local original = love.keyboard.isDown
        love.keyboard.isDown = function(...)
            for _, key in ipairs({...}) do if modifiers[key] then return true end end
            return false
        end
        modifiers = {}; IME.update()
        local ok, err = pcall(fn)
        love.keyboard.isDown = original; modifiers = {}; IME.update()
        if not ok then error(err, 0) end
    end}
end
local function key(owner, text, name, ctrl, shift)
    modifiers = {lctrl = ctrl, lshift = shift}
    local value = UI.editKey(text, name, false, owner)
    modifiers = {}
    return value
end

add("UTF8 caret inserts and deletes in the middle without splitting Hangul", function()
    local owner, text = {}, "A한글BC"
    Edit.begin(owner, text, false)
    text = key(owner, text, "left"); text = key(owner, text, "left")
    text = IME.input(owner, text, "!", false); Assert.equal("A한글!BC", text)
    text = key(owner, text, "backspace"); Assert.equal("A한글BC", text)
    text = key(owner, text, "delete"); Assert.equal("A한글C", text)
    text = key(owner, text, "left"); text = key(owner, text, "backspace")
    Assert.equal("A글C", text)
end)

add("Shift selection replaces only its range and clipboard uses selected text", function()
    local owner, text, clipboard = {}, "abcDEF", ""
    local originalGet, originalSet = love.system.getClipboardText, love.system.setClipboardText
    love.system.getClipboardText = function() return clipboard end
    love.system.setClipboardText = function(value) clipboard = value end
    local ok, err = pcall(function()
        Edit.begin(owner, text, false)
        text = key(owner, text, "home")
        for _ = 1, 3 do text = key(owner, text, "right", false, true) end
        text = key(owner, text, "c", true); Assert.equal("abc", clipboard)
        text = key(owner, text, "left")
        Assert.equal(0, owner.editState.cursor); Assert.equal(0, owner.editState.anchor)
        for _ = 1, 3 do text = key(owner, text, "right", false, true) end
        text = key(owner, text, "right")
        Assert.equal(3, owner.editState.cursor); Assert.equal(3, owner.editState.anchor)
        text = key(owner, text, "home", false, true)
        text = IME.input(owner, text, "한", false); Assert.equal("한DEF", text)
        text = key(owner, text, "end"); text = key(owner, text, "left", false, true)
        text = key(owner, text, "x", true); Assert.equal("F", clipboard); Assert.equal("한DE", text)
        clipboard = "글\r\n!"; text = key(owner, text, "v", true); Assert.equal("한DE글!", text)
        text = key(owner, text, "a", true); text = key(owner, text, "delete"); Assert.equal("", text)
    end)
    love.system.getClipboardText, love.system.setClipboardText = originalGet, originalSet
    if not ok then error(err, 0) end
end)

add("Mouse click and drag select a UTF8 substring inside a dialog", function()
    local root = require("editor.ui.root").new(require("editor.ui.canvas").new())
    local dialog = require("editor.ui.dialog").new(root, {input = true, value = "한글abcd", onConfirm = function() return true end})
    IME.display(dialog, dialog.text, dialog.replace)
    local font, rect = love.graphics.getFont(), dialog.field
    local x = rect.x + 8 + font:getWidth("한글")
    root:mousepressed(x, rect.y + 10, 1)
    local tx = rect.x + 8 + font:getWidth("한글ab")
    root:mousemoved(tx, rect.y + 10, tx - x, 0)
    root:mousemoved(x, rect.y + 10, x - tx, 0)
    local first, last = Edit.range(dialog.editState)
    Assert.equal(2, first); Assert.equal(2, last)
    root:mousemoved(tx, rect.y + 10, tx - x, 0)
    root:mousereleased(tx, rect.y + 10, 1)
    first, last = Edit.range(dialog.editState)
    Assert.equal(2, first); Assert.equal(4, last)
    root:textinput("XY"); Assert.equal("한글XYcd", dialog.text)
    root:keypressed("home"); root:textinput("!"); Assert.equal("!한글XYcd", dialog.text)
    root:dismissPopup()
end)

add("IME composition replaces the selection at the caret and keeps its suffix", function()
    local owner, text = {}, "AB한글CD"
    Edit.begin(owner, text, false); owner.editState.anchor, owner.editState.cursor = 2, 4
    IME.edited(owner, "가"); Assert.equal("AB가CD", IME.display(owner, text, false))
    Assert.equal("AB한글CD", text)
    text = IME.input(owner, text, "가", false); Assert.equal("AB가CD", text)
    IME.edited(owner, "나"); Assert.equal("AB가나CD", IME.display(owner, text, false))
    text = IME.finish(owner, text, false); Assert.equal("AB가나CD", text)
    text = IME.input(owner, text, "나", false); Assert.equal("AB가나CD", text)
    IME.update(); text = IME.input(owner, text, "!", false); Assert.equal("AB가나!CD", text)
end)

add("Numeric Inspector and snap fields share caret editing and mouse capture", function()
    local app = require("editor.app").new()
    local object = app.level:addLObject(120, 0)
    app.sceneView.selectedLObject = object
    local rect = app.inspector:fieldRect("x", love.graphics.getWidth())
    app:mousepressed(rect.x + 2, rect.y + 4, 1)
    Assert.equal(app.inspectorWidget, app.uiRoot.captured)
    app:mousereleased(rect.x + 2, rect.y + 4, 1)
    app:keypressed("home"); app:textinput("3"); app:keypressed("return")
    Assert.equal(3120, object.transform.x)
    local controls = app.viewportControls
    assert(app.sceneView:setSnap("translate", false, 100))
    local _, field = controls:rects()
    app:mousepressed(field.x + 2, field.y + 4, 1); app:mousereleased(field.x + 2, field.y + 4, 1)
    app:keypressed("home"); app:keypressed("right"); app:textinput("2"); app:keypressed("return")
    Assert.equal(1200, app.sceneView.snapSettings.translate.unit)
    app:keypressed("e"); app:keypressed("space"); Assert.equal("rotate", app.sceneView.gizmoMode)
    app:keypressed("r"); app:keypressed("space"); Assert.equal("scale", app.sceneView.gizmoMode)
end)

add("Text highlight and caret use theme colors and scroll follows the caret", function()
    local owner, text = {}, "ab한글01234567890123456789"
    Edit.begin(owner, text, false)
    local rect = {x = 10, y = 10, w = 90, h = 28}
    IME.display(owner, text, false); Edit.geometry(owner, text, rect)
    Assert.truthy(owner.editState.scroll > 0)
    text = key(owner, text, "home"); IME.display(owner, text, false); Edit.geometry(owner, text, rect)
    Assert.equal(0, owner.editState.scroll)
    text = key(owner, text, "right", false, true); text = key(owner, text, "right", false, true)
    local canvas = love.graphics.newCanvas(120, 50)
    love.graphics.push("all"); love.graphics.setCanvas(canvas); love.graphics.clear(0, 0, 0, 0)
    UI.field(IME.display(owner, text, false), rect, true, nil, owner)
    love.graphics.setCanvas(); love.graphics.pop()
    local pixels = canvas:newImageData()
    if os.getenv("LOVE_LABO_GIZMO_PREVIEW") then pixels:encode("png", "text-selection-preview.png") end
    local r, g, b = pixels:getPixel(20, 14)
    local color = require("editor.theme").color("textSelection")
    Assert.truthy(math.abs(r - (color[1] * color[4] + 1 - color[4])) < 0.01)
    Assert.truthy(math.abs(g - (color[2] * color[4] + 1 - color[4])) < 0.01)
    Assert.truthy(math.abs(b - (color[3] * color[4] + 1 - color[4])) < 0.01)
    pixels:release()
    if os.getenv("LOVE_LABO_GIZMO_PREVIEW") then
        text = key(owner, text, "right")
        love.graphics.push("all"); love.graphics.setCanvas(canvas); love.graphics.clear(0, 0, 0, 0)
        UI.field(IME.display(owner, text, false), rect, true, nil, owner)
        love.graphics.setCanvas(); love.graphics.pop()
        pixels = canvas:newImageData(); pixels:encode("png", "text-caret-preview.png"); pixels:release()
    end
    canvas:release()
end)
add("Numeric drag updates live with precision cancels and preserves active text selection", function()
    local app = require("editor.app").new()
    local object = app.level:addLObject(20, 0)
    app.sceneView.selectedLObject = object
    local rect = app.inspector:fieldRect("x", love.graphics.getWidth())
    local x, y = rect.x + 5, rect.y + 5
    app:mousepressed(x, y, 1)
    app:mousemoved(x + 2, y, 2, 0); Assert.equal(20, object.transform.x)
    app:mousemoved(x + 12, y, 10, 0); Assert.equal(32, object.transform.x)
    modifiers = {lshift = true}; app:keypressed("lshift")
    app:mousemoved(x + 22, y, 10, 0); Assert.equal(33, object.transform.x)
    modifiers = {}
    app:keypressed("escape"); Assert.equal(20, object.transform.x)
    app:mousereleased(x + 22, y, 1)
    app:mousepressed(x, y, 1); app:mousemoved(x - 7, y, -7, 0)
    app:mousereleased(x - 7, y, 1); Assert.equal(13, object.transform.x)
    Assert.equal(false, app.inspector:isEditing())
    app:mousepressed(x, y, 1); app:mousereleased(x, y, 1)
    app:mousepressed(x, y, 1); app:mousemoved(x + 35, y, 35, 0); app:mousereleased(x + 35, y, 1)
    Assert.equal(13, object.transform.x)
    local first, last = Edit.range(app.inspector.editState)
    Assert.truthy(first < last)
    app.inspector:cancelEdit()
    object.transform.rotation = 350
    rect = app.inspector:fieldRect("rotation", love.graphics.getWidth()); x, y = rect.x + 5, rect.y + 5
    app:mousepressed(x, y, 1); app:mousemoved(x + 20, y, 20, 0)
    Assert.equal(10, object.transform.rotation)
    app:keypressed("escape"); Assert.equal(350, object.transform.rotation)
    app:mousereleased(x + 20, y, 1)
    rect = app.inspector:fieldRect("scaleX", love.graphics.getWidth()); x, y = rect.x + 5, rect.y + 5
    app:mousepressed(x, y, 1); app:mousemoved(x - 500, y, -500, 0)
    Assert.equal(0.01, object.transform.scaleX)
    app.uiRoot:setPopup(require("editor.ui.widget").new())
    Assert.equal(1, object.transform.scaleX); Assert.equal(false, app.inspector:isEditing())
    app.uiRoot:dismissPopup()
end)

add("Snap drag previews values saves only on release and reverts on Escape", function()
    local saved = {}
    local app = require("editor.app").new(nil, nil, {saveSnapSettings = function(settings)
        saved[#saved + 1] = require("editor.snap_settings").copy(settings); return true
    end})
    local _, rect = app.viewportControls:rects("scale")
    local x, y = rect.x + 5, rect.y + 5
    app:mousepressed(x, y, 1); app:mousemoved(x + 10, y, 10, 0)
    Assert.truthy(math.abs(app.sceneView.snapSettings.scale.unit - 0.2) < 1e-8)
    Assert.equal(0, #saved)
    app:mousereleased(x + 10, y, 1)
    Assert.equal(1, #saved); Assert.truthy(math.abs(saved[1].scale.unit - 0.2) < 1e-8)
    app:mousepressed(x, y, 1); app:mousemoved(x + 20, y, 20, 0)
    app:keypressed("escape"); app:mousereleased(x + 20, y, 1)
    Assert.truthy(math.abs(app.sceneView.snapSettings.scale.unit - 0.2) < 1e-8)
    Assert.equal(1, #saved)
end)
add("Numeric dragging uses relative motion hides the caret and restores mouse on focus loss", function()
    local app = require("editor.app").new()
    local object = app.level:addLObject(20, 0)
    app.sceneView.selectedLObject = object
    local relative, visible, grabbed = love.mouse.getRelativeMode(), love.mouse.isVisible(), love.mouse.isGrabbed()
    local rect = app.inspector:fieldRect("x", love.graphics.getWidth())
    local x, y = rect.x + 5, rect.y + 5
    app:mousepressed(x, y, 1); app:mousemoved(x + 10, y, 10, 0)
    Assert.equal(true, love.mouse.getRelativeMode()); Assert.equal(false, love.mouse.isVisible())
    -- 상대 모드에서는 절대 좌표가 고정되어 있어도 dx 이벤트로 계속 조절한다.
    app:mousemoved(x + 10, y, 25, 0); Assert.equal(55, object.transform.x)
    app:mousemoved(x + 10, y, -40, 0); Assert.equal(15, object.transform.x)
    local original, lines = love.graphics.line, 0
    love.graphics.line = function(...) lines = lines + 1; return original(...) end
    local ok, err = pcall(UI.field, IME.display(app.inspector, app.inspector.editText, false), rect, true, nil, app.inspector)
    love.graphics.line = original
    if not ok then error(err, 0) end
    Assert.equal(0, lines)
    app:focus(false)
    Assert.equal(20, object.transform.x); Assert.equal(false, app.inspector:isEditing())
    Assert.equal(relative, love.mouse.getRelativeMode()); Assert.equal(visible, love.mouse.isVisible()); Assert.equal(grabbed, love.mouse.isGrabbed())
    Assert.equal(nil, app.uiRoot.captured)
    app:mousepressed(x, y, 1); app:mousemoved(x + 10, y, 10, 0); app:mousereleased(x + 10, y, 1)
    Assert.equal(30, object.transform.x)
    Assert.equal(relative, love.mouse.getRelativeMode()); Assert.equal(visible, love.mouse.isVisible())
end)
return tests
