"""기존 프로젝트에 공용 Script·고정 업데이트 예제를 CLI로 추가한다. 동명 에셋은 덮어쓰지 않는다."""
import json
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
PROJECT = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else ROOT / "tests/TestProject"
REQUEST = ROOT / "build/scope-example-request.json"
REQUEST.parent.mkdir(exist_ok=True)


def run(command, **fields):
    REQUEST.write_text(json.dumps(dict(command=command, project=str(PROJECT), **fields), ensure_ascii=False), encoding="utf-8")
    result = subprocess.run(["C:/Program Files/LOVE/lovec.exe", "src", "--cli", "--request", str(REQUEST)],
                            cwd=ROOT, capture_output=True, text=True, encoding="utf-8")
    response = [json.loads(line) for line in result.stdout.splitlines() if line.startswith("{")]
    if result.returncode or not response or not response[-1]["ok"]:
        raise RuntimeError(response[-1] if response else result.stdout + result.stderr)
    return response[-1]["result"]


SOURCES = {
    "ScopeSession": '''local Session = {properties = {
    visits = {type = "number", default = 0, group = "Session"},
    frames = {type = "number", default = 0, group = "Session"}
}}
function Session:load() self.token = love.math.random(1000, 9999) end
function Session:update(dt) self.frames = self.frames + 1 end
function Session:drawScreen(context)
    local world = self:getWorld()
    if not world or not world:getScriptByName("scopeLevel") then return end
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.print("Project token " .. self.token .. " | visits " .. self.visits .. " | frames " .. self.frames, 20, 20)
end
return Session
''',
    "ScopeLevel": '''local LevelLogic = {properties = {
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
''',
    "FixedActor": '''local Bounds = require("Engine").Bounds
local Actor = {properties = {speed = {type = "number", default = 2, group = "Motion"}}}
Actor.getBounds, Actor.hitTest = Bounds.getBounds, Bounds.hitTest
function Actor:load() self.elapsed, self.priority = 0, 10 end
-- update는 선언하지 않는다. Level Script가 이 일반 메서드를 직접 호출한다.
function Actor:fixedUpdate(dt)
    self.elapsed = self.elapsed + dt
    self.owner.transform.x = math.sin(self.elapsed * self.speed) * 180
end
function Actor:draw(context)
    love.graphics.setColor(0.15, 0.8, 0.9, 1)
    love.graphics.circle("fill", 0, 0, 20)
end
function Actor:drawScreen(context)
    love.graphics.setColor(0.15, 0.8, 0.9, 1)
    love.graphics.print("Object drawScreen: fixed on screen while the circle moves", 20, context.viewport.height - 35)
end
function Actor:getLocalBounds() return -20, -20, 40, 40 end
function Actor:drawEditor(context) context:bounds(self) end
return Actor
''',
}

assets = run("project.info")["assets"]
for name in SOURCES:
    if f"Assets/Examples/{name}.lua" in assets:
        raise SystemExit(f"Example already exists: {name}")
for name in ("L_ScriptScopes", "L_ScriptScopesNext"):
    if f"Assets/Examples/{name}.level" in assets:
        raise SystemExit(f"Example already exists: {name}")

ids = {}
if not (PROJECT / "Assets/Examples").is_dir():
    run("folder.create", folder="Assets", name="Examples")
for name, source in SOURCES.items():
    ids[name] = run("script.create", folder="Assets/Examples", name=name)["assetId"]
    run("script.set-source", script=ids[name], source=source)
run("project.script.add", source=ids["ScopeSession"], script="scopeSession")
levels = []
for name in ("L_ScriptScopes", "L_ScriptScopesNext"):
    levels.append(run("level.create", folder="Assets/Examples", name=name, empty=True)["assetId"])
for index, level in enumerate(levels):
    run("level.script.add", level=level, source=ids["ScopeLevel"], script="scopeLevel")
    run("level.script.set", level=level, property="scopeLevel.nextLevel", value=levels[1 - index])
    run("level.script.set", level=level, property="scopeLevel.levelTitle", value="First level" if index == 0 else "Second level")
    run("instance.add", level=level, script=ids["FixedActor"], name="Fixed actor", x=0, y=0)
    result = run("level.simulate", level=level, frames=3, dt=1 / 30)
    assert len(result["instances"]) == 1
print("Created scope examples: " + ", ".join(levels))
