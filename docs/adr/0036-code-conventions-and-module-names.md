# 0036. 코드 컨벤션과 모듈·공개 함수 이름 통일

- 상태: 채택
- 날짜: 2026-10-09
- 부분 대체: [ADR 0021](0021-begin-play-and-orthographic-rotation.md), [ADR 0033](0033-prefab-spawn-and-resource-inspector.md), [ADR 0035](0035-render-components-and-root-transform.md)의 공개 함수·모듈 경로 표기
- 유지: 클래스 상속·부착 구조, 코드 구성 원본, Core의 Editor 비의존, 저장 데이터·에셋 ID 계약

## 배경과 제약

사용자는 클래스 테이블·파일 PascalCase, 변수·함수 camelCase, 상수 UPPER_SNAKE_CASE, 공백 네 칸, 파일별 단일 책임을 AGENTS.md에 명시하고 저장소 전체에 적용하도록 요청했다. 기존 BeginPlay·Draw처럼 대문자 함수와 snake_case 모듈 파일이 섞여 있었다. LÖVE는 main.lua·conf.lua와 정해진 콜백을 요구하며 FFI의 Windows 함수·표준 라이브러리 이름도 변경할 수 없다. 패키지 ZIP에서는 require 경로 대소문자가 실제 파일명과 일치해야 한다.

## 대안과 판단 기준

- 기존 코드와 새 코드에 다른 규칙을 적용하면 새 클래스·컴포넌트 작성자가 두 API 표기를 알아야 한다. 제품 소스·테스트·템플릿·패키징·현행 사용 문서를 함께 변경한다.
- 모든 파일·외부 함수에 규칙을 강제하면 LÖVE나 Windows 호출이 깨진다. 프레임워크 진입 파일·콜백·메타메서드·외부 API는 예외로 기록한다.
- 이전 파일 경로마다 별칭 파일을 남기면 같은 모듈 책임이 두 경로로 계속 보인다. 저장소의 모든 require를 새 경로로 바꾸고 배포·Export 검증으로 누락을 찾는다.
- 책임을 파일 크기로 판단해 나누면 이번 이름 정리와 무관한 구조 변경이 된다. 기존 클래스·로더·렌더러·UI 위젯·문서·파일시스템의 책임 경계를 점검하고 현재 분리를 유지한다.

## 결정 및 근거

1. 제품 Lua 모듈은 PascalCase 파일명을 사용한다. Engine.lua, core/LObject.lua, core/SceneComponent.lua, editor/EditorApp.lua, editor/ui/ClassTree.lua 등이 해당한다. 클래스 테이블과 가져온 클래스·모듈 이름도 PascalCase다. 테스트 사례 모음과 작업 스크립트는 camelCase 파일명, 클래스 역할의 Assert.lua·Runner.lua는 PascalCase다. main.lua와 conf.lua는 예외다.
2. 공개 함수는 beginPlay, update, draw, getLocalBounds, spawnLObject로 통일한다. Engine은 require("Engine")으로 가져온다. 기존 lowercase load 초기화 별칭은 유지한다. 이전 BeginPlay/Update/Draw/GetLocalBounds/SpawnLObject 호출과 require("engine")을 사용하는 외부 프로젝트 소스는 새 표기로 수정해야 한다. 외부 게임 프로젝트의 파일을 자동 변경하지 않는다.
3. 변하지 않는 테이블·수치·핸들은 UPPER_SNAKE_CASE로 표시한다. Transform.FIELDS/ORDER, Ui.METRICS, PropertyLayout.ROW_HEIGHT/HEADER_HEIGHT, 기본 색·스냅 단위·라벨·파일 핸들 등이 해당한다. 변경되는 큐·캐시·상태 변수는 camelCase를 유지한다.
4. 클래스 생성은 이름을 PascalCase로 보정해 파일명과 생성 테이블 이름을 맞춘다. 예를 들어 lower_name은 LowerName.lua와 local LowerName, 숫자 시작 이름은 Class 접두사를 사용한다. 기존 가져오기 파일·에셋 ID·저장 필드는 별도 마이그레이션 없이 유지한다.
5. Lua Class 생성의 부모 트리는 모든 가지가 접힌 상태에서 시작한다. 방향키·화살표로 펼치고 부모를 선택한다. 프로그램으로 숨겨진 항목을 선택하면 해당 조상만 펼친다. Level·Prefab 생성 트리의 기존 기본 상태는 유지한다. 선택·접기 상태는 저장 데이터에 포함하지 않는다.
6. TestProject의 NewClass는 sprite라는 SpriteComponent를 루트로 사용한다. 이미지·일반 프로퍼티 선언은 유지하고 중복 SceneComponent 루트를 제거한다. 기존 sprite.image 참조 키와 Sprite 루트의 Transform 의미를 유지한다.
7. scripts/checkConventions.py는 제품·테스트·스크립트의 이름, 함수·콜백 식별자, 공백 네 칸 들여쓰기, require 파일 존재·대소문자를 검사한다. 파일별 책임과 상수의 의미는 코드 검토로 판단한다. 전체 LÖVE 테스트와 실제 Windows 패키지·CLI·Export 검증을 함께 실행한다. 생성된 build 결과물과 역사적 ADR은 전수 이름 변경 대상에서 제외한다.

## 관계

```text
공개 모듈: Engine.lua ─ 의존 → core/* Component 클래스
호스트: main.lua ─ 의존 → editor/EditorApp.lua / ui 위젯
생성: Project.lua ─ 의존 → ClassName.lua / 각 ScriptTemplate.lua
검사: checkConventions.py → src / tests / scripts (읽기 전용)

소유: NewClass 인스턴스
      └─ sprite (SpriteComponent 루트)
```

## 예상 결과

- 긍정: 파일·클래스·함수 이름이 일관되고 새 코드도 같은 규칙으로 생성된다. 엄격한 대소문자 패키지와 개발 환경이 같은 require 경로를 사용한다. 새 Lua Class 부모 탐색은 필요한 가지부터 펼친다.
- 부정: 공개 함수·Engine 모듈 경로를 사용한 외부 프로젝트 코드는 이름을 갱신해야 한다. 파일 변경 수가 많아 이전 경로로 된 개인 스크립트도 갱신이 필요하다.
- 중립: 상속·계층·Transform·렌더링 의미와 JSON 버전은 유지한다. 역사적 ADR의 당시 이름은 기록으로 남기고 후속 ADR로 연결한다.
