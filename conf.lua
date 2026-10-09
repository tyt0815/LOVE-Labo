function love.conf(t)
    t.identity = "love-labo"
    t.version = "11.5"

    -- Windows에서도 테스트 출력과 Lua 오류를 보기 쉽게 한다.
    t.console = not love.filesystem.isFused()

    t.window.title = "LÖVE Labo"
    t.window.width = 1920
    t.window.height = 1080
    t.window.resizable = true
    t.window.minwidth = 800
    t.window.minheight = 540
end
