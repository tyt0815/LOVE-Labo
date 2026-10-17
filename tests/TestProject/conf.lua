-- 게임의 LÖVE 초기화 설정이다. 에디터 Play와 게임 CLI에는 적용하지 않는다.
function love.conf(config)
    config.window.title = "TestProject"
    config.window.width = 1280
    config.window.height = 720
    config.window.resizable = true
    config.window.vsync = 1
    -- config.window.icon = "Assets/Icon.png"
    -- config.window.fullscreen = true
end
