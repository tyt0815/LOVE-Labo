local Transform = {}
Transform.FIELDS = {x = true, y = true, rotationX = true, rotationY = true, rotation = true, scaleX = true, scaleY = true}
Transform.ORDER = {"x", "y", "rotationX", "rotationY", "rotation", "scaleX", "scaleY"}
function Transform.finite(value)
    return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end
function Transform.normalizeRotation(value) return value % 360 end
function Transform.copy(value)
    if type(value) ~= "table" or not Transform.finite(value.x) or not Transform.finite(value.y) then return nil, "Transform x/y must be finite numbers" end
    local rotation = value.rotation == nil and 0 or value.rotation
    local rotationX, rotationY = value.rotationX == nil and 0 or value.rotationX, value.rotationY == nil and 0 or value.rotationY
    local scaleX, scaleY = value.scaleX == nil and 1 or value.scaleX, value.scaleY == nil and 1 or value.scaleY
    if not Transform.finite(rotation) or not Transform.finite(rotationX) or not Transform.finite(rotationY) or not Transform.finite(scaleX) or not Transform.finite(scaleY) or scaleX <= 0 or scaleY <= 0 then return nil, "Invalid Transform rotation or scale" end
    return {x = value.x, y = value.y, rotation = Transform.normalizeRotation(rotation),
        rotationX = Transform.normalizeRotation(rotationX), rotationY = Transform.normalizeRotation(rotationY), scaleX = scaleX, scaleY = scaleY}
end
local function optionalRotation(value)
    if Transform.finite(value) then value = Transform.normalizeRotation(value) end
    if value == nil or value == 0 then return nil end
    return value
end
function Transform.toData(value)
    return {x = value.x, y = value.y,
        rotationX = optionalRotation(value.rotationX), rotationY = optionalRotation(value.rotationY),
        rotation = optionalRotation(value.rotation),
        scaleX = value.scaleX ~= 1 and value.scaleX or nil,
        scaleY = value.scaleY ~= 1 and value.scaleY or nil}
end
-- 로컬 스케일 → X/Y/Z 회전 → XY 직교 투영 순서로 동일한 행렬을 공유한다.
function Transform.basis(value)
    if value.a then return value.a, value.b, value.c, value.d end
    local rx, ry, rz = math.rad(value.rotationX or 0), math.rad(value.rotationY or 0), math.rad(value.rotation or 0)
    local cx, sx, cy, sy, cz, sz = math.cos(rx), math.sin(rx), math.cos(ry), math.sin(ry), math.cos(rz), math.sin(rz)
    local scaleX, scaleY = value.scaleX or 1, value.scaleY or 1
    return cz * cy * scaleX, sz * cy * scaleX,
        (cz * sy * sx - sz * cx) * scaleY, (sz * sy * sx + cz * cx) * scaleY
end
function Transform.compose(parent, child)
    local a, b, c, d = Transform.basis(parent)
    local e, f, g, h = Transform.basis(child)
    local x, y = Transform.point(parent, child.x, child.y)
    return {x = x, y = y, a = a * e + c * f, b = b * e + d * f, c = a * g + c * h, d = b * g + d * h}
end
function Transform.point(value, x, y)
    local a, b, c, d = Transform.basis(value)
    return value.x + a * x + c * y, value.y + b * x + d * y
end
function Transform.inversePoint(value, x, y)
    local a, b, c, d = Transform.basis(value)
    local determinant = a * d - b * c
    if math.abs(determinant) < 1e-8 then return nil, nil end
    x, y = x - value.x, y - value.y
    return (d * x - c * y) / determinant, (-b * x + a * y) / determinant
end
return Transform
