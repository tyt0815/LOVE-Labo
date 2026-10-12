local Fs = require("editor.HostFileSystem")
local Import = {}
function Import.copy(project, input, folder, name)
    if project:isReadOnly(folder) then return false, "Labo plugin assets are read-only" end
    local entries, err = project:listDirectory(folder)
    if not entries then return false, err end
    name = name or input:gsub("\\", "/"):match("([^/]+)$")
    local valid, nameError = require("editor.Project").isValidName(name)
    if not valid then return false, nameError end
    if require("editor.AssetRegistry").isInternal(name) then return false, "Metadata cannot be imported separately" end
    local reference = folder .. "/" .. name
    local available, registrationError = require("editor.AssetCatalog").checkDestination(project, reference)
    if not available then return false, registrationError end
    local target = assert(project:resolvePath(reference))
    if Fs.info(target) or Fs.info(target .. ".meta") then return false, "Destination already exists: " .. name end
    local items, created, catalogWritten = {}, {}, false
    local function scan(path, destination)
        local info = assert(Fs.info(path), "Source does not exist")
        assert(not info.isLink, "Import does not follow filesystem links")
        items[#items + 1] = {path = path, destination = destination, type = info.type}
        if info.type == "directory" then
            for _, child in ipairs(assert(Fs.list(path))) do
                if not require("editor.AssetRegistry").isInternal(child.name) then scan(Fs.join(path, child.name), Fs.join(destination, child.name)) end
            end
        else assert(info.type == "file", "Expected a file or folder") end
    end
    local ok, result = pcall(function()
        scan(input, target)
        for _, item in ipairs(items) do
            if item.type == "directory" then assert(Fs.mkdir(item.destination))
            else assert(Fs.createFile(item.destination, assert(Fs.read(item.path)))) end
            created[#created + 1] = item
        end
        local metadata = {}
        for _, item in ipairs(items) do if item.type == "file" then
            metadata[reference .. item.destination:sub(#target + 1)] = {version = 1, id = require("project.AssetId").new()}
        end end
        assert(require("editor.AssetCatalog").update(project, metadata))
        catalogWritten = true
        assert(project:rebuildAssetIndex())
    end)
    if not ok then
        if catalogWritten then require("editor.AssetCatalog").remove(project, reference) end
        for index = #created, 1, -1 do
            local item = created[index]
            if item.type == "file" then Fs.removeFile(item.destination .. ".meta"); Fs.removeFile(item.destination)
            else Fs.removeDirectory(item.destination) end
        end
        project:rebuildAssetIndex(); return false, tostring(result)
    end
    return true, reference
end
return Import
