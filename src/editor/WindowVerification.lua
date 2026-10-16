local Verification = {}

function Verification.run(args)
    local Fs, Json = require("editor.HostFileSystem"), require("project.Json")
    local directory
    for index, value in ipairs(args) do if value == "--verify-window" then directory = args[index + 1] end end
    local report = {ok = false, checks = {}}
    local function check(name, condition) assert(condition, name); report.checks[#report.checks + 1] = name end
    local ownsDirectory = false
    local ok, err = xpcall(function()
        assert(directory and not Fs.info(directory), "--verify-window requires a new output directory")
        assert(Fs.mkdir(directory)); ownsDirectory = true
        assert(love.window.setMode(1000, 680, {resizable = true, minwidth = 800, minheight = 540}))
        local Frame = require("editor.WindowFrame")
        assert(Frame.install())
        local ffi = require("ffi")
        report.roundedCornersSupported = Frame.roundedCorners
        local function checkCorners(name)
            if not Frame.roundedCorners then return end
            local preference = ffi.new("unsigned int[1]")
            local result = ffi.load("dwmapi").DwmGetWindowAttribute(Frame.handle, 33, preference, ffi.sizeof(preference))
            check(name, result == 0 and preference[0] == 2)
        end
        checkCorners("native rounded corner preference")
        local app = require("editor.EditorApp").new()
        app:draw()
        check("borderless native window", require("bit").band(Frame.native.SDL_GetWindowFlags(Frame.window), 16) ~= 0)
        local point = require("ffi").new("LaboWindowPoint", {400, 16})
        check("native draggable header callback", Frame.callback(Frame.window, point, nil) == 1)
        point.x, point.y = 1, 200
        check("native resize callback", Frame.callback(Frame.window, point, nil) == 9)
        point.x, point.y = 975, 16
        check("window buttons excluded from drag", Frame.callback(Frame.window, point, nil) == 0)
        local controls = app.menuBar.windowControls
        local popup = require("editor.ui.Dialog").new(app.uiRoot, {title = "Window control verification", onConfirm = function() return true end})
        local function press(index)
            local button = controls:buttons(love.graphics.getWidth())[index]
            assert(app:mousepressed(button.x + 20, 16, 1))
            check("window control keeps dialog open: " .. button.name, app.uiRoot.popup == popup)
        end
        local w, h = love.graphics.getDimensions()
        press(2); love.event.pump(); check("maximize button", love.window.isMaximized())
        local usable, position, size = ffi.new("LaboWindowRect"), ffi.new("int[2]"), ffi.new("int[2]")
        assert(Frame.native.SDL_GetDisplayUsableBounds(Frame.native.SDL_GetWindowDisplayIndex(Frame.window), usable) == 0)
        Frame.native.SDL_GetWindowPosition(Frame.window, position, position + 1)
        Frame.native.SDL_GetWindowSize(Frame.window, size, size + 1)
        report.maximizedBounds = {x = tonumber(position[0]), y = tonumber(position[1]), width = tonumber(size[0]), height = tonumber(size[1])}
        report.workArea = {x = tonumber(usable.x), y = tonumber(usable.y), width = tonumber(usable.w), height = tonumber(usable.h)}
        check("maximize preserves taskbar work area", position[0] >= usable.x and position[1] >= usable.y
            and position[0] + size[0] <= usable.x + usable.w and position[1] + size[1] <= usable.y + usable.h)
        press(2); check("restore button", not love.window.isMaximized())
        checkCorners("rounded corner preference survives maximize and restore")
        local restoredW, restoredH = love.graphics.getDimensions()
        check("restored dimensions", w == restoredW and h == restoredH)
        press(1); check("minimize button", require("bit").band(Frame.native.SDL_GetWindowFlags(Frame.window), 64) ~= 0)
        love.window.restore()
        check("restore minimized window", require("bit").band(Frame.native.SDL_GetWindowFlags(Frame.window), 64) == 0)
        app.uiRoot:dismissPopup()
        Frame.native.SDL_SetWindowSize(Frame.window, 1100, 720)
        love.event.pump()
        Frame.native.SDL_GetWindowSize(Frame.window, size, size + 1)
        check("native resize", size[0] == 1100 and size[1] == 720)
        local captureWidth, captureHeight = love.graphics.getDimensions()
        check("capture uses resized render dimensions", captureWidth == 1100 and captureHeight == 720)
        local canvas = love.graphics.newCanvas(captureWidth, captureHeight)
        love.graphics.push("all"); love.graphics.setCanvas(canvas); app:draw(); love.graphics.setCanvas(); love.graphics.pop()
        local pixels = canvas:newImageData(); local png = pixels:encode("png")
        assert(Fs.writeAtomic(Fs.join(directory, "editor.png"), png:getString()))
        local saved = love.image.newImageData(love.filesystem.newFileData(assert(Fs.read(Fs.join(directory, "editor.png"))), "editor.png"))
        check("saved PNG matches resized window", saved:getWidth() == captureWidth and saved:getHeight() == captureHeight)
        saved:release()
        png:release(); pixels:release(); canvas:release()
        report.ok = true
    end, debug.traceback)
    if not ok then report.error = tostring(err); print(err) end
    if ownsDirectory then assert(Fs.writeAtomic(Fs.join(directory, "report.json"), assert(Json.encode(report, true)))) end
    print(string.format("Window verification: %d checks, %s", #report.checks, report.ok and "passed" or "failed"))
    love.event.quit(report.ok and 0 or 1)
end

return Verification
