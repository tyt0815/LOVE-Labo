local World = {}
function World:draw()
    love.graphics.setColor(0.2, 0.22, 0.24, 1)
    for position = -2560, 2560, 80 do
        love.graphics.line(position, -2560, position, 2560); love.graphics.line(-2560, position, 2560, position)
    end
    love.graphics.setColor(0.9, 0.35, 0.2, 1); love.graphics.circle("fill", 0, 0, 36)
end
return World
