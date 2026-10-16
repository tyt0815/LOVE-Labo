local Model = {}
function Model.validate(data)
    assert(type(data) == "table" and data.version == 1 and type(data.notes) == "table", "Invalid stage")
    assert(type(data.name) == "string" and #data.name > 0, "Stage requires a name")
    for index, note in ipairs(data.notes) do
        assert(type(note) == "table" and type(note.beat) == "number" and note.beat >= 0 and note.beat < math.huge, "Invalid note beat: " .. index)
        assert(type(note.lane) == "number" and note.lane % 1 == 0 and note.lane >= 1 and note.lane <= 4, "Invalid note lane: " .. index)
    end
    for key in pairs(data.notes) do assert(type(key) == "number" and key >= 1 and key <= #data.notes and key % 1 == 0, "Invalid notes array") end
    return data
end
function Model.new(name) return {version = 1, name = name, notes = {}} end
function Model.add(data, beat, lane)
    Model.validate(data)
    data.notes[#data.notes + 1] = {beat = beat, lane = lane}
    return Model.validate(data)
end
function Model.moveFirst(data, direction)
    Model.validate(data)
    if data.notes[1] then data.notes[1].lane = math.max(1, math.min(4, data.notes[1].lane + direction)) end
    return Model.validate(data)
end
return Model
