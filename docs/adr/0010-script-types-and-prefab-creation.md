# 0010. Lua 종류 선택과 스크립트 기반 Level·Prefab 생성

- 상태: 채택
- 날짜: 2026-10-08
- 부분 대체: [ADR 0008](0008-context-menu-and-project-entries.md)의 수동 Level 생성 시 같은 이름의 Lua 자동 생성
- 확장: [ADR 0007](0007-sources-and-level-scripts.md)의 Level 스크립트 참조와 [설계 문서](../LOVE_Labo_Design.md)의 Prefab

## 배경과 제약

Lua 생성 시 Level Script와 LObject Script를 구분하고 Level·Prefab 생성 시 해당 종류의 기존 스크립트를 고를 수 있어야 한다. Prefab은 새로운 Actor 객체 타입이 아니라 Project Lua의 LObject Definition을 참조하는 데이터 변형 에셋이다. 소스 선택 목록을 만들기 위해 임의 프로젝트 코드를 실행하지 않는다. 기존 프로젝트의 표식 없는 Level 코드와 새 프로젝트의 StartLevel 자동 생성은 유지한다.

## 대안과 판단 기준

- 폴더 이름으로 종류를 추론하면 소스 이동에 따라 의미가 바뀐다.
- 별도 sidecar 메타 파일은 소스 이동·복사 시 함께 관리해야 한다.
- Lua 반환 테이블을 실행해서 종류를 읽으면 목록 표시만으로 코드의 부작용이 생긴다.
- 첫 줄의 종류 표식은 소스와 함께 이동하며 코드를 실행하지 않고 읽을 수 있다. 기존 표식 없는 코드는 Level로 분류하여 호환성을 유지한다.
- 수동 Level 생성 시 같은 이름의 Lua를 자동 생성하면 이미 작성한 공통 동작을 재사용하기 어렵다. 명시적으로 기존 스크립트를 선택하여 참조한다.

## 결정 및 근거

1. Sources의 Lua 생성 창에서 Level Script 또는 LObject Script를 고른다. 첫 줄에 `-- labo-script: level` 또는 `-- labo-script: lobject`를 기록하고 종류별 템플릿을 사용한다. Level 템플릿의 기존 `load(world)`·`update(world, dt)`는 유지한다. LObject 템플릿은 `load(self, world)`·`update(self, dt)` 정의 틀을 제공한다.
2. 첫 줄 표식이 없는 Lua는 기존 Level Script로 취급한다. 알 수 없는 종류 표식은 오류다. 종류는 헤더에서만 읽으며 소스를 컴파일·실행하지 않는다. Sources 하위 폴더를 재귀 탐색하고 링크는 따라가지 않는다. 선택과 파일 생성 시에도 경로·존재·종류를 다시 검사한다.
3. Assets의 New 메뉴에 Prefab을 추가한다. Level 생성 창에는 Level Script만, Prefab 생성 창에는 LObject Script만 표시한다. 이름과 스크립트를 선택해 생성하며 맞는 종류의 스크립트가 없으면 생성하지 않는다. 선택 목록은 스크롤과 방향키를 지원하고 Tab으로 이름·목록 입력을 전환한다.
4. 수동 `.level` 생성은 기존 JSON 형식의 `scriptReference`에 선택한 Level Script를 저장한다. 추가 Lua를 생성하거나 선택한 Lua를 수정하지 않는다. 새 프로젝트는 기존처럼 StartLevel.level과 StartLevel.lua를 함께 생성한다.
5. `.prefab`은 `formatVersion: 1`, `definitionReference`, `overrides`가 있는 JSON 에셋이다. `definitionReference`는 선택한 LObject Lua의 canonical Sources 상대 경로다. 초기 `overrides`는 빈 객체이며 Definition 기본값을 덮어쓰지 않는다. Prefab 상속·중첩·Component override 해석은 현재 구현에 추가하지 않는다.
6. Level Play 로더는 LObject Script를 Level 코드로 실행하지 않는다. Prefab 파일 생성·참조 저장과 LObject 코드 템플릿을 제공하며, Prefab 편집·레벨 배치·Runtime Definition 바인딩은 이후 해당 흐름을 구현할 때 연결한다. Core에는 Editor 파일시스템이나 생성 UI 의존성을 추가하지 않는다.

## 예상 결과

- 긍정: 종류에 맞는 소스를 골라 여러 Level·Prefab에서 재사용할 수 있다. 목록 탐색에 코드 실행 부작용이 없고 기존 Level 프로젝트도 동작한다.
- 부정: 수동으로 만드는 새 LObject 코드는 종류 표식을 작성해야 한다. 표식이 없는 Lua는 호환성을 위해 Level로 분류하므로 모든 코드의 의도를 자동 판별하지는 않는다.
- 중립: StartLevel 초기 생성과 기존 `.level` 버전은 유지한다. Prefab은 LObject Definition의 데이터 에셋이며 Runtime 객체 종류를 추가하지 않는다.
