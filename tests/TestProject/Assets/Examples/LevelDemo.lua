local LevelDemo = {properties = {welcome = {type = "string", default = "API examples ready"}}}
function LevelDemo:load(world)
    world.exampleElapsed = 0
    world.debug:screenLog(self.welcome, {key = "welcome", lifespan = 5})
end
function LevelDemo:update(dt) local world = self:getWorld(); world.exampleElapsed = world.exampleElapsed + dt end
return LevelDemo
