local Fs = require("editor.HostFileSystem")
local Json = require("project.Json")
local Editor = {}
-- 셸을 거치지 않는 Windows argv 인코딩이다. 공백·따옴표·끝의 역슬래시를 보존한다.
function Editor.quote(value)
    assert(type(value) == "string" and not value:find("%z"), "Invalid process argument")
    local output, slashes = {'"'}, 0
    for index = 1, #value do
        local char = value:sub(index, index)
        if char == "\\" then slashes = slashes + 1
        else
            output[#output + 1] = string.rep("\\", char == '"' and slashes * 2 + 1 or slashes) .. char
            slashes = 0
        end
    end
    output[#output + 1] = string.rep("\\", slashes * 2) .. '"'
    return table.concat(output)
end
function Editor.settings()
    local bytes
    if love.filesystem.isFused() then bytes = Fs.read(Fs.join(love.filesystem.getSourceBaseDirectory(), "settings.json"))
    else bytes = love.filesystem.read("editor/settings.json") end
    if not bytes then return {} end
    local settings, err = Json.decode(bytes)
    assert(type(settings) == "table" and settings.version == 1, err or "Invalid editor settings")
    assert(settings.codeEditor == nil or type(settings.codeEditor) == "table", "Invalid codeEditor settings")
    return settings.codeEditor or {}
end
function Editor.detect(settings, env, info)
    settings, env, info = settings or {}, env or os.getenv, info or Fs.info
    if settings.executable then
        assert(type(settings.executable) == "string" and settings.executable:lower():match("%.exe$")
            and info(settings.executable), "codeEditor.executable must identify an installed .exe")
        return settings.executable
    end
    local candidates = {}
    local function candidate(base, suffix) if base then candidates[#candidates + 1] = Fs.join(base, suffix) end end
    candidate(env("LOCALAPPDATA"), "Programs/Microsoft VS Code/Code.exe")
    candidate(env("ProgramFiles"), "Microsoft VS Code/Code.exe")
    candidate(env("ProgramFiles(x86)"), "Microsoft VS Code/Code.exe")
    for directory in (env("PATH") or ""):gmatch("[^;]+") do
        directory = directory:gsub('^"', ''):gsub('"$', '')
        candidate(directory, "Code.exe")
        if directory:gsub("\\", "/"):lower():match("/bin/?$") then candidate(Fs.parent(directory), "Code.exe") end
    end
    for _, path in ipairs(candidates) do
        local entry = info(path)
        if entry and entry.type == "file" then return path end
    end
    error("VS Code was not found. Install VS Code or configure codeEditor.executable in editor settings")
end
function Editor.plan(project, source, settings)
    assert(type(source) == "string", "Specify a script source")
    local public = project.plugins and project.plugins.scripts[source]
    source = public and public.id or source
    local reference = assert(project:getAssetReference(source))
    assert(reference:lower():match("%.lua$"), "Code opening requires a Lua script")
    local originalPath = assert(project:resolveSourceFile(source))
    local bytes = assert(Fs.read(originalPath))
    local readOnly = project:isReadOnly(source)
    local path = originalPath
    if readOnly then
        -- 제공 에셋 캐시를 외부 편집기에 넘기지 않고 내용별 열람용 사본을 연다.
        local hash = love.data.encode("string", "hex", love.data.hash("sha256", bytes))
        path = Fs.join(project.rootPath, ".labo/CodePreview/" .. hash .. "/" .. reference:match("[^/]+$"))
    end
    settings = settings or Editor.settings()
    local executable = Editor.detect(settings)
    local args, substituted = {}, false
    assert(settings.arguments == nil or type(settings.arguments) == "table", "codeEditor.arguments must be an array")
    for _, argument in ipairs(settings.arguments or {"--reuse-window"}) do
        assert(type(argument) == "string", "Editor arguments must be strings")
        if argument:find("{file}", 1, true) then substituted = true end
        args[#args + 1] = argument:gsub("{file}", function() return path end)
    end
    if not substituted then args[#args + 1] = path end
    return {executable = executable, arguments = args, path = path, sourcePath = originalPath, readOnly = readOnly}
end
function Editor.launch(plan)
    local ffi = require("ffi")
    if not pcall(ffi.typeof, "LaboEditorStartup") then ffi.cdef[[
    typedef struct { uint32_t cb; uint16_t *reserved; uint16_t *desktop; uint16_t *title;
        uint32_t x,y,xSize,ySize,xCount,yCount,fill,flags; uint16_t show,reservedSize;
        uint8_t *reservedBytes; void *input,*output,*error; } LaboEditorStartup;
    typedef struct {void *process,*thread; uint32_t processId,threadId;} LaboEditorProcess;
    int __stdcall CreateProcessW(const uint16_t*, uint16_t*, void*, void*, int, uint32_t, void*, const uint16_t*, LaboEditorStartup*, LaboEditorProcess*);
    int __stdcall SetFileAttributesW(const uint16_t*, uint32_t);
    ]] end
    local wide = require("editor.WindowsUnicode").wide
    local win = ffi.load("kernel32")
    local parts = {Editor.quote(plan.executable)}
    for _, argument in ipairs(plan.arguments) do parts[#parts + 1] = Editor.quote(argument) end
    local startup, process = ffi.new("LaboEditorStartup"), ffi.new("LaboEditorProcess")
    startup.cb = ffi.sizeof(startup)
    if win.CreateProcessW(wide(plan.executable), wide(table.concat(parts, " ")), nil, nil, 0, 0, nil, nil, startup, process) == 0 then
        error("Cannot launch code editor (Windows error " .. tonumber(win.GetLastError()) .. ")")
    end
    win.CloseHandle(process.process); win.CloseHandle(process.thread)
    return tonumber(process.processId)
end
function Editor.open(project, source, dryRun, settings, launch)
    local plan = Editor.plan(project, source, settings)
    if dryRun then return plan end
    if plan.readOnly then
        local directory = Fs.parent(plan.path)
        for _, folder in ipairs({Fs.join(project.rootPath, ".labo"), Fs.join(project.rootPath, ".labo/CodePreview"), directory}) do
            local entry = Fs.info(folder)
            if not entry then assert(Fs.mkdir(folder))
            else assert(entry.type == "directory" and not entry.isLink, "Preview folder must not be a filesystem link") end
        end
        if not Fs.info(plan.path) then assert(Fs.createFile(plan.path, assert(Fs.read(plan.sourcePath)))) end
        local ffi = require("ffi")
        ffi.cdef[[int __stdcall SetFileAttributesW(const uint16_t*, uint32_t);]]
        assert(ffi.load("kernel32").SetFileAttributesW(require("editor.WindowsUnicode").wide(plan.path), 1) ~= 0,
            "Cannot protect plugin source preview")
    end
    plan.processId = (launch or Editor.launch)(plan)
    return plan
end
return Editor
