# 0098. 편집 실패 경계·Prefab 배치와 네이티브 크기 조절을 보완한다

- 상태: 채택·구현
- 날짜: 2026-10-18
- 확장: [0083 창 제어](0083-editor-window-controls-in-menu-bar.md), [0085 공개 배치 API](0085-public-projection-layout-and-input.md), [0066 참조 복구](0066-central-asset-catalog-and-reference-repair.md), [0091 실패 정리](0091-loading-validation-and-failure-cleanup.md), [0094 미리보기 소유권](0094-editor-preview-ownership-and-prefab-lists.md)
- 기존 공개 API·저장 형식·플러그인 계약·편집 조작을 유지한다.

## 배경과 제약

Game View·Preview 등의 단일 pop은 사용자 draw의 미회수 push를 소비하여 보호 프레임을 남겼다. 입력 중 hitTest·배치 제공자 예외도 에디터 밖으로 전파되었다. Prefab 내부 부모 변경은 앵커를 제외한 저장 Transform만 합성했다. 사용처 검사는 읽기 실패를 미사용으로 취급했고, --step-dt는 JSON 요청에서만 동작했다.

Windows 창은 모서리 hit-test를 제공하지만 WS_THICKFRAME을 제거하여 실제 드래그 크기 조절을 잃었다. 기존 네이티브 검증은 콜백과 SDL_SetWindowSize만 검사하여 이 차이를 놓쳤다.

## 대안과 판단 기준

- 출력마다 복구 루프를 복사하면 실패 규칙이 다시 갈라진다. 공용 그래픽 스코프에서 복구하고 오류는 소비자에게 전달한다.
- Root 전체의 오류를 삼키기보다 사용자 평가가 포함된 Scene 편집 작업을 보호하고 실패한 제스처를 복원한다.
- Prefab에 플러그인별 계산을 추가하지 않고 기존 Level·AuthoringLayout의 공개 제공자·역변환을 재사용한다. 임시 평가에 게임 load는 필요하지 않다.
- 사용처 목록과 조사 오류를 구별하여 삭제가 불완전한 조사에 의존하지 않게 한다.
- 수동 리사이즈나 기본 제목 표시줄 복원 대신 네이티브 sizing 스타일을 유지한다. Microsoft의 [창 스타일 계약](https://learn.microsoft.com/en-us/windows/win32/winmsg/window-styles)에서 WS_THICKFRAME은 크기 조절 테두리를 제공한다.

## 결정 및 근거

1. 내부 core.GraphicsScope.call은 그래픽 프레임을 시작하고 성공·실패 모두 진입 깊이까지 회수한다. 첫 두 반환값 또는 오류를 전달한다. Renderer는 각 Script의 변환·draw를 보호하고 Rendering.withScreen·Pipeline·GameView·SceneView·drawEditor·Preview PNG가 같은 규칙을 사용한다. Engine 공개 API는 늘리지 않는다.
2. SceneView.interact는 입력·프레이밍·참조 선택의 오류를 받아 드래그 시작 Transform·선택·시점을 복원한다. 실패한 복제는 추가 객체를 제거한다. EditorApp은 기존 오류 로그를 사용하고 캡처를 해제한다. 다중 Level 재부모화도 일부 객체만 변경된 채 남기지 않는다.
3. PrefabTreeEdit은 임시 Level에 Prefab을 구체화하고 AuthoringLayout과 Level.setWorldPosition으로 새 부모 기준 오프셋을 계산한다. 성공·실패 모두 임시 바인딩을 폐기한다. 실패는 초안·선택을 원복한다. 같은 부모 안의 순서 변경에는 역변환을 요구하지 않는다.
4. AssetRepair.usage는 조사 불가 시 nil,error를 반환한다. Repair와 일반 missing 등록 삭제가 모두 오류를 표시하며 기존 목록을 유지한다. 이미 missing으로 확인한 파일 부재는 조사에서 제외한다.
5. 기존 level.events의 step-dt JSON 필드를 명령줄에서도 허용하고 parser부터 전환까지 검증한다.
6. WindowFrame은 WS_CAPTION을 제거하고 WS_THICKFRAME·시스템 메뉴·최소화·최대화를 유지한다. SDL hit-test·최대화 작업 영역 보정·DWM 모서리 정책은 유지한다.
7. --verify-window는 실제 네 모서리의 hit-test와 SendInput 누름·이동·해제를 검사한다. Windows 이동 루프가 주 스레드를 점유하므로 검증 전용 LÖVE 스레드가 포인터를 움직이고 해제한다. 포인터와 창 위치·크기를 복원한다. 대화형 데스크톱 접근이 필요하며 일반 제품 실행에는 주입 스레드를 시작하지 않는다.

```text
출력 소비자 ──의존──> GraphicsScope (스택 복구 소유)
EditorApp ──의존──> SceneView.interact (제스처·선택 복원)
PrefabTreeEdit ──일시 소유──> Level + AuthoringLayout ──의존──> 공개 Transform 제공자
Repair·일반 삭제 ──의존──> usage의 참조 목록 / 조사 오류
WindowFrame ──소유──> SDL hit-test·Win32 창 스타일
WindowVerification ──일시 소유──> 포인터 주입 스레드
```

새 상속 관계는 없다. Core는 Editor에 의존하지 않는다.

## 예상 결과

- 긍정: 사용자 코드 오류 뒤 편집을 계속하고 Prefab의 유효 위치와 ID 복구 가능성을 보존한다. 네 모서리 드래그 리사이즈가 동작한다.
- 부정: Prefab 부모 변경에 임시 저작 그래프 평가 비용이 추가된다. 실제 포인터 검증은 데스크톱 접근 권한이 필요하다.
- 중립: 게임 attachTo의 로컬 Transform 유지, 파일 버전·GUI 조작은 유지한다. 진입 이전 스택의 pop이나 사용자 파일·전역 상태 부작용까지 복원하는 샌드박스는 추가하지 않는다.
