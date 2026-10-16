local LevelLogic = {properties = {
    fixedStep = {type = "number", default = 1 / 60, group = "Fixed update"},
    levelTitle = {type = "string", default = "First level"},
    nextLevel = {type = "string", default = ""}
}}
function LevelLogic:load()
    self.view = require("Engine").Rendering.createView(self:getWorld(), {owner = self})
    self.accumulator, self.steps = 0, 0
    local manager = self:getProject():getScriptByName("scopeSession")
    if manager then manager.visits = manager.visits + 1 end
end
function LevelLogic:update(dt)
    assert(self.fixedStep > 0, "fixedStep must be positive")
    self.accumulator = self.accumulator + dt
    local targets = {}
    for _, object in ipairs(self:getWorld():getObjects()) do
        for _, id in ipairs(object:getScriptOrder()) do
            local script = object:getScriptById(id)
            if script.fixedUpdate then targets[#targets + 1] = script end
        end
    end
    -- 우선순위는 Inspector 프로퍼티가 아닌 일반 인스턴스 변수다.
    table.sort(targets, function(a, b)
        if (a.priority or 0) == (b.priority or 0) then return a.id < b.id end
        return (a.priority or 0) < (b.priority or 0)
    end)
    local count = 0
    while self.accumulator >= self.fixedStep and count < 8 do
        for _, script in ipairs(targets) do
            if script.owner and script.enabled ~= false then script:fixedUpdate(self.fixedStep) end
        end
        self.accumulator, self.steps, count = self.accumulator - self.fixedStep, self.steps + 1, count + 1
    end
    -- 긴 프레임에서 무제한으로 따라잡지 않도록 예제의 최대 반복 횟수를 제한한다.
    if count == 8 then self.accumulator = self.accumulator % self.fixedStep end
end
function LevelLogic:keypressed(key)
    if key == "n" and self.nextLevel ~= "" then assert(self:getWorld():openLevel(self.nextLevel)) end
end
function LevelLogic:draw(context)
    love.graphics.setColor(0.3, 0.4, 0.5, 1)
    love.graphics.line(-240, 0, 240, 0)
    love.graphics.circle("line", 0, 0, 100)
end
function LevelLogic:drawScreen(context)
    love.graphics.setColor(1, 0.85, 0.25, 1)
    love.graphics.print(self.levelTitle .. " | fixed steps " .. self.steps .. " | N: change level", 20, 50)
end
return LevelLogic
