-- labo-script: script
local NewClass = {privateValue = 123, properties = {
    speed = {type = "number", default = 100, group = "Movement"},
    title = {type = "string", default = "Example"},
    enabled = {type = "boolean", default = true},
    target = {type = "object", default = false},
    otherScript = {type = "script", default = false},
    projectile = {type = "prefab", default = false}
}}
function NewClass.beginPlay(self, world)
    self.hiddenCounter = 0
    if self.projectile ~= false then
        self.spawned = assert(world:spawnLObject(self.projectile, {x = 200, y = 0}))
    end
end
function NewClass.update(self, dt)
    self.hiddenCounter = self.hiddenCounter + 1
    if self.enabled then self.owner.transform.x = self.owner.transform.x + self.speed * dt end
end
return NewClass
