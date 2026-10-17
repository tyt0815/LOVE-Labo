# 0094. 편집 미리보기의 폐기 책임과 Prefab 목록 검증을 완성한다

- 상태: 채택·구현
- 날짜: 2026-10-17
- 확장: [0028 공용 로딩·CLI](0028-agent-cli-and-standalone-game-export.md), [0085 공개 배치 API](0085-public-projection-layout-and-input.md), [0091 준비·그래픽 상태 정리](0091-loading-validation-and-failure-cleanup.md), [0093 호스트 경계](0093-shared-script-and-host-boundaries.md)
- 기존 결정을 대체하지 않고 편집 Scene과 Inspector에서 빠진 보호·폐기 경계를 구체화한다.

## 배경과 제약

Scene View가 실행하는 사용자 draw·배치 제공자 오류가 에디터 UI까지 전파되고 바깥 그래픽 스택을 남겼다. Inspector는 configure 바인딩을 만들지만 대상 교체·재구성·부분 실패와 임시 검사에서 이를 폐기하지 않았다. Prefab의 children·bindings·removedPaths는 table 여부만 확인하여 문자열 키나 구멍 뒤 항목을 무시했다.

게임 공개 API·정상 저장 데이터·편집 문서를 유지한다. Core의 Editor 독립성, load 전에는 게임 unload 콜백을 실행하지 않는 계약을 지킨다. 사용자 Lua의 임의 전역·파일 부작용을 되돌리는 기능은 추가하지 않는다.

## 대안과 판단 기준

- Renderer에서 모든 오류를 삼키면 게임 실행의 실패 보고 의미가 바뀐다. 상태를 시작한 SceneView가 복원하고 EditorApp이 오류를 기록한다. 편집 draw를 끄면 현재 미리보기 기능을 잃는다.
- 에디터 전체에 pcall만 추가하면 남은 그래픽 스택을 복구하지 못한다. SceneView 진입 깊이를 기록하고 자신이 시작한 상태와 그 안에서 남은 스택을 복원한다.
- 전역 PreviewManager나 새 상속 계층보다 팩터리의 실패 정리와 성공 대상의 작은 release 계약이 소유권을 직접 드러낸다. 개별 소비자가 스크립트를 순회하지 않고 기존 ScriptHost.unload를 재사용한다.
- GUI·CLI·Export마다 Prefab 목록을 검사하면 판정이 갈라진다. 공용 Prefab.decode에서 기존 core.Array.isDense를 적용한다. 정상 nil·빈 목록은 허용한다.

## 결정 및 근거

1. SceneView.draw는 편집 렌더링을 보호 구간에서 실행하고 그래픽 스택을 진입 깊이까지 복구한 뒤 오류를 전달한다. EditorApp은 오류를 로그에 기록하며 나머지 UI를 계속 그린다. 동일한 오류가 계속 표시되는 프레임은 중복 기록하지 않으며 정상 프레임 뒤 다시 실패하면 새 오류로 기록한다.
2. ObjectDefinition.inspectorTarget은 부분 구성 실패 시 생성한 호스트를 unload한다. 성공 대상은 release 메서드를 제공하며 호출자가 소유한다. release는 중복 호출할 수 있고 게임 load를 시작하지 않은 대상에서는 configure 바인딩만 정리한다.
3. ClassInspector는 현재 미리보기 대상을 소유하고 교체·재구성·선택 해제 시 폐기한다. ScopeInspector가 같은 대상 테이블을 갱신하기 전에 이전 preview를 정리한다. 재구성 실패 시 이전 프로퍼티 행을 제거하고 오류를 표시하며 다음 재구성을 허용한다. 에디터 종료도 현재 Inspector와 Scene 캐시를 정리한다.
4. ClassTree·Prefab 캡처/복제·배치/스포이드·부모 기본값 검사 등 임시 소비자는 사용 후 대상을 폐기한다. CLI는 호출별 정리 목록에 각 대상을 등록하여 성공·중간 실패 모두 폐기한다. 기존 명령·응답 필드는 유지한다.
5. Prefab.decode는 루트·중첩 children 및 removedPaths, 루트 bindings를 연속 배열로 검사한다. previewBackground도 정확한 RGB 배열이어야 한다. 잘못된 목록 오류에는 필드 위치를 포함한다. 객체 참조와 에셋 해석은 기존 계층 해결·로딩 검증의 책임이다.

```text
EditorApp ──의존·오류 기록──> SceneView ──시작·복구──> 편집 그래픽 상태
ObjectDefinition ──생성·실패 폐기──> Inspector target ──포함──> preview ScriptHost
ClassInspector ──소유·교체 폐기──> Inspector target ──release 의존──> ScriptHost.unload
임시 검사·CLI 호출 ──일시 소유·완료 폐기──> Inspector target
GUI·CLI·Export ──의존──> Prefab.decode ──의존──> core.Array.isDense
```

새 상속·인터페이스 구현 관계는 없다.

## 예상 결과

- 긍정: 사용자 미리보기 오류 뒤에도 편집·로그 확인을 계속하며 그래픽 상태와 바인딩 수명을 유지한다. 잘못된 Prefab 목록을 조용히 축소하지 않는다.
- 부정: 과거 일부 항목을 무시하던 비정상 Prefab은 이제 오류가 된다. 내부 Inspector 대상 소비자는 사용 완료 시 release해야 한다.
- 중립: 파일 버전·게임 공개 API·CLI 명령과 조작 단계는 유지한다. 사용자 코드가 SceneView 진입 이전의 그래픽 스택을 직접 pop하거나 그래픽 객체를 파괴한 경우까지 복구하는 샌드박스는 아니다.
