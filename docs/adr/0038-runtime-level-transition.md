# 0038. 프레임 경계의 런타임 레벨 전환

- 상태: 채택
- 날짜: 2026-10-09
- 관련: [ADR 0033](0033-prefab-spawn-and-resource-inspector.md)의 프로젝트 로더 주입, [ADR 0028](0028-agent-cli-and-standalone-game-export.md)의 독립 게임 호스트

## 배경과 제약

프로젝트 Lua 코드에서 레벨 1에서 레벨 2로 전환해야 한다. Editor Play와 독립 Export 게임에서 같은 API를 제공하고 현재 update 순회와 미저장 편집 문서를 오염시키지 않아야 한다. 다른 레벨의 파일도 현재 게임 패키지에 포함된다.

## 대안과 판단 기준

- update 안에서 World를 즉시 교체하면 진행 중인 객체 목록과 콜백이 섞인다. 현재 프레임 완료 후 호스트가 교체한다.
- 기존 World를 먼저 버리면 대상 로드·초기화 실패 시 복귀할 수 없다. 후보 World를 준비하고 beginPlay까지 성공한 경우에만 교체한다.
- Core에서 파일·프로젝트 구현을 참조하면 Editor 비의존성이 깨진다. World는 주입받은 요청 함수를 호출하고 runtime LevelTransition이 프로젝트 참조와 파일을 처리한다.

## 결정 및 근거

1. 공개 API는 `world:openLevel(reference)`와 `Engine.openLevel(world, reference)`다. 프로젝트 상대 `.level` 경로와 에셋 ID를 받는다. 반환값 `true`는 전환 요청 접수이며 즉시 전환 완료를 뜻하지 않는다. 잘못된 참조·파일·구조·프로퍼티는 `false, error`를 반환한다.
2. 요청 시 후보 World의 구성과 참조를 준비하되 beginPlay는 실행하지 않는다. 같은 World에 이미 요청이 대기하면 추가 요청을 거절한다. 후보의 build는 한 번만 실행한다.
3. 현재 World의 프레임 update가 정상 완료한 뒤 Editor/게임 Host가 `takeLevelTransition()`으로 후보를 초기화한다. 성공한 후보는 elapsedTime 0에서 시작하며 대상 `levelReference`를 가진다. 다음 update부터 새 레벨을 갱신한다.
4. 초기화 실패 시 기존 World를 유지하고 `world.levelTransitionError`에 오류를 남긴다. 호스트도 오류를 표시한다. 기존 레벨의 다음 프레임과 재요청은 가능하다.
5. Editor의 열린 authoring 문서는 바뀌지 않는다. Stop Play는 기존 편집 레벨로 돌아간다. Runtime 상태·객체 참조는 레벨 간 자동 전달하지 않는다.

## 관계

```text
호출 의존: 프로젝트 Lua → Engine / World.openLevel
주입: World ← runtime.LevelTransition ← 프로젝트 파일 로더
초기화 의존: LevelTransition → WorldLoader.prepare / activate
소유·교체: Editor Play / 게임 Host → 현재 World → 성공한 후보 World
```

## 예상 결과

- 긍정: 에디터와 배포 게임에서 같은 레벨 전환이 동작하며 실패 시 현재 게임을 유지한다.
- 부정: 동기 준비가 프레임 시간을 소비할 수 있다. 사용자 build·beginPlay의 파일·전역 상태 등 외부 부작용까지 되돌리지는 않는다.
- 중립: 비동기 로딩, 페이드, persistent 게임 상태, 레벨 스트리밍, 새 Level 프로퍼티 타입은 포함하지 않는다.
