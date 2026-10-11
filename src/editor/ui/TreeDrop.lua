local Drop = {}
function Drop.intent(row, y, top, height)
    if not row then return {mode = "detach"} end
    local offset = y - top
    if offset < height * 0.25 then return {mode = "before", target = row}
    elseif offset > height * 0.75 then return {mode = "after", target = row} end
    return {mode = "attach", target = row}
end
return Drop
