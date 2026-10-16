# CLI와 게임 Export

## 사용자 가이드 화면 캡처

`love src --capture-guide <새 절대 경로>`는 임시 예제 프로젝트로 실제 UI를 재현하고 PNG·report.json을 저장한 뒤 종료합니다. Project Browser의 카드·하단 정보, Project → Inspector 메뉴, 기본으로 접힌 그룹과 펼친 그룹 예제도 포함합니다. 기존 사용자 프로젝트와 최근 프로젝트 설정은 변경하지 않습니다.

```powershell
love src --capture-guide C:/Temp/LaboGuideCapture
python scripts/updateGuideImages.py C:/Temp/LaboGuideCapture
# 일부 화면만 갱신할 때
python scripts/updateGuideImages.py C:/Temp/LaboGuideCapture --only camera-details view-details script-context
```

두 번째 명령은 캡처 원본과 번호 표시를 추가한 가이드 이미지를 갱신합니다. 결과 화면을 확인한 뒤 관련 안내문과 함께 반영합니다.

## Project·Level Script 부착

`project.script.*`와 `level.script.*`는 GUI의 Project·레벨 Inspector와 같은 부착 편집 로직을 사용합니다.

| 명령 끝부분 | 인자·기능 |
|---|---|
| get | 부착 목록·scriptIds·스키마·값·revision 조회 |
| add | `--source` 원본, 선택적 `--script` 부착 이름 |
| remove | `--script` 이름 또는 부착 ID |
| rename | `--script`, `--name` |
| move | `--script`, `--index` (1부터 시작) |
| set | `--property 부착이름.필드`, `--value` 또는 `--value-json` |
| reset | `--property 부착이름.필드` |

Level 명령에는 `--level`을 지정합니다. 생략하면 프로젝트의 기본 레벨을 사용합니다. 쓰기 전 get의 revision을 `--revision`으로 전달하면 외부 변경을 감지합니다. Project 설정은 project.labo, Level 설정은 해당 .level에 저장합니다.

```powershell
love src --cli project script add --project tests/TestProject --source Assets/Examples/ScopeSession.lua --script manager
love src --cli project script get --project tests/TestProject
love src --cli level script get --project tests/TestProject --level Assets/Examples/L_ScriptScopes.level
love src --cli level script set --project tests/TestProject --level Assets/Examples/L_ScriptScopes.level --property scopeLevel.fixedStep --value-json 0.02
love src --cli level simulate --project tests/TestProject --level Assets/Examples/L_ScriptScopes.level --frames 3 --dt 0.033333
```

simulate 결과는 기존 instances에 더해 projectScripts·levelScripts 상태를 반환합니다. Project·Level 콜백도 실행하고, 레벨 전환 시 Project 인스턴스를 유지하며 종료 시 모두 정리합니다.

`asset.delete`는 실제 파일이 없는 등록도 제거합니다. 사용 중인 ID는 기존 복구 창과 같은 참조 보호 정책으로 거부하며, 사라진 파일에는 내용 revision을 지정할 수 없습니다. GUI 삭제는 등록만 제거한 작업도 Undo/Redo할 수 있습니다.

## 기본 사용

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
| level view/render | 초기화 후 활성 View·투영 정보 조회; render는 --output PNG로 실제 출력 |
| level set-camera | 과거 mainCamera 데이터 편집용 호환 명령. 새 구성은 일반 View Script 사용 |
| project rendering-examples | 메인 화면·미니맵 검수 예제 추가 |
| level simulate | --frames 0..10000, --dt, --debug; 파일 수정 없이 load/update 결과와 스크립트 상태 반환, draw는 실행하지 않음. --debug는 에디터 로그·도형 기록도 반환 |
| level pointer | --space world/screen, --x, --y, --width, --height, --events-json; 이벤트마다 최신 카메라로 좌표 변환 |
| instance add/get/list/set/reset/rename/reparent/duplicate/delete | --instance 또는 --instances, --prefab, --parent; 재정의 프로퍼티는 movement.speed처럼 사용자 이름 또는 내부 ID 포함 |
| instance script rename | --instance, --script 이름 또는 ID, --name 새 이름 |
| instance script add/remove/move | --instance, --source, --script, --index; 로컬 부착만 제거·정렬 |
| instance reorder | --instances 또는 --instance, --destination 인스턴스 ID, --mode before/after |
| export | --output; 검증 후 독립 게임 .love 생성 |

정확한 개별 인자는 help와 JSON 요청 예제를 확인합니다. 일반 스크립트 생성은 --type script, 레벨 스크립트는 --type level을 사용합니다. 생성 경로 기본값은 Assets입니다. 새 레벨은 빈 상태이며 카메라를 자동 생성하지 않습니다. LaboEssentials의 Camera·View를 부착하고 View.cameraSource를 지정하거나 Rendering API로 출력을 등록합니다.

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

스크립트 프로퍼티 조회 결과의 schema·values 키는 `사용자이름.프로퍼티`이며 `scriptIds`가 이름과 UUID를 연결합니다. prefab get은 최상위, instance get은 properties.scriptIds에서 확인합니다. 이름 또는 ID로 편집할 수 있으며 저장된 script 참조는 내부 ID를 사용합니다. 과거 Main Camera도 호환 데이터에서 내부 ID를 보존합니다. `instance set`/`prefab set`의 `이름.enabled`로 활성 상태를 편집합니다.

## 일반 Script 이벤트 검증

`level.events`는 레벨을 초기화하고 일반 LÖVE 이벤트를 부착 Script에 전달한 뒤 Transform·프로퍼티 상태를 반환합니다. 레벨을 저장하지 않습니다. 입력 소비를 수행하는 `level.pointer`와 독립된 명령입니다.

```json
{
  "command": "level.events",
  "project": "C:/Games/MyGame",
  "level": "Assets/Examples/L_InputEvents.level",
  "width": 1280,
  "height": 720,
  "events": [
    {"name": "keypressed", "args": ["right", "right", false]},
    {"name": "textinput", "args": ["Hello"]},
    {"name": "mousepressed", "args": [640, 360, 1, false, 1]},
    {"name": "mousereleased", "args": [1500, 900, 1, false, 1]}
  ]
}
```

`Labo-cli.exe --cli --request request.json`으로 실행합니다. `--events-json`으로 이벤트 배열을 전달할 수도 있습니다. 이벤트는 1~1000개이며 이름은 [지원 Script 콜백](guide/lua-api.md#löve-이벤트-콜백)으로 제한됩니다. 좌표는 지정한 화면의 호스트 좌표이고 카메라 레터박스와 게임 영역 원점 변환을 적용합니다. `--debug`는 로그를 결과에 포함합니다. 게임 업데이트·Pointer 판정은 실행하지 않습니다. 실제 Joystick 객체가 필요한 조이스틱·게임패드 이벤트는 JSON CLI로 주입하지 않습니다.

Export의 실제 Host 검증에는 기존 `--verify-game`과 함께 `--verify-events <이벤트 배열 JSON 파일>`을 사용합니다.

```powershell
love Game.love --verify-game report.json --verify-events events.json
```

`events.json`은 위 `events` 배열만 저장한 파일입니다. 실제 Host 콜백을 호출하므로 마우스 이벤트는 기존 Pointer도 처리합니다. 검증은 초기화·한 프레임 업데이트·렌더링 후 이벤트를 전달하고 보고서를 저장한 뒤 종료합니다.

## 오디오 프로퍼티와 임시 세션 종료

기존 `asset import`로 오디오 파일을 가져오고, `instance set` 또는 `prefab set`으로 `audio` 프로퍼티에 에셋 ID를 지정합니다. GUI와 같은 확장자·LÖVE 디코더 검증을 수행합니다.

```powershell
Labo-cli.exe --cli asset import --project D:/Games/MyGame --input D:/Sounds/Tone.wav --folder Assets
Labo-cli.exe --cli instance set --project D:/Games/MyGame --level Assets/Examples/L_AudioLifecycle.level --instance 2 --property AudioLifecycle.sound --value 오디오에셋UUID
Labo-cli.exe --cli level simulate --project D:/Games/MyGame --level Assets/Examples/L_AudioLifecycle.level --frames 1 --debug
```

`level.simulate`, `level.events`, `level.pointer`는 완료·실패 시 임시 Runtime World를 정리하고 초기화한 Script의 unload를 호출합니다. simulate의 레벨 전환 후 최종 World도 정리합니다. 결과의 인스턴스 상태는 종료 직전에 읽고 debug 기록에는 종료 로그도 포함합니다. 에셋 검증·정적 Preview·Export 생성은 게임 load/unload를 실행하지 않습니다. 새 재생 CLI는 추가하지 않고 LÖVE Source 제어는 게임 코드에 둡니다.

## 렌더링 검증

```powershell
love src --cli project rendering-examples --project tests/TestProject
love src --cli level view --project tests/TestProject --level Assets/Examples/L_Multiview.level --width 960 --height 540
love src --cli level render --project tests/TestProject --level Assets/Examples/L_Multiview.level --width 960 --height 540 --output C:/Temp/multiview.png
```

rendering-examples는 동명 에셋이 있으면 중단하며 덮어쓰지 않습니다. 저장소 테스트 프로젝트에는 이미 예제가 있습니다. level.view는 load를 실행해 등록된 활성 View를 조회하고 lifecycleExecuted=true를 반환합니다. views에는 출력 순서·카메라·타깃 종류·해상도·실제 viewport가 들어갑니다. 대표 화면 View의 기존 camera·scale·projected 결과도 유지합니다. level.render는 같은 구성을 실제 렌더링해 PNG로 저장합니다. 출력 부모 폴더는 미리 생성하고, width/height는 양의 정수 픽셀 수를 사용합니다. 창이 없는 CLI는 렌더링에 필요한 최소 그래픽 컨텍스트를 준비합니다. 검증용 World와 GPU 자원은 종료 시 정리합니다.
