-- labo-script: script
local AudioLifecycle = {properties = {
    sound = {type = "audio", default = false},
    status = {type = "string", default = "Ready"}
}}
function AudioLifecycle:load(world)
    self.world = world
    if self.sound then
        self.data = assert(world:getAssetData(self.sound))
        -- 재생·반복·볼륨은 일반 LÖVE API로 제어한다.
        if love.audio then self.audioSource = love.audio.newSource(self.data, "static") end
    end
end
function AudioLifecycle:keypressed(key)
    if key == "space" and self.audioSource then
        self.audioSource:stop(); self.audioSource:play(); self.status = "Playing"
    elseif key == "delete" then
        self.world:removeLObject(self.owner)
    elseif key == "n" then
        assert(self.world:openLevel("Assets/Examples/L_AudioLifecycle.level"))
    end
end
function AudioLifecycle:unload()
    if self.audioSource then self.audioSource:stop(); self.audioSource:release(); self.audioSource = nil end
    if self.data then self.data:release(); self.data = nil end
    self.owner.world.debug:log("AudioLifecycle unloaded: " .. self.owner.name)
end
function AudioLifecycle:draw()
    love.graphics.setColor(0.2, 0.8, 1, 1)
    love.graphics.rectangle("fill", -20, -20, 40, 40)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.print("Space: play tone / Delete: remove object / N: reload level", -400, -120)
    love.graphics.print("Stop Play: unload stops and releases the Source", -400, -80)
    love.graphics.print(self.status, -400, -40)
end
return AudioLifecycle
