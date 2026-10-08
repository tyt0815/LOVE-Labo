local Transform = {}
function Transform.finite(value)
    return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end
function Transform.copy(value)
    if type(value) ~= "table" or not Transform.finite(value.x) or not Transform.finite(value.y) then return nil, "Transform x/y must be finite numbers" end
    local rotation = value.rotation == nil and 0 or value.rotation
    local scaleX, scaleY = value.scaleX == nil and 1 or value.scaleX, value.scaleY == nil and 1 or value.scaleY
    if not Transform.finite(rotation) or not Transform.finite(scaleX) or not Transform.finite(scaleY) or scaleX <= 0 or scaleY <= 0 then return nil, "Invalid Transform rotation or scale" end
    return {x = value.x, y = value.y, rotation = rotation, scaleX = scaleX, scaleY = scaleY}
end
function Transform.toData(value)
    return {x = value.x, y = value.y,
        rotation = value.rotation ~= 0 and value.rotation or nil,
        scaleX = value.scaleX ~= 1 and value.scaleX or nil,
        scaleY = value.scaleY ~= 1 and value.scaleY or nil}
end
function Transform.point(value, x, y)
    local angle = math.rad(value.rotation or 0)
    local cosine, sine = math.cos(angle), math.sin(angle)
    x, y = x * (value.scaleX or 1), y * (value.scaleY or 1)
    return value.x + x * cosine - y * sine, value.y + x * sine + y * cosine
end
function Transform.inversePoint(value, x, y)
    local angle = math.rad(value.rotation or 0)
    local cosine, sine = math.cos(angle), math.sin(angle)
    x, y = x - value.x, y - value.y
    return (x * cosine + y * sine) / (value.scaleX or 1), (-x * sine + y * cosine) / (value.scaleY or 1)
end
return Transform
