local AssetData = {}
local AUDIO_EXTENSIONS = {wav = true, ogg = true, mp3 = true, flac = true}
function AssetData.isAudio(reference)
    return type(reference) == "string" and AUDIO_EXTENSIONS[(reference:match("%.([^%.]+)$") or ""):lower()] == true
end
function AssetData.read(project, reference)
    local path, err = project:getAssetReference(reference)
    if not path then return nil, err end
    local bytes, readError = project:readAsset(reference)
    if not bytes then return nil, readError end
    -- 원본 확장자를 유지해야 LÖVE 디코더가 파일 형식을 해석할 수 있다.
    return love.filesystem.newFileData(bytes, path)
end
function AssetData.validateAudio(project, reference)
    local path, err = project:getAssetReference(reference)
    if not path or not AssetData.isAudio(path) then return false, err or "Expected a WAV, OGG, MP3 or FLAC audio asset" end
    local data, readError = AssetData.read(project, reference)
    if not data then return false, readError end
    local ok, decoder = pcall(love.sound.newDecoder, data)
    data:release()
    if not ok then return false, tostring(decoder) end
    decoder:release()
    return true
end
return AssetData
