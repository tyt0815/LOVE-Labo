local BuildInfo = require("BuildInfo")
local Version = {major = 0, minor = 1, patch = 0, prerelease = "dev"}

function Version.getInfo()
    local number = string.format("%d.%d.%d", Version.major, Version.minor, Version.patch)
    if Version.prerelease ~= "" then number = number .. "-" .. Version.prerelease end
    local display = number
    if BuildInfo.revision then
        display = display .. "+" .. BuildInfo.revision .. (BuildInfo.dirty and ".dirty" or "")
    end
    return {engineVersion = number, displayVersion = display,
        revision = BuildInfo.revision, dirty = BuildInfo.dirty}
end

return Version
