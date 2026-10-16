# 스테이지 제작

Game-cli.exe help 또는 schema로 명령과 인자를 조회합니다. Labo나 Python 설치는 필요하지 않습니다. EXE 옆의 DLL과 license-love.txt도 함께 배포합니다.

```powershell
./Game-cli.exe inspect --workspace C:/Games/MyGame/Content
./Game-cli.exe add --workspace C:/Games/MyGame/Content --beat 4 --lane 3
love Game.love --workspace C:/Games/MyGame/Content
```

게임의 R 키로 CLI 저장 결과를 다시 읽습니다. 좌우 키로 첫 노트를 옮기고 S로 저장합니다. 스테이지 이름과 파란 노트가 같은 StageModel에서 검증됩니다. GUI의 미저장 수정은 CLI가 읽지 못하며, 외부 수정 후 S를 누르면 revision 충돌을 반환합니다. R은 미저장 변경을 버립니다.

복잡한 명령은 --request <UTF-8 JSON 절대 경로>로 전달합니다.

```json
{"command":"add","workspace":"C:/Games/MyGame/Content","arguments":{"beat":8,"lane":4}}
```

stdout은 {version:1,ok:true,result:...} 또는 {version:1,ok:false,error:...} JSON입니다. 종료 코드는 성공 0, 실패 1입니다. --result <절대 경로>는 같은 응답을 파일에 저장합니다. create는 기존 파일을 덮어쓰지 않습니다. add의 revision 인자는 inspect에서 읽은 revision과 같아야 합니다.

Stage.json: version=1, name=문자열, notes=[{beat=0 이상 수, lane=1~4 정수}]. 확장자나 도메인 형식은 게임이 정의합니다. 작업 폴더는 미리 생성하며 상대 파일 경로는 폴더 밖으로 나갈 수 없습니다. 작업 중 .labo-content.lock으로 같은 규칙을 사용하는 편집을 직렬화합니다. 강제 종료로 남은 잠금은 실행 중인 프로세스가 없을 때만 제거합니다.

배포용 Content/Stage.json은 빌드 예제의 초기 데이터입니다. 재Export는 이 파일을 다시 복사합니다. 제작한 콘텐츠는 별도 작업 폴더에서 관리하세요. --workspace를 생략한 게임은 저장 폴더 아래 자체 예제 데이터를 사용하고 화면에 경로를 표시합니다.
