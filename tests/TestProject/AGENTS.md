# LÖVE Labo 프로젝트 AI 작업 지침

- 실행 계약: LÖVE 11.5 + LuaJIT / Lua 5.1, attached-script 개발 버전.
- 작업 전 https://tyt0815.github.io/LOVE-Labo/guide/ai/ 와 관련 API 문서를 확인한다.
- 웹 문서와 설치 버전이 다르면 Docs/EngineGuide.md, CLI help, 실제 제공 API를 기준으로 한다.
- 게임 코드는 Assets에서 수정한다. 엔진 코어·DLL·배포 파일은 직접 수정하지 않는다.
- 에셋 생성·이동·삭제·배치는 Labo-cli.exe 명령을 우선 사용하고 .meta ID를 보존한다.
- GUI에서 연 문서를 저장한 뒤 CLI로 수정한다. CLI 변경은 GUI Undo에 포함되지 않는다.
- LObject는 Transform과 자손 계층을 소유한다. Lua 스크립트를 여러 개 부착하며 self.owner가 오브젝트다.
- Prefab에서 스크립트를 추가·제거·정렬한다. 배치 인스턴스에도 로컬 스크립트를 추가한다. 상속한 오브젝트·스크립트의 구조는 고정하고 값만 재정의한다.
- 클래스·파일 이름은 PascalCase, 변수·함수는 camelCase, 상수는 UPPER_SNAKE_CASE, 들여쓰기는 공백 4칸이다.
