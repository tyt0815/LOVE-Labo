# Lua 레벨 전환

```lua
local Portal = {}

function Portal.beginPlay(self, world)
    self.world = world
end

function Portal.update(self, dt)
    if self.shouldTravel then
        local accepted, err = self.world:openLevel("Assets/Levels/L_Stage2.level")
        if accepted then self.shouldTravel = false
        else self.travelError = err end
    end
end

return Portal
```

Level 클래스 안에서는 `self:openLevel(reference)`을 사용한다. 공개 모듈의 `require("Engine").openLevel(world, reference)`도 같은 함수다. 참조는 프로젝트 상대 `.level` 경로 또는 에셋 ID다. 한 World에서는 한 요청만 대기할 수 있다.

`true`는 요청 접수다. 현재 프레임의 update가 끝나면 호스트가 후보 레벨의 beginPlay까지 실행하고 성공한 경우에만 교체한다. 즉시 검증 실패는 `false, error`, 접수 후 초기화 실패는 기존 `world.levelTransitionError`로 확인한다. 실패하면 현재 레벨이 계속 실행된다. 후보의 build는 준비 단계에서 한 번 실행하며 beginPlay는 실제 전환 경계에서 실행한다.

새 레벨은 새로운 World·객체·컴포넌트와 elapsedTime 0으로 시작한다. 이전 객체 참조나 프로퍼티는 자동 전달하지 않는다. 새 레벨의 update는 다음 프레임부터 실행된다. 사용자 코드의 파일·전역 상태 등 외부 부작용은 실패 복구 대상이 아니다.

Editor Play 중 전환은 편집 문서에 저장되지 않는다. Stop Play는 원래 편집 레벨로 돌아간다. 독립 게임 Export도 같은 API를 지원하고 등록된 레벨 파일을 패키지에서 읽는다.
