# 0088. 프로젝트 Lua 빌드와 게임 전용 CLI 배포

- 상태: 채택
- 날짜: 2026-10-16
- 확장: [ADR 0028](0028-agent-cli-and-standalone-game-export.md)의 독립 Export와 공용 로딩
- 유지: [ADR 0085](0085-public-projection-layout-and-input.md)의 플러그인·일반 API 경계

## 배경과 제약

제작한 게임의 내장 콘텐츠 편집기와 AI가 같은 생성·검증·저장 규칙을 사용해야 한다. 게임 CLI와 제작 문서를 게임에 동봉하되 Labo나 Python 설치를 요구하지 않는다. 빌드 조합은 프로젝트가 수정하고 특정 채보·스테이지 규칙은 엔진에 두지 않는다. 현재 네이티브 파일 IO와 배포 호스트는 Windows, LÖVE 11.5다.

## 검토한 대안과 판단 기준

- 프로젝트 Python 스크립트: 별도 설치·프로세스·오류 전달 계약이 필요하다. 프로젝트와 같은 Lua를 선택한다.
- 빌드 스크립트 경로 설정: 경로 선택 UI와 프로젝트 스키마를 늘린다. 실제 요구가 없는 설정은 두지 않고 Tools/Build.lua를 고정한다.
- 엔진에 게임별 명령 등록: 규칙 복제가 생기고 Core가 도메인을 알게 된다. 일반 프로젝트 Lua 모듈을 로딩한다.
- 기존 게임 Host를 만든 뒤 CLI 실행: World·사용자 load·창·오디오 초기화가 발생한다. 별도 얇은 CliHost로 명령만 실행한다.
- GUI와 CLI 즉시 동기화: IPC·Undo·미저장 상태 충돌 정책이 필요하다. 명시적 Reload와 revision 검사부터 제공한다.
- 게임 패키지를 CLI에서 외부 마운트: 중복 크기는 줄지만 파일의 상대 위치·수명에 결합한다. 최초 구현은 독립 패키지로 실행 가능하게 한다.

## 결정 및 근거

1. 새 프로젝트에 Tools/Build.lua를 생성한다. 기존 프로젝트는 최초 Export/Open Build Script 때 누락된 기본 파일만 만든다. 기존 파일은 덮어쓰지 않는다.
2. GUI·에디터 CLI Export는 ProjectBuild를 공유한다. builder의 packageGame/packageCli/copy/log가 출력 폴더 아래 결과를 구성한다. 낮은 계층 GamePackage와 export.package는 스크립트를 실행하지 않아 재귀 Export가 필요 없다. Lua 실행은 일반 프로젝트 권한이며 보안 샌드박스가 아니다.
3. packageCli는 원본 lovec.exe와 CLI 아카이브를 결합하고 런타임 DLL·라이선스를 복사한다. 에디터 배포본에도 원본 lovec.exe를 둔다. 이미 fuse된 Labo-cli.exe는 재결합하지 않는다. 일반 게임 .love Export는 유지한다.
4. CLI 모듈은 {summary,commands}를 반환하고 각 명령은 parameters와 run(context,args)를 선언한다. 공용 GameCommands가 help/schema·형식 검증·명령행/JSON 요청을 처리한다. CliHost는 PackageProject와 기존 moduleLoader로 모듈만 읽고 World·게임 콜백·창·오디오를 생성하지 않는다. JSON 응답 버전 1, 성공 0/실패 1을 사용한다.
5. NativeFileSystem·WindowsUnicode는 project 계층으로 이동하고 editor 경로는 호환 위임한다. Workspace는 루트 경계·부모 링크 검사, UTF-8 파일 IO, atomic 교체, 선택적 revision, 배타 잠금을 제공한다. CLI는 지정된 작업 폴더에서 요청 전체를 잠그고 게임 편집기는 같은 API와 일반 콘텐츠 모델을 사용한다. 게임별 데이터 형식은 고정하지 않는다.
6. GUI는 스크립트 열기·출력 경로·로그/오류·폴더 열기·마지막 결과를 제공한다. 빌드는 동기식이며 전체 트랜잭션이 아니다. 중간 실패 전 파일과 로그를 보존한다. UI와 CLI의 미저장 데이터 동기화는 명시적 Reload와 revision 충돌로 다룬다.

## 관계

```text
EditorApp / editor.Cli ─ 의존 → ProjectBuild ─ 실행 → Tools/Build.lua
                                    └─ 제공 → builder API
                                                 ├─ 의존 → GamePackage
                                                 ├─ 의존 → CliPackage → GamePackage
                                                 └─ 의존 → Workspace
게임 CLI EXE ─ 포함 → CliHost ─ 의존 → GameCommands / PackageProject / moduleLoader
                              └─ 로딩 → 프로젝트 Commands ─ 의존 → 공용 콘텐츠 모델
게임 내 편집 Script ─ 의존 → 같은 콘텐츠 모델 / Workspace
Workspace ─ 의존 → NativeFileSystem / WindowsUnicode
```

새 상속 계층은 추가하지 않는다. builder는 빌드 함수에 전달하는 호출 API이며 명령 모듈은 부착 Script가 아니다. 게임 내 편집기만 기존 Script 생명주기를 사용한다.

## 예상 결과

- 긍정: 프로젝트가 Lua만으로 게임·CLI·가이드 배포를 조합하며 AI와 게임 편집기의 규칙을 공유한다. CLI는 에디터 설치 없이 독립 실행한다.
- 부정: 게임과 CLI의 에셋이 중복되어 배포 크기·메모리 사용이 늘어난다. Windows 의존과 동기식 빌드 대기, 강제 종료 뒤 잠금 수동 복구가 남는다.
- 중립: 프로젝트/레벨 저장 스키마는 유지한다. 기본 Export는 게임만 생성한다. 콘텐츠 형식·명령·가이드는 게임 프로젝트가 정한다. IPC·GUI Undo 통합·다른 OS 패키징은 이번 범위 밖이다.
