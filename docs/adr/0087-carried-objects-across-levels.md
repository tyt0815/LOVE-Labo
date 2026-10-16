# 0087. 명시적으로 선택한 LObject 계층을 다음 World로 옮긴다

- 상태: 채택·구현
- 날짜: 2026-10-16
- 부분 대체: [0038](0038-runtime-level-transition.md)의 객체 참조 미전달 정책
- 관련: [0074](0074-scoped-scripts-and-screen-drawing.md), [0085](0085-public-projection-layout-and-input.md)

## 배경과 제약

플레이어·장비·Camera·HUD의 인스턴스와 스크립트 상태를 유지하며 레벨을 바꿔야 한다. Core는 제공 스크립트 역할을 몰라야 하고 실패 시 기존 World를 유지해야 한다. 전환은 update 순회 후 동기 경계에서 수행한다.

## 대안과 판단 기준

- 데이터 복사 후 재생성은 일반 Lua 인스턴스·자원·자손의 동일성을 잃는다.
- 전역 persistent 플래그는 각 전환에서 어떤 객체가 유지되는지 숨긴다.
- 명시적인 carry 배열과 범용 WorldTransfer를 사용한다. 기존 옵션 없는 호출은 객체 전체 교체를 유지한다.

## 결정 및 근거

world:openLevel(reference,{carry={object,...}})와 Engine.openLevel의 세 번째 인자로 이동 대상을 지정한다. 현재 World의 살아 있는 객체만 허용하며 중복과 선택한 조상의 자손은 한 번만 옮긴다. 요청 시 배열을 복사하고 적용 경계에서 생존을 다시 검증한다. 선택한 객체의 당시 자손도 함께 옮긴다.

Core.WorldTransfer가 대상 World의 목록·새 runtimeId를 부여한다. authoringId는 새 레벨의 저작 객체를 나타내지 않으므로 nil로 바꾸고 실패 시 원래 값을 복구한다. Lua 객체·Script 인스턴스와 내부 상태·자손 참조는 유지한다. 선택 루트의 이전 부모는 분리하고 월드 위치를 새 로컬 오프셋으로 역산한다. 로컬 회전·스케일은 유지하며 부모의 회전·스케일 전체를 복제하지는 않는다. 읽기 전용 배치처럼 역산할 수 없는 루트는 전환 오류로 처리한다.

소유 Script가 함께 이동하는 View·Input region·RenderTarget은 같은 인스턴스로 옮긴다. createTarget의 owner 옵션으로 단독 타깃도 수명을 식별한다. 소유자 없는 타깃은 이동하는 View만 참조하는 경우 함께 이동한다. 남는 View와 공유하거나 남는 Script가 소유한 타깃 의존성은 오류로 거절한다. Project Script 소유 등록도 Project 인스턴스와 함께 모든 전환에서 이동한다. 포인터 캡처는 취소한다.

후보 World에 객체와 등록을 연결한 뒤 초기화 전에 worldChanged(previousWorld,nextWorld)를 기존 Script에 알린다. enabled와 무관하게 수명 통지를 수행하며 load·unload는 재호출하지 않는다. 사용자는 이 콜백에서 캐시한 World를 갱신한다. 후보 load는 이동한 객체를 조회할 수 있다. 성공하면 이전 World의 나머지를 정리한다.

실패 시 객체 목록·부모·루트 Transform·ID·기존 등록을 복구하고 후보에서 추가한 등록을 정리한다. 통지를 수행했다면 반대 방향 worldChanged를 호출해 캐시 복원을 돕는다. 후보는 폐기하며 rollback 콜백 오류도 보고한다. 임시 이동 중에는 기존 객체의 제거·재부모화·스크립트 부착 변경과 기존 등록의 release를 금지한다. 일반 Lua 필드·파일 쓰기·사용자 GPU 자원 해제 등 사용자 부작용은 복구하지 않는다. 자동 참조 재작성도 수행하지 않는다.

```text
World.openLevel ──요청 의존──> runtime.LevelTransition
LevelTransition ──의존──> core.WorldTransfer · WorldLoader
WorldTransfer ──임시 소속 이전──> LObject 계층 · 소유된 범용 등록
WorldLoader ──초기화 전 통지──> Script.worldChanged
실패 ──복구──> 기존 World / 성공 ──폐기──> 이전 World의 나머지
```

## 예상 결과

- 긍정: 플레이어·HUD·입력과 일반 스크립트 상태를 재생성 없이 유지한다. GUI·CLI·Export가 같은 전환을 사용한다.
- 부정: 사용자가 저장한 이전 World·남는 객체 참조는 직접 관리해야 하며 콜백의 임의 부작용은 원상 복구할 수 없다.
- 중립: 객체의 디스크 직렬화, 비동기 로딩, 자동 persistent 속성은 추가하지 않는다.
