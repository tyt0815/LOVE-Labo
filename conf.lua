function love.conf(t)
    t.identity = "love-labo"
    t.version = "11.5"

    -- Windows에서도 테스트 출력과 Lua 오류를 보기 쉽게 한다.
    t.console = true

    t.window.title = "LÖVE Labo"
    t.window.width = 1280
    t.window.height = 720
    t.window.resizable = true
end