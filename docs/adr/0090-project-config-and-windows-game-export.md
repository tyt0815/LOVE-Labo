# 0090. 프로젝트 conf.lua와 Windows 게임 EXE Export

- 상태: 채택·구현
- 날짜: 2026-10-17
- 확장: [0088 Lua 빌드·게임 CLI](0088-project-lua-build-and-game-cli.md)
- 유지: [0086 프로젝트 저장 identity](0086-project-save-identity.md), [0085 공개 API](0085-public-projection-layout-and-input.md)
- 부분 대체: [0028](0028-agent-cli-and-standalone-game-export.md)의 .love만 생성하던 기본 Export 범위

## 배경과 제약

Windows 플레이어가 별도의 LÖVE 설치 없이 게임을 실행해야 한다. 기존 빌드 스크립트·.love 출력·게임 CLI 계약을 유지한다. 게임 시작 시 창·모듈 설정을 프로젝트에서 자유롭게 구성하되 에디터 Play나 게임 CLI의 호스트 초기화를 바꾸지 않는다.

## 대안과 판단 기준

- Project Script의 load에서 창 설정: 이미 생성된 창을 바꿀 수 있으나 모듈 초기화 이전 설정을 다루지 못한다.
- Project Inspector에 모든 초기 설정 노출: 편집은 쉽지만 LÖVE 옵션별 스키마·변환 규칙을 중복 관리한다. 임의 Lua 설정 코드와 양방향 동기화도 필요하다.
- 프로젝트 conf.lua: 기존 LÖVE API를 그대로 사용한다. GUI에는 파일 열기만 제공하고 설정의 원본은 한 파일로 둔다.
- 별도 EXE 생성 도구나 Python: 런타임과 Lua ZIP 결합은 기존 에디터·CLI 패키징에서 검증했으므로 같은 방식과 공용 서비스를 사용한다.
- 지원하지 않는 플랫폼 선택지를 미리 제공: 실제 출력이 없으므로 현재 Windows만 표시하고 다른 플랫폼 요청은 명시적으로 거부한다.

## 결정 및 근거

1. 새 프로젝트 루트에 conf.lua를 생성하고 기존 프로젝트는 Export/설정 파일 열기 때 없는 기본 파일만 만든다. love.conf(config)에 기본값 변경 코드를 둔다. Export에서는 문법만 검사하고 실행하지 않는다.
2. 게임 패키지는 원본 ProjectConf.lua와 얇은 conf.lua 어댑터를 포함한다. 어댑터는 LÖVE 초기화 시 프로젝트 설정을 호출하고 에셋 경로/ID 아이콘을 패키지 경로로 변환한다. identity는 프로젝트 UUID 계약을 유지하며 다른 값 지정은 오류다. 에디터 Play·게임 CLI에는 사용자 conf.lua를 실행하지 않는다.
3. Project Inspector는 일반 문서 작업 행을 사용해 Game startup/Open conf.lua를 표시한다. CodeEditor의 기존 경로·인자·VS Code 재사용 처리를 공유한다. 파일 저장은 외부 편집기에서 하며 Inspector Undo/Save에 포함하지 않는다.
4. builder:packageGame은 .exe와 기존 .love를 확장자로 구분한다. WindowsPackage는 원본 love.exe 또는 CLI의 lovec.exe와 .love ZIP을 결합하고 DLL·라이선스를 복사한다. 이미 결합한 Labo.exe를 재사용하지 않는다. 에디터 배포본에는 두 원본 런처를 보관한다.
5. Export 창은 고정 Windows 표시, 출력 폴더, 실행 파일 이름을 제공한다. 기존 Tools/Build.lua를 실행하고 builder.platform은 windows다. CLI export도 같은 서비스를 사용하며 기본 출력은 Build/Windows/Game.exe, export.package는 기존 .love 전용이다. 기존 빌드 스크립트를 덮어쓰거나 출력 이름을 강제로 바꾸지 않는다.
6. 전체 빌드의 실패 원자성은 ADR 0088을 유지한다. EXE의 탐색기 아이콘 수정·설치 프로그램·다른 OS 출력은 이번 범위에 넣지 않는다.

## 관계

```text
ExportDialog (Widget 상속) ─ 의존 → ProjectBuild ─ 실행 → Tools/Build.lua
builder.packageGame ─ 의존 → WindowsPackage / GamePackage
builder.packageCli ─ 의존 → CliPackage → WindowsPackage → GamePackage
GamePackage ─ 의존 → GameConfig ─ 포함 → ProjectConf.lua / conf.lua
ScopeInspector ─ 제공 → 일반 문서 작업 → CodeEditor → 프로젝트 conf.lua
게임 EXE ─ 포함 → LÖVE 원본 런처 + 게임 ZIP (Editor 미포함)
```

게임 스크립트 상속·World 구조는 바꾸지 않는다. 설정 파일은 Script 콜백이 아닌 LÖVE 초기화 API를 사용한다.

## 예상 결과

- 긍정: 게임 EXE를 폴더째 배포할 수 있으며 초기 설정에 LÖVE 전체 설정 코드를 활용한다. GUI·CLI와 게임/CLI EXE 생성이 공용 로직을 사용한다.
- 부정: Windows 런타임과 DLL 배포가 필요하고 초기 설정 오류는 게임 시작 시 드러날 수 있다. 설정 파일은 코드로 편집해야 한다.
- 중립: .love 출력과 기존 빌드 API를 유지한다. 저장 identity와 에디터 창 설정은 바꾸지 않는다. 다른 플랫폼은 실제 지원할 때 추가한다.
