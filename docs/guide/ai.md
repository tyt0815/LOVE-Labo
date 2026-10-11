# AI 작업 시작

새 프로젝트의 AGENTS.md와 Docs/EngineGuide.md를 먼저 읽고 이 가이드와 설치된 CLI help를 확인합니다. 웹 문서와 설치 버전의 API가 다르면 해당 버전의 로컬 안내와 실제 API를 기준으로 합니다.

모든 콘텐츠는 Assets에 둡니다. Lua 파일은 스크립트이며 Prefab이 생성할 오브젝트 계층·스크립트 구성을 저장합니다. 엔진 코어를 직접 수정하지 않고 공개 Lua API와 CLI를 사용합니다. .meta ID는 파일 이동에도 유지합니다.

```powershell
Labo-cli.exe --cli help
Labo-cli.exe --cli project validate --project D:/Games/MyGame
Labo-cli.exe --cli script create --project D:/Games/MyGame --name Movement
Labo-cli.exe --cli prefab create --project D:/Games/MyGame --name PF_Player
Labo-cli.exe --cli prefab script add --project D:/Games/MyGame --prefab Assets/PF_Player.prefab --source Assets/Movement.lua --script movement
Labo-cli.exe --cli level simulate --project D:/Games/MyGame --frames 60 --dt 0.0166667
```

Lua는 self.owner를 통해 오브젝트를 사용합니다. properties에 선언한 값만 노출합니다. 스크립트는 Prefab에서 추가·제거·정렬하며 배치 인스턴스에서는 값만 재정의합니다. GUI의 초안은 저장 후 CLI로 수정합니다. CLI 변경은 GUI Undo에 포함되지 않습니다.

level.simulate로 초기화·업데이트 결과를 확인하고 level.pointer로 입력을 재현합니다. 렌더링은 실제 Play 또는 독립 Export 실행으로 확인합니다. 복잡한 명령은 --request UTF-8 JSON 파일을 사용하고 반환한 에셋 ID를 후속 명령에 재사용합니다.

![Prefab의 스크립트 그룹](images/prefab-details.png)

명령 전체는 [CLI 사용법](../cli-and-export.md), 데이터 계약은 [계층 Prefab](../hierarchy-prefabs.md)을 참고하세요.
