local Verification = {}

local POINTER_PROBE = [[
    local channelName, x, y, dx, dy, handle = ...
    require("love.timer")
    local ffi = require("ffi")
    ffi.cdef[=[
        typedef struct {long dx; long dy; unsigned int data; unsigned int flags; unsigned int time; uintptr_t extra;} LaboMouseInput;
        typedef struct {unsigned int type; union {LaboMouseInput mouse;} input;} LaboInput;
        unsigned int __stdcall SendInput(unsigned int count, LaboInput *inputs, int size);
        int __stdcall SetCursorPos(int x, int y);
        int __stdcall PostMessageW(void *window, unsigned int message, uintptr_t wparam, intptr_t lparam);
    ]=]
    local user, channel = ffi.load("user32"), love.thread.getChannel(channelName)
    local function button(flags)
        local input = ffi.new("LaboInput[1]")
        input[0].input.mouse.flags = flags
        assert(user.SendInput(1, input, ffi.sizeof(input[0])) == 1, "Resize pointer injection failed")
    end
    local ok, err = pcall(function()
        assert(user.SetCursorPos(x, y) ~= 0)
        channel:push("positioned")
        love.timer.sleep(0.15)
        button(2)
        channel:push("pressed")
        love.timer.sleep(0.2)
        user.SetCursorPos(x + dx / 2, y + dy / 2)
        love.timer.sleep(0.1)
        user.SetCursorPos(x + dx, y + dy)
        love.timer.sleep(0.1)
    end)
    pcall(button, 4)
    -- 네이티브 이동 루프가 실패한 경우에도 종료시켜 검증 프로세스가 멈추지 않게 한다.
    user.PostMessageW(ffi.cast("void *", handle), 0x001F, 0, 0)
    channel:push(ok and "released" or tostring(err))
]]

local function verifyResizeDrag(frame, report, check)
    local ffi, user = require("ffi"), frame.user
    ffi.cdef[[
        typedef struct {long dx; long dy; unsigned int data; unsigned int flags; unsigned int time; uintptr_t extra;} LaboMouseInput;
        typedef struct {unsigned int type; union {LaboMouseInput mouse;} input;} LaboInput;
        unsigned int __stdcall SendInput(unsigned int count, LaboInput *inputs, int size);
        int __stdcall GetCursorPos(LaboWindowPoint *point);
        int __stdcall SetCursorPos(int x, int y);
        int __stdcall SetForegroundWindow(void *window);
    ]]
    local cursor, position = ffi.new("LaboWindowPoint"), ffi.new("int[2]")
    assert(user.GetCursorPos(cursor) ~= 0)
    frame.native.SDL_GetWindowPosition(frame.window, position, position + 1)
    local width, height = love.graphics.getDimensions()
    user.SetForegroundWindow(frame.handle)
    love.graphics.present()
    love.event.pump()
    local function button(flags)
        local input = ffi.new("LaboInput[1]")
        input[0].type, input[0].input.mouse.flags = 0, flags
        assert(user.SendInput(1, input, ffi.sizeof(input[0])) == 1, "Could not inject resize pointer")
    end
    report.resizeDrags = {}
    local ok, err = pcall(function()
        check("native sizing style", require("bit").band(user.GetWindowLongW(frame.handle, -16), 0x00040000) ~= 0)
        for _, corner in ipairs({{name = "top left", x = -24, y = -20, hit = 13},
            {name = "top right", x = 24, y = -20, hit = 14},
            {name = "bottom left", x = -24, y = 20, hit = 16},
            {name = "bottom right", x = 24, y = 20, hit = 17}}) do
            local before, after = ffi.new("LaboNativeRect"), ffi.new("LaboNativeRect")
            assert(user.GetWindowRect(frame.handle, before) ~= 0)
            local x = corner.x < 0 and before.left + 5 or before.right - 5
            local y = corner.y < 0 and before.top + 5 or before.bottom - 5
            local packed = require("bit").bor(require("bit").band(x, 65535), require("bit").lshift(require("bit").band(y, 65535), 16))
            check(corner.name .. ": native corner hit", user.SendMessageW(frame.handle, 0x0084, 0, packed) == corner.hit)
            -- Windows 크기 조절 루프가 주 스레드를 점유하므로 별도 스레드가 포인터를 이동·해제한다.
            local channelName = "resize-" .. require("project.AssetId").new()
            local channel = love.thread.getChannel(channelName)
            local worker = love.thread.newThread(love.filesystem.newFileData(POINTER_PROBE, "WindowResizePointer.lua"))
            worker:start(channelName, x, y, corner.x, corner.y, tonumber(ffi.cast("intptr_t", frame.handle)))
            assert(channel:demand(3) == "positioned", worker:getError() or "Resize pointer positioning failed")
            repeat love.event.pump(); love.timer.sleep(0.01) until not worker:isRunning()
            worker:wait()
            button(4)
            check(corner.name .. ": resize pointer released", channel:pop() == "pressed" and channel:pop() == "released" and not worker:getError())
            love.event.pump()
            assert(user.GetWindowRect(frame.handle, after) ~= 0)
            local deltaWidth = tonumber(after.right - after.left - (before.right - before.left))
            local deltaHeight = tonumber(after.bottom - after.top - (before.bottom - before.top))
            report.resizeDrags[#report.resizeDrags + 1] = {corner = corner.name, widthChange = deltaWidth, heightChange = deltaHeight}
            check(corner.name .. ": pointer drag resizes native window", deltaWidth == 24 and deltaHeight == 20)
        end
    end)
    -- 검증이 실패해도 포인터와 테스트 창의 원래 위치·크기를 복원한다.
    button(4)
    frame.native.SDL_SetWindowPosition(frame.window, position[0], position[1])
    frame.native.SDL_SetWindowSize(frame.window, width, height)
    user.SetCursorPos(cursor.x, cursor.y)
    love.event.pump()
    assert(ok, err)
end

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
        ffi.cdef[[
            intptr_t __stdcall SendMessageW(void *hwnd, unsigned int message, uintptr_t wparam, intptr_t lparam);
            int __stdcall GetWindowRect(void *hwnd, LaboNativeRect *rect);
            int __stdcall GetClientRect(void *hwnd, LaboNativeRect *rect);
        ]]
        local user = Frame.user
        report.maximizeTransitions = {}
        local function checkNativeMaximize(name)
            local outer, client, monitor = ffi.new("LaboNativeRect"), ffi.new("LaboNativeRect"), ffi.new("LaboMonitorInfo")
            monitor.size = ffi.sizeof(monitor)
            assert(user.GetMonitorInfoW(user.MonitorFromWindow(Frame.handle, 2), monitor) ~= 0)
            assert(user.GetWindowRect(Frame.handle, outer) ~= 0 and user.GetClientRect(Frame.handle, client) ~= 0)
            local bounds = {left = tonumber(outer.left), top = tonumber(outer.top), right = tonumber(outer.right), bottom = tonumber(outer.bottom)}
            report.maximizeTransitions[#report.maximizeTransitions + 1] = {name = name, bounds = bounds,
                workArea = {left = tonumber(monitor.work.left), top = tonumber(monitor.work.top), right = tonumber(monitor.work.right), bottom = tonumber(monitor.work.bottom)}}
            check(name .. ": native bounds match work area", outer.left == monitor.work.left and outer.top == monitor.work.top
                and outer.right == monitor.work.right and outer.bottom == monitor.work.bottom)
            check(name .. ": client fills native window", client.right == outer.right - outer.left and client.bottom == outer.bottom - outer.top)
            return bounds
        end
        for _, active in ipairs({0, 1, 0, 1}) do
            user.SendMessageW(Frame.handle, 0x0086, active, 0)
            user.SendMessageW(Frame.handle, 0x0085, 1, 0)
            user.SendMessageW(Frame.handle, 0x00AE, 0, 0)
            local outer, client = ffi.new("LaboNativeRect"), ffi.new("LaboNativeRect")
            assert(user.GetWindowRect(Frame.handle, outer) ~= 0 and user.GetClientRect(Frame.handle, client) ~= 0)
            check("activation keeps full borderless client: " .. active,
                outer.right - outer.left == client.right and outer.bottom - outer.top == client.bottom)
        end
        local app = require("editor.EditorApp").new()
        app:draw()
        check("borderless native window", require("bit").band(Frame.native.SDL_GetWindowFlags(Frame.window), 16) ~= 0)
        local point = require("ffi").new("LaboWindowPoint", {400, 16})
        check("native draggable header callback", Frame.callback(Frame.window, point, nil) == 1)
        point.x, point.y = 1, 200
        check("native resize callback", Frame.callback(Frame.window, point, nil) == 9)
        point.x, point.y = 975, 16
        check("window buttons excluded from drag", Frame.callback(Frame.window, point, nil) == 0)
        verifyResizeDrag(Frame, report, check)
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
        report.maximizedNativeBounds = checkNativeMaximize("maximize button")
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
        local originalPosition = ffi.new("int[2]")
        Frame.native.SDL_GetWindowPosition(Frame.window, originalPosition, originalPosition + 1)
        report.displays = Frame.native.SDL_GetNumVideoDisplays()
        -- 연결된 각 모니터에서 최대화·최소화 복원·재최대화의 실제 외곽을 확인한다.
        for display = 0, report.displays - 1 do
            assert(Frame.native.SDL_GetDisplayUsableBounds(display, usable) == 0)
            Frame.native.SDL_SetWindowPosition(Frame.window, usable.x + 16, usable.y + 16)
            love.event.pump()
            for cycle = 1, 2 do
                love.window.maximize(); love.event.pump()
                check("display " .. display .. " maximize state " .. cycle, love.window.isMaximized())
                checkNativeMaximize("display " .. display .. " maximize " .. cycle)
                love.window.minimize(); love.window.restore(); love.event.pump()
                check("display " .. display .. " restores maximized state " .. cycle, love.window.isMaximized())
                checkNativeMaximize("display " .. display .. " minimized restore " .. cycle)
                love.window.restore(); love.event.pump()
                local restoredWidth, restoredHeight = love.graphics.getDimensions()
                check("display " .. display .. " restores normal dimensions " .. cycle, not love.window.isMaximized()
                    and restoredWidth == w and restoredHeight == h)
            end
        end
        Frame.native.SDL_SetWindowPosition(Frame.window, originalPosition[0], originalPosition[1])
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
