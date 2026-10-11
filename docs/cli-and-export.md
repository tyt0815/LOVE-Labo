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
| script create/list/get/set-source | --name, --parent Script/Camera/Sprite/Pointer/Rect/Canvas 또는 Lua 에셋, --script, --source (Lua 코드 문자열). class.*도 호환 별칭 |
| folder create | --folder, --name |
| asset list/get/import/copy/move/rename/delete | --asset, --folder, --name; move의 --destination은 최종 파일 경로 |
| prefab create/get/tree/set/reset/set-parent | --prefab, --node root 또는 root/ID, --property, --value-json, --parent |
| prefab script add | --prefab, --node, --source, 선택 --script 부착 ID |
| prefab script remove | --prefab, --node, --script |
| prefab script move | --prefab, --node, --script, --index (1부터) |
| prefab child add/remove/rename | --prefab, --node, --template 또는 --instance, --name |
| prefab child move | --prefab, --node, --destination 노드 경로, --mode attach/before/after/detach; root 앞은 독립 Prefab의 루트 교체 |
| level create/get/set/reset/set-parent/validate | --level, --name, --property; create --empty는 카메라 없는 레벨 |
| level view/set-camera | 투영 정보; --instance, --script로 Main Camera 지정 |
| level simulate | --frames 0..10000, --dt; 파일 수정 없이 beginPlay/update 결과와 스크립트 상태 반환, draw는 실행하지 않음 |
| level pointer | --space world/screen, --x, --y, --width, --height, --events-json; 이벤트마다 최신 카메라로 좌표 변환 |
| instance add/get/list/set/reset/rename/reparent/duplicate/delete | --instance 또는 --instances, --prefab, --parent; 재정의 프로퍼티는 movement.speed처럼 부착 ID 포함 |
| instance script add/remove/move | --instance, --source, --script, --index; 로컬 부착만 제거·정렬 |
| instance reorder | --instances 또는 --instance, --destination 인스턴스 ID, --mode before/after |
| export | --output; 검증 후 독립 게임 .love 생성 |

정확한 개별 인자는 help와 JSON 요청 예제를 확인합니다. 일반 스크립트 생성은 --type script, 레벨 스크립트는 --type level을 사용합니다. 생성 경로 기본값은 Assets입니다. 새 레벨은 기본 Camera 부착 오브젝트와 `{authoringId,script}` Main Camera를 저장합니다. 별도 Camera.lua를 만들지 않습니다.

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

게임은 LÖVE 11.5가 필요하다. 독립 실행 게임 EXE·설치 프로그램은 이번 범위에 포함하지 않는다. 게임 호스트는 시작·update·렌더링 오류를 잡아 오류 화면을 표시하고, Editor Play와 같은 스크립트·참조·beginPlay 초기화 로직을 사용한다. 운영체제·드라이버나 네이티브 라이브러리 오류까지 복구한다는 계약은 아니다.

## 복구와 검증

유효한 프로젝트를 열 때 Assets가 없으면 생성한다. 같은 이름의 파일·링크, 권한 오류, 손상된 프로젝트 JSON은 덮어쓰지 않고 오류를 반환한다. 삭제된 폴더 안의 에셋·클래스 자체를 복원하지는 않는다. 시작 화면의 프로젝트 열기 콜백 오류도 에디터 전체 종료 대신 화면의 오류로 남긴다.

```powershell
.\scripts\verifyCliExport.ps1
```

위 명령은 에디터를 패키징하고 실제 CLI로 스크립트·Prefab·레벨을 생성한다. 부착 순서, 초기화·업데이트, 포인터, 사용자 draw와 독립 게임 Export를 검증한다. 결과는 `build/cli-export-<고유값>/Game.love`와 `game-report.json`에 남는다.
