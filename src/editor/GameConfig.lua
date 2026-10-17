local Fs = require("editor.HostFileSystem")
local Workspace = require("project.Workspace")
local Config = {}
Config.FILE = "conf.lua"

function Config.template(name)
    return [[-- 게임의 LÖVE 초기화 설정이다. 에디터 Play와 게임 CLI에는 적용하지 않는다.
function love.conf(config)
    config.window.title = ]] .. string.format("%q", name or "Labo Game") .. [[

    config.window.width = 1280
    config.window.height = 720
    config.window.resizable = true
    config.window.vsync = 1
    -- config.window.icon = "Assets/Icon.png"
    -- config.window.fullscreen = true
end
]]
end

function Config.ensure(project)
    local path = Workspace.new(project.rootPath):path(Config.FILE)
    local info, err = Fs.info(path)
    assert(not err, err)
    if info then assert(info.type == "file" and not info.isLink, "conf.lua must be a regular file")
    else assert(Fs.createFile(path, Config.template(project.name))) end
    return path
end

function Config.read(project)
    local bytes = assert(Fs.read(Config.ensure(project))):gsub("^\239\187\191", "")
    -- Export에서는 문법만 검사하고 사용자 초기화 코드를 실행하지 않는다.
    assert(loadstring(bytes, "@conf.lua"))
    return bytes
end

function Config.wrapper(project)
    return [[require("ProjectConf")
local configure = love.conf
assert(type(configure) == "function", "Project conf.lua must define love.conf(config)")
function love.conf(config)
    config.version = "11.5"
    config.identity = ]] .. string.format("%q", assert(project.saveIdentity)) .. [[

    config.window.title = ]] .. string.format("%q", project.name or "Labo Game") .. [[

    config.window.width = 1280
    config.window.height = 720
    config.window.resizable = true
    local identity = config.identity
    configure(config)
    assert(config.identity == identity, "conf.lua must preserve the project save identity; use project.reset-save-identity for a separate game")
    -- 프로젝트·플러그인 에셋 경로와 ID를 패키지의 실제 아이콘 경로로 해석한다.
    if config.window and type(config.window.icon) == "string" then
        local path = config.window.icon
        local manifest = assert(require("project.Json").decode(assert(love.filesystem.read("game.json"))))
        for reference, metadata in pairs(manifest.metadata) do
            if path == reference or path == metadata.id then config.window.icon = "project/" .. reference; break end
        end
    end
end
]]
end
return Config
