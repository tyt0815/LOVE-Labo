# 0093. Script 반환 계약과 호스트 경계의 공용 규칙을 일치시킨다

- 상태: 채택·구현
- 날짜: 2026-10-17
- 확장: [0028 공용 CLI·Export](0028-agent-cli-and-standalone-game-export.md), [0058 플러그인](0058-plugins-and-mounted-assets.md), [0072 부모 ID](0072-script-parent-asset-ids-and-copy-id.md), [0085 공개 API](0085-public-projection-layout-and-input.md), [0088 빌드·게임 CLI](0088-project-lua-build-and-game-cli.md), [0091 준비 상태 정리](0091-loading-validation-and-failure-cleanup.md), [0092 세션 로더](0092-session-loading-and-runtime-failure-boundaries.md)
- 기존 결정을 대체하지 않는다. 일반 Script 에셋도 제공 플러그인과 같은 클래스 반환 형식을 허용하고, 경계별로 누락된 기존 보호·정리 원칙을 구체화한다.

## 배경과 제약

플러그인은 Script:extend 결과를 허용하지만 프로젝트 Assets는 metatable을 모두 거부하여 제공 소스를 복사해 사용할 수 없었다. 반대로 플러그인은 임의의 metatable까지 검증 없이 받아들였다. Windows의 대소문자 구별 없는 경로를 export.package의 Assets 검사에서 반영하지 않아 원본을 덮어쓸 수 있었다. 에디터 UI는 World의 빈 캡처 테이블을 읽고 실제 View의 캡처를 놓쳤다. CLI 이벤트는 View의 부분 출력 사각형을 무시했고, 에디터 CLI는 결과 파일 저장 전에 성공 응답을 출력했다. 미리보기 교체와 부분 구성 실패는 이전 configure 바인딩을 정리하지 않았다.

에디터의 조작 단계와 저장 형식은 유지한다. Core는 Editor에 의존하지 않으며 새 실행 캐시나 특별한 플러그인 권한을 추가하지 않는다.

## 대안과 판단 기준

- 제공 플러그인을 모두 일반 정의 테이블로 바꾸면 기존 공개 Script:extend 사용 사례를 제한한다. 두 반환 형식을 공용 로더에서 받되 검증된 파생 클래스만 허용한다.
- 임의의 metatable이나 super 필드만 확인하면 검증하지 않은 테이블이 클래스처럼 통과한다. Script:extend가 검증을 마친 테이블을 약한 키 집합에 기록한다. 이는 보안 샌드박스나 변조 방지 장치가 아니라 클래스 출처 판별이다.
- 호스트별 경로·CLI 응답 검사를 계속 복제하면 같은 규칙이 다시 갈라진다. 소스 출력 보호와 응답 완료 처리는 각각 실제 호출자가 공유한다. 명령 파서와 호스트별 파일 경로 해석은 합치지 않는다.
- 캡처를 World에도 복사하면 두 저장소의 동기화가 필요하다. View별 소유권을 유지하고 RenderPipeline이 활성 화면 입력 캡처만 조회한다.
- 캐시 전체를 매번 지우면 재사용을 잃는다. 서명이 바뀐 항목과 실패한 부분 객체만 기존 ScriptHost.unload로 정리한다. load 전에는 unload 콜백 없이 바인딩만 해제하는 기존 계약을 사용한다.

## 결정 및 근거

1. Script.isClass는 Script:extend가 생성한 파생 클래스만 판별한다. LuaScript.scriptClass는 프로젝트·플러그인에 같은 반환 형식과 폐기된 build/beginPlay 금지 규칙을 적용한다. 일반 정의는 기존 에셋 ID extends를 해석한 부모로 확장하고, 이미 확장한 클래스는 다시 확장하지 않는다. 기반 Script 자체와 임의 metatable은 거절한다. 클래스 테이블과 세션 require 캐시의 동일성을 유지한다.
2. editor.BuildOutput.check는 정규화한 Windows 경로를 대소문자 구분 없이 비교하여 Assets·Tools·Docs·Plugins·.labo 및 프로젝트 설정 파일 출력을 막는다. ProjectBuild의 packageGame/packageCli/copy, 낮은 계층 GamePackage·WindowsPackage가 같은 정책에 의존한다.
3. project.CliResponse.finish는 명령 결과 인코딩과 선택적인 결과 저장을 완료한 뒤 최종 JSON·성공 여부를 반환한다. Editor Cli·게임 CliHost가 이를 사용하며 경로 해석·실제 파일 쓰기는 콜백으로 전달한다. 저장 실패 뒤 성공 JSON을 먼저 출력하지 않는다. 이미 완료된 명령의 파일 변경을 되돌리는 트랜잭션은 제공하지 않는다.
4. RenderPipeline.captureButton은 활성 화면 View의 살아 있는 입력 영역 캡처를 조회한다. EditorApp은 이를 보호된 경계에서 호출하여 Root의 단일 캡처를 마지막 게임 버튼까지 유지한다. CLI 일반 이벤트는 기존 primaryViewport를 사용해 부분 출력·레터박스 원점을 GUI·게임 Host와 일치시킨다.
5. AuthoringLayout과 SpriteAssets는 캐시 교체 전 이전 호스트를 정리하고 구성 실패 시 부분 호스트도 정리한다. clear도 같은 ScriptHost.unload를 사용한다. 미리보기는 게임 load/update를 시작하지 않는다.
6. editor.ProjectValidation은 프로젝트 전체 에셋 검증을 소유한다. CliAssets와 PluginOperations가 직접 의존하여 GUI 플러그인 작업이 CLI 명령 디스패처를 호출하지 않게 한다. valid/checked/errors 응답은 유지한다.

```text
LuaScript·PluginRegistry ──의존──> LuaScript.scriptClass ──검증 조회──> Script.isClass
ProjectBuild·GamePackage·WindowsPackage ──의존──> BuildOutput
Editor Cli·게임 CliHost ──의존──> CliResponse ──콜백 의존──> 호스트별 파일 쓰기
EditorApp ──캡처 조회──> RenderPipeline ──조회──> View가 소유한 버튼별 캡처
CliEvents·Editor·게임 Host ──의존──> RenderPipeline.primaryViewport
AuthoringLayout·SpriteAssets ──캐시 호스트 소유·폐기──> ScriptHost.unload
CliAssets·PluginOperations ──의존──> ProjectValidation ──의존──> LuaScript·WorldLoader
```

새 상속·인터페이스 계층은 추가하지 않는다.

## 예상 결과

- 긍정: 제공 소스를 Assets에 복사할 수 있고 임의 클래스 우회는 거절한다. 출력 위치·CLI 실패 응답·이벤트 좌표가 호스트 간에 일치한다. 패널 밖 버튼 해제와 미리보기 교체에서 자원 수명을 유지한다.
- 부정: 과거 플러그인에서 임의 metatable이나 build/beginPlay를 반환한 비정상 정의는 오류가 된다. 원본 폴더를 배포 대상으로 지정했던 빌드는 별도 출력 폴더로 바꿔야 한다. 캡처 조회는 활성 View의 투영 제공자를 평가하므로 에디터의 오류 격리를 유지해야 한다.
- 중립: 파일 형식·CLI 명령 이름·정상 응답 필드와 GUI 조작은 유지한다. require 기반 클래스 상속은 일반 Lua 의존성이며, 파일 이동에 안정적인 저작 상속 참조에는 계속 에셋 ID extends를 사용한다.
