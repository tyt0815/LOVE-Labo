# 저장과 게임 Export

## 문서 저장

Inspector 편집은 저장 전에도 초안과 편집 화면·Play에 적용됩니다. Prefab의 Save 또는 Ctrl+S로 현재 문서를 저장합니다. 인스턴스 override는 레벨에 저장됩니다.

Ctrl+Shift+S 또는 **File → Save All**은 변경된 레벨·Prefab 목록을 표시합니다. 기본으로 모두 체크되어 있으며 저장할 대상만 선택해 확인합니다. 취소하면 초안을 유지합니다. 아직 저장 경로가 없는 레벨은 경로 지정이 필요합니다.

Undo/Redo는 프로퍼티·Transform·계층과 에디터에서 실행한 에셋 생성·삭제·이동·이름 변경을 다룹니다. CLI나 외부 편집기의 변경은 GUI Undo에 포함되지 않습니다.

## 독립 실행 게임

**File → Export Game**에서 `.love` 출력 경로를 지정합니다. 엔진의 core/project/runtime과 프로젝트 소스·에셋이 포함되고 에디터 UI와 테스트는 포함하지 않습니다. 현재 레벨과 Prefab 초안을 패키징에 사용하므로 Export는 원본 문서를 저장하는 작업과 구분됩니다. 재현 가능한 빌드를 남기려면 먼저 Save All로 원하는 문서를 저장합니다.

```powershell
./build/windows/Labo-cli.exe --cli export --project D:/Games/MyGame --level Assets/L_Start.level --output D:/Games/MyGame/Build/Game.love
love D:/Games/MyGame/Build/Game.love
```

CLI Export는 디스크에 저장된 프로젝트를 읽습니다. GUI의 미저장 초안을 다른 프로세스의 CLI가 읽을 수는 없으므로 저장을 먼저 완료하세요. 출력은 Assets/Sources 바깥에 둡니다.

현재 `.love` 게임은 LÖVE 런타임으로 실행합니다. Windows 에디터 자체 배포와 게임 Export는 서로 다른 작업입니다. 상세 패키지 검증은 [CLI와 Export](../cli-and-export.md), [패키징](../packaging.md)에 있습니다.
