# Lua 레벨 전환

부착 Script에서는 `self:getWorld():openLevel(reference, options)`로 레벨 전환을 요청합니다. `require("Engine").openLevel(world, reference, options)`도 같은 경로를 사용합니다. 참조는 `.level` 에셋 ID 또는 프로젝트 상대 경로입니다.

```lua
local Portal = {}
function Portal:update(dt)
    if not self.shouldTravel then return end
    local accepted, err = self:getWorld():openLevel("Assets/Levels/L_Stage2.level")
    if accepted then self.shouldTravel = false
    else self.travelError = err end
end
return Portal
```

`true`는 요청 접수이며 한 World에서 한 요청만 대기할 수 있습니다. 현재 프레임의 업데이트가 끝난 뒤 후보 World를 준비하고 Script의 load까지 성공해야 교체합니다. 즉시 검증 실패는 `false, error`, 접수 뒤 초기화 실패는 `world.levelTransitionError`로 확인합니다. 실패하면 기존 레벨을 유지합니다. 일반 Script에 build 콜백을 추가하지 않습니다.

옵션을 생략하면 새 World·LObject·Script와 elapsedTime 0으로 시작하며 이전 오브젝트 참조나 프로퍼티를 자동 전달하지 않습니다. Project Script는 같은 인스턴스를 유지합니다. 새 레벨의 update는 다음 프레임부터 실행합니다.

```lua
local world = self:getWorld()
local accepted, err = world:openLevel(destinationId, {carry = {player}})
```

carry에 지정한 오브젝트·자손·부착 Script는 같은 인스턴스로 이동합니다. load/unload를 반복하지 않고 `worldChanged(previousWorld, nextWorld)`를 호출합니다. 소유한 View·입력·렌더 타깃 이동과 실패 복구는 [객체 유지·저장 가이드](game-state.md)를 참고하세요. 사용자 Lua의 파일·전역 변수 등 외부 부작용은 복구 대상이 아닙니다.

Editor Play의 전환은 편집 문서에 저장하지 않으며 Stop은 원래 편집 레벨로 돌아갑니다. 독립 게임 Export도 같은 API를 사용합니다. [ADR 0087](../adr/0087-carried-objects-across-levels.md)에 객체 유지와 전환 경계의 결정을 기록했습니다.
