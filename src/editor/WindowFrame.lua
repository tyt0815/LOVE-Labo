local Frame = {active = false, height = 32, controlsWidth = 138, dragLeft = 216, blocked = false}

-- SDL_HitTestResult 값이다. 판별 과정에서 UI나 운영체제 상태를 변경하지 않는다.
function Frame.hitTest(x, y, width, height, maximized, blocked, dragLeft)
    if not maximized then
        local left, right, top, bottom = x < 6, x >= width - 6, y < 6, y >= height - 6
        if top and left then return 2 elseif top and right then return 4
        elseif bottom and right then return 6 elseif bottom and left then return 8
        elseif top then return 3 elseif right then return 5
        elseif bottom then return 7 elseif left then return 9 end
    end
    if not blocked and y >= 0 and y < Frame.height and x >= dragLeft and x < width - Frame.controlsWidth then return 1 end
    return 0
end

function Frame.install()
    if Frame.active then return true end
    if love.system.getOS() ~= "Windows" then return false, "Custom editor frame requires Windows" end
    local ok, err = pcall(function()
        local ffi = require("ffi")
        ffi.cdef[[
            typedef struct {int x; int y;} LaboWindowPoint;
            typedef struct {int x; int y; int w; int h;} LaboWindowRect;
            typedef struct {
                unsigned char version[3]; int subsystem;
                union {struct {void *window; void *hdc; void *instance;} win; unsigned char reserved[64];} info;
            } LaboWindowInfo;
            void *SDL_GL_GetCurrentWindow(void);
            void SDL_GetWindowSize(void *window, int *w, int *h);
            void SDL_SetWindowSize(void *window, int w, int h);
            void SDL_GetWindowPosition(void *window, int *x, int *y);
            int SDL_GetWindowDisplayIndex(void *window);
            int SDL_GetDisplayUsableBounds(int display, LaboWindowRect *rect);
            unsigned int SDL_GetWindowFlags(void *window);
            void SDL_SetWindowBordered(void *window, int bordered);
            int SDL_SetWindowHitTest(void *window, int (*callback)(void *, const LaboWindowPoint *, void *), void *data);
            const char *SDL_GetError(void);
            void SDL_GetVersion(unsigned char *version);
            int SDL_GetWindowWMInfo(void *window, LaboWindowInfo *info);
            long __stdcall GetWindowLongW(void *window, int index);
            long __stdcall SetWindowLongW(void *window, int index, long value);
            int __stdcall SetWindowPos(void *window, void *after, int x, int y, int w, int h, unsigned int flags);
            typedef struct {long left; long top; long right; long bottom;} LaboNativeRect;
            typedef struct {unsigned int size; LaboNativeRect monitor; LaboNativeRect work; unsigned int flags;} LaboMonitorInfo;
            intptr_t __stdcall SetWindowLongPtrW(void *window, int index, intptr_t value);
            intptr_t __stdcall CallWindowProcW(void *proc, void *window, unsigned int message, uintptr_t wparam, intptr_t lparam);
            int __stdcall IsZoomed(void *window);
            void * __stdcall MonitorFromWindow(void *window, unsigned int flags);
            int __stdcall GetMonitorInfoW(void *monitor, LaboMonitorInfo *info);
            long __stdcall DwmSetWindowAttribute(void *window, unsigned int attribute, const void *value, unsigned int size);
            long __stdcall DwmGetWindowAttribute(void *window, unsigned int attribute, void *value, unsigned int size);
        ]]
        local sdl = ffi.load("SDL2")
        local window = sdl.SDL_GL_GetCurrentWindow()
        assert(window ~= nil, "No active editor OpenGL window")
        local size = ffi.new("int[2]")
        local bit = require("bit")
        local function classify(nativeWindow, point)
            sdl.SDL_GetWindowSize(nativeWindow, size, size + 1)
            return Frame.hitTest(point.x, point.y, size[0], size[1],
                bit.band(sdl.SDL_GetWindowFlags(nativeWindow), 128) ~= 0, Frame.blocked, Frame.dragLeft)
        end
        -- SDL 이벤트 처리 중 C에서 Lua로 돌아오는 콜백은 JIT 컴파일하지 않는다.
        jit.off(classify, true)
        Frame.callback = ffi.cast("int (*)(void *, const LaboWindowPoint *, void *)", classify)
        local result = sdl.SDL_SetWindowHitTest(window, Frame.callback, nil)
        if result ~= 0 then
            Frame.callback:free(); Frame.callback = nil
            error(ffi.string(sdl.SDL_GetError()))
        end
        Frame.native, Frame.window = sdl, window
        Frame.active = true
        sdl.SDL_SetWindowBordered(window, 0)
        -- SDL 2의 borderless 창에도 최대화 스타일을 부여하되 기본 테두리는 만들지 않는다.
        local user = ffi.load("user32")
        local info = ffi.new("LaboWindowInfo")
        sdl.SDL_GetVersion(info.version)
        assert(sdl.SDL_GetWindowWMInfo(window, info) ~= 0, ffi.string(sdl.SDL_GetError()))
        local handle = info.info.win.window
        local monitor = ffi.new("LaboMonitorInfo")
        monitor.size = ffi.sizeof(monitor)
        local function windowProc(hwnd, message, wparam, lparam)
            -- 활성화·네이티브 이동 루프에서도 SDL 포커스 처리는 유지하고 기본 장식 그리기만 막는다.
            if message == 0x0086 then lparam = -1 end -- WM_NCACTIVATE
            if message == 0x0085 or message == 0x00AE or message == 0x00AF then return 0 end
            local result = user.CallWindowProcW(Frame.previousProc, hwnd, message, wparam, lparam)
            -- SDL 2는 최대화한 borderless 클라이언트를 모니터 전체로 확장한다.
            -- 계산 뒤 작업 영역으로 제한해 작업 표시줄과 화면 밖 버튼을 방지한다.
            if message == 0x0083 and wparam ~= 0 and user.IsZoomed(hwnd) ~= 0
                and user.GetMonitorInfoW(user.MonitorFromWindow(hwnd, 2), monitor) ~= 0 then
                local rect = ffi.cast("LaboNativeRect *", lparam)
                rect[0] = monitor.work
                return 0
            end
            return result
        end
        jit.off(windowProc, true)
        Frame.windowProc = ffi.cast("intptr_t (__stdcall *)(void *, unsigned int, uintptr_t, intptr_t)", windowProc)
        Frame.user, Frame.handle = user, handle
        Frame.setWindowPointer = ffi.abi("64bit") and user.SetWindowLongPtrW or user.SetWindowLongW
        local previous = Frame.setWindowPointer(handle, -4, ffi.cast("intptr_t", Frame.windowProc))
        assert(previous ~= 0, "Could not install editor window procedure")
        Frame.previousProc = ffi.cast("void *", previous)
        local style = user.GetWindowLongW(handle, -16)
        style = bit.bor(bit.band(style, bit.bnot(0x00C40000)), 0x00090000)
        assert(user.SetWindowLongW(handle, -16, style) ~= 0, "Could not update editor window style")
        assert(user.SetWindowPos(handle, nil, 0, 0, 0, 0, 39) ~= 0, "Could not refresh editor window frame")
        -- Windows 11의 네이티브 라운딩을 요청한다. 최대화·스냅 시에는 DWM이 사각으로 표시한다.
        -- 이전 Windows에서 속성을 지원하지 않아도 창 제어 기능은 유지한다.
        local loaded, dwm = pcall(ffi.load, "dwmapi")
        Frame.roundedCorners = false
        if loaded then
            local preference = ffi.new("unsigned int[1]", 2)
            Frame.roundedCorners = dwm.DwmSetWindowAttribute(handle, 33, preference, ffi.sizeof(preference)) == 0
        end
    end)
    if not ok then
        if Frame.active then
            Frame.shutdown()
            Frame.native.SDL_SetWindowBordered(Frame.window, 1)
        end
        return false, tostring(err)
    end
    return true
end

function Frame.setHeader(dragLeft, blocked)
    Frame.dragLeft, Frame.blocked = dragLeft, blocked == true
end

function Frame.toggleMaximize()
    if love.window.isMaximized() then love.window.restore() else love.window.maximize() end
end

function Frame.shutdown()
    if not Frame.active then return end
    if Frame.windowProc then
        if Frame.previousProc then Frame.setWindowPointer(Frame.handle, -4, require("ffi").cast("intptr_t", Frame.previousProc)) end
        Frame.windowProc:free(); Frame.windowProc = nil
        Frame.previousProc = nil
    end
    -- SDL이 콜백을 더 호출하지 않게 해제한 다음 Lua 콜백 메모리를 반환한다.
    Frame.native.SDL_SetWindowHitTest(Frame.window, nil, nil)
    Frame.callback:free(); Frame.callback = nil
    Frame.active = false
end

-- 창 스타일 변경·해제는 동기적으로 네이티브 콜백에 재진입할 수 있다.
if jit then
    jit.off(Frame.install, true)
    jit.off(Frame.shutdown, true)
end

return Frame
