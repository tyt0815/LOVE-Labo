local Json = require("Examples.SaveJson")
local Session = {properties = {
    levelA = {type = "string", default = ""}, levelB = {type = "string", default = ""},
    status = {type = "string", default = "No save loaded"},
}}
function Session:load()
    self.saveFile = "saves/" .. assert(self.owner.saveIdentity) .. "/slot1.json"
end
local function finite(value) return type(value) == "number" and value == value and math.abs(value) < math.huge end
function Session:validate(data)
    if type(data) ~= "table" or data.version ~= 1 then return false, "Unsupported save version" end
    if data.level ~= self.levelA and data.level ~= self.levelB then return false, "Unknown saved level" end
    local player = data.player
    if type(player) ~= "table" then return false, "Missing player data" end
    for _, key in ipairs({"hp", "gold", "keys", "x", "y"}) do
        if not finite(player[key]) then return false, "Invalid player field: " .. key end
    end
    if player.hp < 0 or player.hp > 100 or player.gold < 0 or player.keys < 0
        or player.gold % 1 ~= 0 or player.keys % 1 ~= 0 then return false, "Invalid player values" end
    return true
end
function Session:saveSlot(traveller, level)
    local data = {version = 1, level = level, player = {hp = traveller.hp, gold = traveller.gold, keys = traveller.keys,
        x = traveller.owner.transform.x, y = traveller.owner.transform.y}}
    local valid, err = self:validate(data)
    if not valid then self.status = err; return false, err end
    local directory = self.saveFile:match("^(.*)/")
    local made, makeError = love.filesystem.createDirectory(directory)
    if not made then self.status = makeError or "Could not create save directory"; return false, self.status end
    local encoded, encodeError = Json.encode(data)
    if not encoded then self.status = tostring(encodeError); return false, encodeError end
    local ok, writeError = love.filesystem.write(self.saveFile, encoded)
    self.status = ok and "Saved slot 1" or (writeError or "Could not write save file")
    return ok, writeError
end
function Session:loadSlot()
    local bytes, err = love.filesystem.read(self.saveFile)
    if not bytes then self.status = "Save missing: " .. tostring(err); return false, self.status end
    local data, decodeError = Json.decode(bytes)
    local valid, validationError = self:validate(data)
    if not valid then self.status = decodeError or validationError; return false, self.status end
    self.pendingRestore = data.player
    local ok, transitionError = self:getWorld():openLevel(data.level)
    if not ok then self.pendingRestore = nil end
    self.status = ok and "Loading slot 1" or tostring(transitionError)
    return ok, transitionError
end
return Session
