# 0092. 세션 로더와 실행 실패의 정리 경계를 일치시킨다

- 상태: 채택·구현
- 날짜: 2026-10-17
- 확장: [0069 부착 식별자와 클래스 캐시](0069-script-identity-and-editor-authored-attachments.md), [0074 세션별 공용 Script](0074-scoped-scripts-and-screen-drawing.md), [0087 객체 유지 전환](0087-carried-objects-across-levels.md), [0091 로딩 검증과 정리](0091-loading-validation-and-failure-cleanup.md)
- 기존 결정을 대체하지 않고 구현에서 누락한 공유·정리 경계를 구체화한다.

## 배경과 제약

프로젝트와 플러그인이 별도 모듈 캐시를 사용하면 같은 require 결과의 동일성이 깨지고, 설치 레지스트리의 실행 캐시가 다음 Play에 남는다. 제공 View의 투영 함수도 최초 World를 캡처하여 carry 뒤 비활성화된다. 에디터의 크기·이벤트·휠 입력은 draw와 달리 투영 오류를 격리하지 않았다. Spawn 실패 정리는 배열 길이에 의존하여 초기화 중 기존 객체를 제거하면 생성물이 남았다. Script 목록은 구멍 뒤의 항목을 조용히 버릴 수 있었다. 공개 API·파일 형식과 사용자 편집 흐름은 유지한다.

## 대안과 판단 기준

- 설치 레지스트리의 캐시를 매번 비우면 이미 실행 중인 세션과 검증·미리보기가 간섭한다. 등록 정의·활성 목록을 공유하는 세션별 레지스트리 뷰를 사용한다.
- 프로젝트와 플러그인 캐시를 따로 두고 이름으로 클래스를 비교하면 일반 Lua의 테이블 동일성과 보조 모듈 상태를 보장하지 못한다. 같은 세션의 require와 부착 로더가 캐시를 공유한다.
- View에 전용 Core 이동 예외를 추가하지 않고 제공 Script가 현재 World를 조회한다.
- 각 이벤트에서 투영 예외 처리를 반복하지 않고 EditorApp의 보호된 viewport 조회를 공유한다.
- Spawn 중 기존 객체 제거를 금지하면 게임 코드의 구성 자유도가 줄어든다. 시작 시 살아 있던 객체의 집합과 실패 시 목록을 비교하여 새 객체만 정리한다.
- Script 목록에 별도 배열 검증을 유지하지 않고 core.Array.isDense를 사용한다.

## 결정 및 근거

1. LuaScript.moduleLoader는 PluginRegistry.forProject로 세션 뷰를 만들고 그 뷰에 require·모듈 로더를 연결한다. LuaScript.loader는 같은 뷰에 클래스 로더를 연결한다. 플러그인의 에셋 ID·별칭·require와 프로젝트 부모 상속은 이 세션의 캐시를 공유한다. WorldLoader는 기존 Project 호스트의 로더를 유지하여 레벨 전환·Spawn에도 같은 클래스가 사용되게 한다. 새 Play·검증·CLI 로더는 새 실행 캐시를 사용한다.
2. 제공 View는 투영 함수에서 self:getWorld()와 Camera의 현재 소속을 비교한다. 성공한 이동과 실패 복구 모두 등록 인스턴스를 재생성하지 않는다.
3. EditorApp.runtimeViewport는 사용자 투영 평가를 보호하고 실패하면 discardRuntime으로 실행 자원을 정리한다. 크기 갱신·이벤트·휠 입력이 이 경계를 사용한다. GameView.draw의 그래픽 상태 보호는 유지한다.
4. PrefabSpawner는 생성 시작 시 기존 객체의 동일성을 기록하고 실패 시 현재 목록의 새 객체를 역순으로 정리한다. 중첩 Spawn도 포함하며 제거된 기존 객체를 복원하지 않는다. unload 실패가 있어도 나머지 정리를 계속하고 생성 오류와 함께 보고한다. 일반 Lua·파일 부작용 복구는 제공하지 않는다.
5. Script 부착·삭제 ID·정렬 ID 목록은 공통 연속 배열 검사 후 순회한다. nil과 빈 목록의 기존 의미는 유지한다.

```text
설치 PluginRegistry ──정의·활성 목록 공유──> 세션 레지스트리 뷰
LuaScript 로더 ──소유──> 세션 뷰·모듈/클래스 캐시 ←─사용── 프로젝트·플러그인
Project 실행 호스트 ──소유──> 같은 클래스 로더 ←─사용── 전환 World·Spawn
EditorApp ──오류 격리·정리──> 투영 평가·Runtime
PrefabSpawner ──실패 정리──> 이번 호출에서 추가된 객체
ScriptAttachments ──의존──> core.Array.isDense
```

새 상속 계층이나 공개 API는 추가하지 않는다.

## 예상 결과

- 긍정: 모듈 상태·클래스 동일성과 세션 격리가 일치하고, 객체 이동 뒤 제공 View가 유지된다. 투영 오류가 에디터 전체로 전파되지 않으며 Spawn 실패의 부분 객체를 정리한다.
- 부정: Spawn마다 기존 객체 집합을 만드는 비용이 추가된다. 비정상 Script 목록은 일부를 무시하는 대신 오류로 거절한다.
- 중립: 공개 API·정상 저장 데이터·편집 조작은 유지한다. 사용자가 직접 소유한 일반 Lua 상태와 외부 자원을 자동으로 되돌리지는 않는다.
