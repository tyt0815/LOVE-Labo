# CLI와 게임 Export

개발판은 `love src --cli ...`, 배포판은 `Labo-cli.exe --cli ...`를 사용합니다. stdout은 JSON이며 실패는 `ok:false`와 오류를 반환합니다. `--request <UTF-8 JSON 파일>`로 배열·복잡한 값을 전달할 수 있습니다. 참조는 에셋 ID 또는 Assets 경로, 기본 레벨은 project.labo의 지정값입니다.

```powershell
Labo-cli.exe --cli project create --parent D:/Games --name MyGame
Labo-cli.exe --cli script create --project D:/Games/MyGame --name Movement
Labo-cli.exe --cli prefab create --project D:/Games/MyGame --name PF_Player
Labo-cli.exe --cli prefab script add --project D:/Games/MyGame --prefab Assets/PF_Player.prefab --source Assets/Movement.lua --script movement
Labo-cli.exe --cli level create --project D:/Games/MyGame --name L_Start
Labo-cli.exe --cli project set-default --project D:/Games/MyGame --level Assets/L_Start.level
Labo-cli.exe --cli instance add --project D:/Games/MyGame --prefab Assets/PF_Player.prefab --x 100 --y 50
Labo-cli.exe --cli level simulate --project D:/Games/MyGame --frames 60 --dt 0.0166667
Labo-cli.exe --cli export --project D:/Games/MyGame --output D:/Games/MyGame/Build/Game.love
```

## 명령 목록

| 명령 | 용도·주요 인자 |
|---|---|
| project create/info/set-default/validate | 생성, 정보, 기본 --level, 전체 검증 |
| project refresh/repair-plan | 목록 갱신, 끊어진 등록·추천 대상·미등록 후보·revision 조회 |
| project repair | JSON 요청 revision과 changes[{id,target}] 또는 [{id,delete:true}]로 선택 적용 |
| project examples | Assets/Examples의 일반 에셋과 검수용 레벨 생성. 기존 예제를 덮어쓰지 않음 |
| script create/list/get/set-source | --name, --parent Script/Camera/Sprite/Pointer/Rect/Canvas 또는 Lua 에셋, --script, --source (Lua 코드 문자열). class.*도 호환 별칭 |
| folder create | --folder, --name |
| asset list/get/import/copy/move/rename/delete | --asset, --folder, --name; move의 --destination은 최종 파일 경로 |
| asset thumbnail | --asset Prefab; 브라우저와 같은 저장값 캐시를 생성·재사용하고 output·receipt·generated 반환. 생명주기와 초안 저장 없이 수행 |
| prefab create/get/tree/set/reset/set-parent | --prefab, --node root 또는 root/ID, --property, --value-json, --parent |
| prefab create --level --instance --link | 기존 계층에서 에셋 생성 후 원본 연결 및 레벨 저장; --link 생략 시 캡처만 수행 |
| prefab script add | --prefab, --node, --source, 선택 --script 사용자 이름; 내부 UUID 자동 생성 |
| prefab script rename | --prefab, --node, --script 이름 또는 ID, --name 새 이름 |
| prefab script remove | --prefab, --node, --script |
| prefab script move | --prefab, --node, --script, --index (1부터) |
| prefab child add/remove/rename | --prefab, --node, --template 또는 --instance, --name |
| prefab child rename --node root | 루트 오브젝트 이름 변경; Prefab 파일 이름 변경은 asset rename 사용 |
| prefab child move | --prefab, --node, --destination 노드 경로, --mode attach/before/after/detach; root 앞은 로컬 자손을 새 루트로 지정하며 기존 루트의 원본 유지 |
| level create/get/set/reset/set-parent/validate | --level, --name, --property; create --empty는 카메라 없는 레벨 |
| level view/set-camera | 투영 정보; --instance, --script로 Main Camera 지정 |
| level simulate | --frames 0..10000, --dt, --debug; 파일 수정 없이 load/update 결과와 스크립트 상태 반환, draw는 실행하지 않음. --debug는 에디터 로그·도형 기록도 반환 |
| level pointer | --space world/screen, --x, --y, --width, --height, --events-json; 이벤트마다 최신 카메라로 좌표 변환 |
| instance add/get/list/set/reset/rename/reparent/duplicate/delete | --instance 또는 --instances, --prefab, --parent; 재정의 프로퍼티는 movement.speed처럼 사용자 이름 또는 내부 ID 포함 |
| instance script rename | --instance, --script 이름 또는 ID, --name 새 이름 |
| instance script add/remove/move | --instance, --source, --script, --index; 로컬 부착만 제거·정렬 |
| instance reorder | --instances 또는 --instance, --destination 인스턴스 ID, --mode before/after |
| export | --output; 검증 후 독립 게임 .love 생성 |

정확한 개별 인자는 help와 JSON 요청 예제를 확인합니다. 일반 스크립트 생성은 --type script, 레벨 스크립트는 --type level을 사용합니다. 생성 경로 기본값은 Assets입니다. 새 레벨은 기본 Camera 부착 오브젝트와 `{authoringId,script}` Main Camera를 저장합니다. 별도 Camera.lua를 만들지 않습니다.

```powershell
Labo-cli.exe --cli prefab create --project D:/Games/MyGame --level Assets/L_Start.level --instance 2 --name PF_Enemy --link
```

이 명령은 오브젝트 ID와 Transform을 유지하며, 스크립트와 프로퍼티 값을 에셋으로 옮긴 뒤 레벨을 저장합니다. 결과의 linkedLevel과 instance로 연결한 대상을 확인합니다. GUI Create Prefab과 공용 캡처·연결 로직을 사용합니다. 생성 후 연결 또는 레벨 저장이 실패하면 새 에셋을 제거합니다. 상속 자손 하나를 교체하지 않고 배치 루트에서 사용합니다.

`--link`와 함께 전달하는 `--revision`은 연결할 레벨의 revision입니다. `level get`으로 조회한 revision이 현재 레벨과 다르면 에셋 생성 전에 거절하며, 생성·저장 도중 레벨이 변경된 경우도 덮어쓰지 않습니다.

```json
{"command":"prefab.set","project":"D:/Games/MyGame","prefab":"Assets/PF_Player.prefab","property":"movement.speed","value":250}
```

Prefab과 인스턴스에서 로컬 스크립트를 추가·제거·정렬합니다. 상속한 구성은 값만 편집합니다. GUI와 CLI는 같은 PrefabEditor·ObjectDefinition·계층 로직을 사용합니다. 변경 충돌을 피하려면 GUI 초안을 먼저 저장합니다. CLI 파일 변경은 GUI Undo에 포함되지 않습니다.

`level simulate` 중 레벨 전환 대상의 초기화가 실패하면 성공 결과 대신 오류를 반환합니다. 이전 World에서 계속 실행한 결과를 정상 전환으로 보고하지 않습니다.

상속된 오브젝트의 부모·순서·삭제와 상속된 스크립트의 제거·정렬은 명령 단계에서 거절합니다. 원본으로부터 구성 전체를 배치한 루트 인스턴스의 이동·삭제는 허용합니다. 로컬 항목 추가와 프로퍼티 변경은 허용하며 GUI와 같은 공용 로직을 사용합니다.

## 패키징

`scripts/packageEditor.ps1`로 에디터를 패키징하고 `scripts/verifyCliExport.ps1`로 패키징된 CLI와 독립 게임을 검증합니다. 개발판 GUI의 미저장 Prefab도 Export에 포함되며 CLI는 디스크 데이터를 사용합니다.

게임 패키지에는 `core/`, `project/`, `runtime/`, 공개 `Engine.lua`, 프로젝트 Assets, ID/경로/종류 매니페스트와 게임 전용 `main.lua`·`conf.lua`만 포함한다. 에디터·테스트·사용자 설정은 포함하지 않는다. 편집용 메타데이터 파일은 복사하지 않고 매니페스트에서 ID 매핑을 유지한다. 초기 Export는 의존 에셋만 추려내지 않고 등록된 프로젝트 파일 전체를 담는다.

```powershell
& 'C:\Program Files\LOVE\love.exe' D:\Games\MyGame\Build\Game.love
```

게임은 LÖVE 11.5가 필요하다. 독립 실행 게임 EXE·설치 프로그램은 이번 범위에 포함하지 않는다. 게임 호스트는 시작·update·렌더링 오류를 잡아 오류 화면을 표시하고, Editor Play와 같은 스크립트·참조·load 초기화 로직을 사용한다. 운영체제·드라이버나 네이티브 라이브러리 오류까지 복구한다는 계약은 아니다.

## 복구와 검증

유효한 프로젝트를 열 때 Assets가 없으면 생성한다. 같은 이름의 파일·링크, 권한 오류, 손상된 프로젝트 JSON은 덮어쓰지 않고 오류를 반환한다. 삭제된 폴더 안의 에셋·클래스 자체를 복원하지는 않는다. 시작 화면의 프로젝트 열기 콜백 오류도 에디터 전체 종료 대신 화면의 오류로 남긴다.

```powershell
.\scripts\verifyCliExport.ps1
```

위 명령은 에디터를 패키징하고 실제 CLI로 스크립트·Prefab·레벨을 생성한다. 부착 순서, 초기화·업데이트, 포인터, 사용자 draw와 독립 게임 Export를 검증한다. 결과는 `build/cli-export-<고유값>/Game.love`와 `game-report.json`에 남는다.

## 플러그인 관리

`plugin.list`, `plugin.create`, `plugin.plan`, `plugin.enable`, `plugin.disable`을 지원합니다. 의존성을 함께 변경하려면 `--confirm true`를 사용합니다. [상태 표시·에셋 탐색·JSON 예제](guide/plugins.md)를 참고하세요.

## 스크립트 배치와 외부 파일·폴더 임포트

`asset.preview --asset Assets/PF_Player.prefab --output D:/Captures/Player.png`은 초기화·업데이트 없이 PNG를 출력합니다. [인스턴스 캡처·배경 설정](guide/preview.md)을 참고하세요.

창 없이 시작하는 실제 CLI의 썸네일 생성·캐시 갱신·재사용과 Prefab·이미지 PNG 출력은 `powershell -NoProfile -ExecutionPolicy Bypass -File scripts/verifyThumbnailCli.ps1`로 검증합니다. 검증 프로젝트와 출력은 build의 새 폴더에 보관합니다.

`instance.add --level Assets/L_Start.level --script Assets/Behavior.lua --x 20 --y 40`은 빈 LObject에 해당 오브젝트 스크립트를 부착합니다. `--parent <인스턴스 ID>`로 자손 배치도 가능합니다. Prefab과 script를 동시에 지정하지 않습니다.

`asset.import --input C:/Images/Player.png --folder "Assets/User Plugins/MyPlugin"`은 파일을 복사합니다. input은 폴더도 가능하며 name으로 새 이름을 지정할 수 있습니다. 기존 파일·메타데이터를 덮어쓰지 않고 파일시스템 링크는 따라가지 않습니다.

스크립트 프로퍼티 조회 결과의 schema·values 키는 `사용자이름.프로퍼티`이며 `scriptIds`가 이름과 UUID를 연결합니다. prefab get은 최상위, instance get은 properties.scriptIds에서 확인합니다. 이름 또는 ID로 편집할 수 있으며 저장된 script 참조와 Main Camera는 내부 ID를 사용합니다. `instance set`/`prefab set`의 `이름.enabled`로 활성 상태를 편집합니다.
