# 0007. Sources 탐색과 레벨 Lua 스크립트 연결

- 초기 소스 생성과 클래스·프로퍼티 계약은 [ADR 0012](0012-lua-classes-properties-and-unsaved-levels.md)로 부분 대체

- 상태: 채택
- 날짜: 2026-10-08
- 부분 대체: [ADR 0002](0002-project-launcher-and-assets.md)의 Assets 전용 탐색·빈 메모리 레벨 시작
- 확장: [ADR 0005](0005-default-level-on-project-creation.md)의 초기 파일과 [ADR 0006](0006-widget-canvas-and-asset-views.md)의 브라우저 UI

## 배경과 제약

사용자가 Assets·Sources 두 루트 탐색, 클릭 가능한 경로, 도구 위치 변경과 Default Level에서 실행할 Lua 코드 생성을 요청했다. `.level`과 Lua의 연결은 데이터와 동작의 책임을 분리해야 한다. 기존 레벨·프로젝트 형식과 Edit/Runtime 분리, 한글 프로젝트 경로를 유지한다.

## 대안과 판단 기준

- 같은 파일 이름만으로 코드를 추론하면 연결 정보가 저장되지 않고 파일 이동·이름 변경에 취약하다.
- Lua 안에 배치 데이터까지 두면 시각적 편집 데이터의 원본이라는 `.level`의 책임이 바뀐다.
- `.level`이 명시적인 프로젝트 상대 소스 참조를 저장하면 여러 레벨이 같은 코드를 공유할 수 있고 배치 데이터는 독립적으로 유지된다.
- LÖVE 전역 callback을 프로젝트 코드가 소유하면 호스트 에디터의 생명주기와 충돌한다. 반환된 모듈의 레벨 callback을 Runtime World가 호출한다.

## 결정 및 근거

1. 새 프로젝트에 `Assets/Levels/StartLevel.level`과 `Sources/Levels/StartLevel.lua`를 생성한다. 생성은 기존 파일을 덮어쓰지 않으며 중간 실패 시 이번 생성의 파일·빈 폴더를 역순으로 정리한다.
   초기 파일명은 사용자 요청에 따라 `Default`에서 `StartLevel`로 변경했다. 기존 프로젝트는 저장된 참조를 그대로 사용하며 파일명을 자동 변경하지 않는다.
2. 레벨 JSON에 선택적인 `scriptReference`를 추가한다. 값은 canonical `Sources/.../*.lua` 상대 경로다. 기본 레벨은 기본 Lua를 참조한다. 레벨은 배치 데이터의 원본이며 Lua는 레벨의 동작을 담당한다. 기존 스크립트 없는 레벨을 허용하므로 `formatVersion: 1`을 유지한다.
3. 프로젝트 정보에 선택적인 `defaultLevelReference`를 저장하고, 지정된 레벨을 에디터 진입 시 연다. 지정된 레벨이 잘못됐거나 읽히지 않으면 시작 화면에 오류를 표시한다. 지정이 없는 기존 프로젝트는 기존 빈 메모리 Level 동작을 유지한다. 기존 프로젝트를 열 때 파일을 자동 생성하거나 수정하지 않는다.
4. Lua 파일은 `load(world)`와 `update(world, dt)` 함수가 있는 테이블을 반환한다. 두 함수는 생략할 수 있다. Play마다 소스를 새로 컴파일·실행하여 모듈과 전역 쓰기 영역을 만든다. `load` 후에만 새 Runtime을 에디터에 적용하며 `update`는 LObject 업데이트 전에 호출한다. 명시적 `false` 반환과 예외는 실패다. 실패는 에디터에 표시하며 시작 실패는 Runtime을 적용하지 않고 실행 중 실패는 Runtime을 폐기한다.
5. 호스트 파일 읽기·컴파일은 Editor에, callback 호출은 Core World에 둔다. Core는 Editor 파일시스템에 의존하지 않는다. 프로젝트 Lua는 신뢰하는 코드이며 새로운 전역 쓰기 영역은 완전한 VM/프로세스 샌드박스가 아니다. Project 모듈 discovery·require 경로·Public facade 확장은 이번 구현에 포함하지 않는다.
6. 브라우저에 Assets·Sources를 별도 루트로 표시한다. Sources 없는 기존 프로젝트에서는 빈 Sources 루트를 보여준다. 두 루트 밖의 참조와 경로 segment의 링크·연결점은 탐색·스크립트 로딩에서 거부한다. 기존 `listAssets`는 Assets 전용 계약을 유지하고 공통 탐색은 `listDirectory`로 제공한다.
7. 트리 펼침은 오른쪽·아래쪽 chevron을 사용한다. Up 버튼은 제거하고 파일 영역 위의 Breadcrumb 위젯에서 상위 경로를 클릭한다. 보기 드롭다운은 우측 Refresh 바로 왼쪽에 둔다. `.level` 더블클릭은 기존 문서 열기를 사용하며 저장하지 않은 변경은 폐기하지 않는다.
8. Level 파일 읽기·임시 저장·교체·복구는 Windows에서 Unicode 호스트 API를 사용하여 자동 열린 한글 프로젝트도 저장할 수 있게 한다. 다른 OS는 기존 Lua 파일 접근 방식을 유지한다. 정상 파일 보존과 `.tmp`·`.bak` 복구 순서는 유지한다.

## 예상 결과

- 긍정: 기본 레벨의 배치 데이터와 실행 코드가 명시적으로 연결되고, 소스 탐색·경로 이동·Play 재실행 흐름이 생긴다. Runtime 변경은 authoring 데이터와 분리된다.
- 부정: 잘못된 소스 참조·문법·callback 오류를 처리해야 한다. 코드를 수정한 후에는 Stop/Play로 다시 읽어야 한다.
- 중립: 게임 특화 기능은 기본 코드에 추가하지 않는다. Lua 편집은 외부 도구를 사용한다. 기존 프로젝트·레벨은 기본 레벨이나 Sources를 강제로 갖지 않아도 된다.
