local Drop = {}
function Drop.intent(row, y, top, height)
    if not row then return {mode = "detach"} end
    local offset = y - top
    if offset < height * 0.25 then return {mode = "before", target = row}
    elseif offset > height * 0.75 then return {mode = "after", target = row} end
    return {mode = "attach", target = row}
end
function Drop.tree(rows, row, y, top, height)
    local intent = Drop.intent(row, y, top, height)
    if not row and #rows > 0 then
        local last = rows[#rows]
        local outer = last
        local depth = rows[1].key == "root" and 1 or 0
        for index = #rows, 1, -1 do if rows[index].depth == depth then outer = rows[index]; break end end
        return {mode = "after", target = outer, depth = outer.depth, lineY = top}
    end
    intent.depth = row and row.depth or 0
    intent.lineY = top + (intent.mode == "after" and height or 0)
    return intent
end
return Drop
