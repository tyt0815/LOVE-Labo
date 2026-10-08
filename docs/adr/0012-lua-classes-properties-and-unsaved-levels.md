# 0012. Lua Class 상속·프로퍼티와 저장 전 레벨 문서

- 상태: 채택
- 날짜: 2026-10-08
- 대체: [ADR 0005](0005-default-level-on-project-creation.md)의 기본 레벨 자동 생성
- 부분 대체: [ADR 0007](0007-sources-and-level-scripts.md)의 초기 소스 생성, [ADR 0010](0010-script-types-and-prefab-creation.md)의 필수 부모 선택·Prefab 생성 전용 범위
- 유지: [ADR 0011](0011-asset-ids-metadata-and-path-cache.md)의 메타 ID 원본과 재생성 가능한 경로 캐시

## 배경과 제약

새 프로젝트에 초기 레벨과 소스를 자동 생성하지 않고 빈 문서를 편집하다 첫 저장에 파일을 생성한다. 사용자는 Lua Class끼리의 상속, Level·Prefab에서 부모 클래스 선택·해제, 기본 타입 프로퍼티의 인스펙터 편집을 요구했다. 기존 Level callback과 메타 종류·ID 참조는 보존해야 하며 Editor 파일 로더가 Core로 들어가서는 안 된다.

## 대안과 판단 기준

- 초기 파일을 유지하면 빈 프로젝트와 저장 전 문서를 구분할 수 없다. 빈 Assets·Sources와 메모리 문서를 사용한다.
- 단순 callback 연결만 클래스라고 부르면 요청한 상속과 프로퍼티 기본값을 제공하지 못한다. 종류별 단일 상속과 명시적 선언을 제공한다.
- 경로 기반 `extends`는 이동 시 코드 재작성이 필요하다. 부모 에셋 ID는 이동에도 유지된다.
- 프로퍼티 선언을 별도 JSON에 중복하면 Lua와 메타의 기본값이 어긋난다. Lua가 선언의 원본이고 JSON 에셋에는 덮어쓴 값만 저장한다.
- Lua 텍스트의 일부만 정규식으로 파싱하면 실제 Lua 선언을 일관되게 해석할 수 없다. 목록은 메타만 읽되 인스펙터의 명시적 대상 선택과 Play에서는 모듈을 로드한다. 최상위 부작용을 막는 보안 VM은 제공하지 않는다.

## 결정 및 근거

1. 새 프로젝트는 project.labo와 빈 Assets·Sources를 만든다. 기본 레벨 지정이 없거나 지정된 파일이 없으면 경로 없는 LevelDocument를 연다. Ctrl+S의 첫 저장은 Assets 내부의 기존 부모 폴더와 새 `.level` 경로를 선택하며 기존 파일을 덮어쓰지 않는다. 파일·메타 생성 실패는 롤백하고 문서 경로·clean snapshot은 성공 후 갱신한다. 첫 저장으로 기본 레벨 지정까지 자동 변경하지 않는다.
2. UI 명칭은 Lua Class, Level Class, LObject Class, Parent Class로 통일한다. 호환성을 위해 `scriptReference`, `scriptKind`, `labo-script` 표식과 버전 2 형식은 유지한다. 새 Level·Prefab의 부모는 선택 사항이다.
3. Lua Class는 일반 테이블을 반환하고 `extends`에 같은 종류의 부모 클래스 ID를 지정한다. 로더는 순환·깊이·종류·함수 선언을 검증하고 부모를 `super`로 제공한다. 부모의 함수를 자식이 재정의하며, 재정의하지 않은 함수는 상속한다. 부모 함수 호출은 명시적이다. 다중 상속은 제공하지 않는다.
4. `properties`에 이름별 `{type, default}`를 선언한다. 타입은 number·string·boolean이며 숫자는 유한해야 한다. 부모의 프로퍼티 기본값을 같은 타입으로 재정의할 수 있다. Level의 `propertyOverrides`, Prefab의 `overrides.properties`에는 기본값과 다른 값만 저장한다. 부모를 바꿀 때 호환 값만 유지하고 해제 시 비운다.
5. 인스펙터는 LObject 선택이 없으면 현재 Level, 브라우저에서 Prefab을 선택하면 해당 에셋의 부모·프로퍼티를 편집한다. Ctrl+S로 저장하며 Prefab 저장도 ID로 현재 위치를 찾는다. 저장 전 Prefab을 다른 Prefab으로 바꾸는 선택은 막아 변경을 보존한다. 알 수 없는 필드·기존 override는 Prefab 저장에서 보존한다.
6. Play에서 클래스 기본값과 에셋 변경값을 합쳐 Runtime이 소유하는 properties 테이블을 만든다. Level은 world.properties, LObject는 self.properties로 읽는다. 배치 객체의 Prefab·LObject Class 참조는 Editor 로더가 해석하고 Core에는 클래스 테이블과 값만 전달한다. lifecycle 오류는 Play 시작·업데이트 경계에서 처리한다. Runtime 변경은 문서에 반영하지 않는다.
7. Move·Rename을 독립 메뉴로 분리한다. Move는 목적지 폴더 트리 선택을 기본 입력으로 하며 경로 직접 입력도 제공하고 이름은 유지한다. Rename은 현재 폴더에서 이름만 변경하고 확장자는 유지한다. 동일 루트·기존 폴더·링크 금지·덮어쓰기 금지·원본과 메타 동시 이동은 기존 Project.moveEntry가 재검증한다.

## 예상 결과

- 긍정: 빈 프로젝트를 바로 편집할 수 있고 파일 생성 시점을 사용자가 결정한다. Lua 동작·상속 프로퍼티를 여러 에셋이 재사용하고 이동에도 참조가 유지된다.
- 부정: 인스펙터 선언을 읽을 때 Lua 모듈 최상위 코드가 실행된다. 클래스 모듈은 선언 중심으로 작성해야 하고 소스 변경 후 Refresh 또는 다시 열기로 선언을 갱신한다. 부모를 변경하면 호환되지 않는 변경값이 사라진다.
- 중립: 상속은 깊은 객체 계층을 강제하지 않으며 Component composition 방향은 유지한다. 기본 레벨 지정 기능의 UI, Prefab 시각적 배치 도구·중첩 상속·Component override 편집은 이번 결정 범위 밖이다.
