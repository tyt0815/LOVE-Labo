-- 기존 입력 회귀 사례의 콜백을 명시적인 공개 등록 API에 연결한다.
local Engine = require("Engine")
local Fixture = {}
function Fixture.bindWorld(world)
    local hosts = world:getObjects(); hosts[#hosts + 1] = world
    if world.project then hosts[#hosts + 1] = world.project end
    for _, host in ipairs(hosts) do
        for _, id in ipairs(host.scriptOrder) do
            local script = host.scripts[id]
            if not script.region and not script.fixtureRegion and (script.onPointerDown or script.onPointerUp or script.onPointerMove or script.blockPointer or script.boundsSource ~= nil) then
                script.fixtureRegion = Engine.Input.registerRegion(world, {owner = script,
                    hitTest = function(context, x, y) return script:hitTest(context, x, y) end,
                    filterSource = function() return script:getBoundsSource() end,
                    order = function() return script:getBoundsSource().drawOrder end,
                    priority = function() return script.inputPriority or 0 end,
                    block = function() return script.blockPointer or false end,
                    onDown = function(event) if script.onPointerDown then return script:onPointerDown(event) end end,
                    onUp = function(event) if script.onPointerUp then return script:onPointerUp(event) end end,
                    onMove = function(event) if script.onPointerMove then return script:onPointerMove(event) end end})
            end
        end
    end
    return world
end
return Fixture
