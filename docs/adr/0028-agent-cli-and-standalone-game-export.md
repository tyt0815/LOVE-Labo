# 0028. AI 작업 CLI와 독립 게임 Export의 공용 로딩 계층

- 상태: 채택
- 날짜: 2026-10-09
- 확장: [ADR 0027](0027-windows-editor-packaging.md)의 배포 실행 파일
- 확장: [ADR 0012](0012-lua-classes-properties-and-unsaved-levels.md), [ADR 0017](0017-components-instance-properties-and-prefab-placement.md)의 클래스·컴포넌트 저장 계약
- 유지: Core → Editor 의존 금지, Edit/Runtime 상태 분리

## 배경과 제약

AI가 배포된 에디터를 사용하여 클래스·Prefab 생성, 배치·프로퍼티 편집과 게임 Export를 수행해야 한다. 게임은 에디터 없이 패키지 내부 프로젝트 코드를 실행해야 한다. 동시에 필수 프로젝트 폴더 누락이나 프로젝트 콜백 오류가 호스트 전체 종료로 이어지지 않도록 보완한다.

## 대안과 판단 기준

- CLI가 JSON 스키마를 독자적으로 조작하면 GUI와 검증·기본값·ID 규칙이 달라진다. Project·문서·Definition의 기존 로직을 재사용한다.
- 게임에 Editor 코드를 복사하면 초기 Export는 간단하지만 설계의 독립 Runtime 계약을 깨뜨린다. 로딩과 구성의 공통 부분만 `project/`·`runtime/`으로 분리한다.
- CLI에서 EditorApp을 생성하면 그래픽·UI 초기화가 필요하다. CLI 분기는 테마·폰트보다 먼저 처리하고 창·오디오를 생성하지 않는다.
- 기존 모듈 경로를 한 번에 삭제하면 호출부와 테스트의 불필요한 변경이 커진다. 이동한 Editor 모듈은 공용 모듈을 반환하는 호환 위임을 유지한다.
- Export에 외부 ZIP 도구를 요구하면 설치 환경 의존성이 늘어난다. UTF-8 파일 이름과 CRC32를 지원하는 ZIP32 저장 방식으로 `.love`를 작성한다. 대신 전체 패키지를 메모리에 구성하고 압축하지 않는다.

## 결정 및 근거

1. `project/`는 JSON·ID·기본 프로퍼티 데이터·참조 검증·Prefab 디코딩·클래스 로딩·Definition 구성을 제공한다. 파일 읽기는 `readSource`·`readAsset`을 제공하는 프로젝트 객체에 위임한다. Editor Project는 네이티브 외부 파일, Runtime PackageProject는 패키지 가상 파일을 읽는다.
2. `runtime/world_loader`는 레벨에서 객체 구성·전방/순환 참조 해석·BeginPlay 순서를 공유한다. `prepare`는 검증을 위해 build와 참조 해석만 하고, `create`는 BeginPlay까지 실행한다. Editor Play와 게임 Host가 같은 초기화 경로에 의존한다.
3. `Labo-cli.exe --cli`는 생성·조회·수정·Export를 제공하고 버전 1 JSON 응답과 0/1 종료 코드를 반환한다. JSON 요청 파일도 지원한다. 컴포넌트 부착·게임 동작 작성은 프로젝트 Lua의 기존 책임이다.
4. CLI는 프로젝트 잠금으로 다른 CLI 작업을 직렬화한다. 문서의 SHA-256 revision으로 선택적 낙관적 충돌 검사를 제공하며, 저장 직전 읽은 파일과 비교한다. GUI 미저장 문서와 자동 동기화는 제공하지 않고 닫은 문서에 대한 작업을 사용 계약으로 명시한다.
5. Export는 Core·공용 Project 모듈·게임 Host·프로젝트 코드/에셋·ID 매니페스트를 포함한다. Editor·테스트는 제외한다. GUID와 상대 경로 의미는 유지하고 게임 Host는 패키지 내부 파일만 읽는다. GUI의 Ctrl+Shift+E와 CLI가 동일한 Export 서비스를 사용한다.
6. 유효한 프로젝트의 Assets·Sources 누락만 생성한다. 파일/링크 충돌과 잘못된 데이터는 덮어쓰지 않는다. 시작 콜백·게임 초기화/Update/렌더링 오류는 오류 반환 또는 화면 표시로 격리한다. 잃어버린 에셋과 OS 네이티브 오류 복구는 이 계약 밖이다.

## 관계

```text
EditorApp ─┐
CLI ───────┼─ 의존 → project/ + runtime/world_loader → core/
Game Host ─┘              ↑
                   파일 읽기 의존
           Editor Project / Runtime PackageProject

GUI·CLI → Export → 게임 Host·공용 모듈·프로젝트 파일 포함
```

상속을 추가하지 않는다. 두 프로젝트 어댑터는 동일한 읽기 메서드 계약을 충족하지만 공통 부모를 상속하지 않는다. 프로젝트 데이터를 Runtime 상태로 복사하는 기존 경계를 유지한다.

## 예상 결과

- 긍정: AI·GUI·게임 간 클래스·프로퍼티·참조 의미가 일치하며 독립 게임을 검증할 수 있다. 필수 폴더 누락을 복구하고 잘못된 편집을 저장 전에 거부한다.
- 부정: 공유 계층으로 파일 위치가 바뀌고 호환 위임이 남는다. 무압축 ZIP의 크기와 메모리 비용이 증가하며 GUI/CLI 동시 편집은 별도 동기화가 필요하다.
- 중립: 기본 레벨·Prefab·메타데이터 저장 스키마는 유지한다. 이번 목표는 `.love`이며 게임 EXE·설치 프로그램·소스 보호는 포함하지 않는다.
