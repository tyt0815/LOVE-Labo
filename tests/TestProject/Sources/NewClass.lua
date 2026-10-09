-- labo-script: lobject
local Engine = require("Engine")
local NewClass = {}
-- 다른 LObject 클래스를 상속하려면 .lua.meta의 ID를 지정한다.
-- NewClass.extends = "부모 클래스 ID"
-- 이 선언에 포함된 값만 Inspector에 표시되고 Prefab/레벨에 저장된다.
NewClass.properties = {
    displayName = {type = "string", default = "예제 오브젝트"},
    speed = {type = "number", default = 100},
    enabled = {type = "boolean", default = true},
    -- 배치한 인스턴스에서 같은 레벨의 다른 인스턴스를 선택한다.
    target = {type = "object", default = false},
}

-- 에디터 미리보기와 Play에서 같은 컴포넌트 구성을 만든다.
function NewClass.build(self)
    -- 일반 필드는 Inspector에 노출되지 않으며 저장되지 않는다.
    self.internalLabel = "코드에서만 사용하는 값"
    self.elapsedTime = 0
    self.accumulatedDistance = 0

    -- SpriteComponent를 루트로 사용한다. 루트 Transform은 인스턴스 Transform과 같다.
    self:setRootComponent("sprite", Engine.SpriteComponent)
end

-- Runtime LObject가 생성될 때 초기화하는 동작을 작성한다.
function NewClass.beginPlay(self, world)
    self.elapsedTime = 0
    self.accumulatedDistance = 0
    -- Inspector의 target 값은 이 시점에 실제 Runtime LObject로 연결되어 있다.
    self.linkedObject = self.properties.target or nil
end

-- Runtime LObject의 매 프레임 동작을 작성한다. dt는 초 단위다.
function NewClass.update(self, dt)
    if self.properties.enabled then
        self.elapsedTime = self.elapsedTime + dt
        self.accumulatedDistance = self.accumulatedDistance + self.properties.speed * dt
    end
end

return NewClass
