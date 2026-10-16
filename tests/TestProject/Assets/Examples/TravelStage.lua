local Stage = {properties = {stageName = {type = "string", default = "A"}, level = {type = "string", default = ""},
    destination = {type = "string", default = ""}, failure = {type = "string", default = ""},
    playerPrefab = {type = "lobjectTemplate", default = false}}}
function Stage:load(world)
    self.session = assert(self:getProject():getScriptByName("travelSession"))
    for _, object in ipairs(world:getObjects()) do
        if object:getScriptByName("traveller") then self.player = object end
    end
    if not self.player then self.player = assert(world:spawnLObject(self.playerPrefab, {x = 0, y = 0})) end
    self.traveller = self.player:getScriptByName("traveller")
    local restored = self.session.pendingRestore
    if restored then
        self.traveller.hp, self.traveller.gold, self.traveller.keys = restored.hp, restored.gold, restored.keys
        self.player.transform.x, self.player.transform.y = restored.x, restored.y
        self.appliedRestore = restored
    end
end
function Stage:update()
    if self.appliedRestore and self.session.pendingRestore == self.appliedRestore then
        self.session.pendingRestore = nil; self.session.status = "Loaded slot 1"; self.appliedRestore = nil
    end
    local err = self:getWorld().levelTransitionError
    if err then self.session.status = "Transition failed; previous World retained" end
end
function Stage:keypressed(key)
    if key == "n" then assert(self:getWorld():openLevel(self.destination, {carry = {self.player}}))
    elseif key == "f" then assert(self:getWorld():openLevel(self.failure, {carry = {self.player}}))
    elseif key == "s" then self.session:saveSlot(self.traveller, self.level)
    elseif key == "l" then self.session:loadSlot()
    elseif key == "h" then self.traveller.hp = math.max(0, self.traveller.hp - 10)
    elseif key == "g" then self.traveller.gold = self.traveller.gold + 1
    elseif key == "k" then self.traveller.keys = self.traveller.keys + 1 end
end
function Stage:draw(context)
    love.graphics.setColor(self.stageName == "A" and 0.16 or 0.24, 0.18, 0.22, 1)
    for x = -2560, 2560, 80 do love.graphics.line(x, -1000, x, 1000) end
    for y = -1000, 1000, 80 do love.graphics.line(-2560, y, 2560, y) end
    context:withScreen(function()
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.printf("Stage " .. self.stageName .. " | Player instance " .. self.traveller.token .. " | World changes " .. self.traveller.visits,
            0, 100, context.viewport.width, "center")
        love.graphics.printf("A/D move | N travel | F fail travel | H damage | G gold | K key | S save | L load",
            0, context.viewport.height - 78, context.viewport.width, "center")
        love.graphics.printf(self.session.status, 0, context.viewport.height - 46, context.viewport.width, "center")
    end)
end
return Stage
