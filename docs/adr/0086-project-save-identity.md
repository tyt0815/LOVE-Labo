# 0086. 프로젝트 ID로 Export 저장 폴더를 구분한다

- 상태: 채택·구현
- 날짜: 2026-10-16
- 관련: [0028](0028-agent-cli-and-standalone-game-export.md), [0074](0074-scoped-scripts-and-screen-drawing.md)

## 배경과 제약

Export가 모든 게임에 같은 LÖVE identity를 지정하면 같은 이름의 세이브·설정 파일이 충돌한다. 프로젝트 이름·설치 위치 변경은 저장 위치를 바꾸지 않아야 한다. 게임 저장 자체는 일반 스크립트와 LÖVE 파일 API로 구성한다.

## 대안과 판단 기준

- 이름·루트 경로 기반 identity는 이름 변경·이동·동명 프로젝트에서 불안정하다.
- Export마다 UUID를 만들면 같은 게임의 업데이트에서 이전 저장을 찾지 못한다.
- 프로젝트 파일에 안정적인 UUID를 저장하면 재실행·이동·재배포에서도 같은 identity를 유지한다.

## 결정 및 근거

project.labo의 id에 UUID를 보존하고 identity는 labo-<id>다. 새 프로젝트는 생성할 때, 기존 프로젝트는 처음 성공적으로 열 때 ID를 발급해 저장한다. 기존 메타데이터는 다시 읽어 보존하고 잘못된 명시적 ID는 오류로 처리한다. Export conf.lua와 game.json, Project Script 호스트의 id·saveIdentity에 같은 값을 전달한다.

프로젝트 복사는 같은 게임으로 취급해 ID를 유지한다. 별도 게임으로 분리할 때 project.reset-save-identity CLI를 명시적으로 실행한다. 에셋 ID는 바꾸지 않는다. 기존 저장 폴더는 삭제·자동 병합하지 않는다. 고정 identity를 쓰던 이전 배포본의 저장은 자동으로 이전하지 않는다.

Editor Play의 LÖVE identity는 에디터의 설정 수명을 유지한다. 예제는 saves/<saveIdentity>/slot1.json으로 프로젝트별 하위 폴더를 구분하고 전역 setIdentity를 호출하지 않는다. Editor Play와 Export의 물리 저장 위치는 다르며 project.info에서 프로젝트 ID·identity를 조회한다.

## 예상 결과

- 긍정: 서로 다른 게임의 파일 충돌을 방지하고 이름·경로 변경에도 저장 위치가 유지된다.
- 부정: 이전 공용 폴더의 세이브 이전은 게임이 명시적으로 처리해야 한다. 기존 프로젝트 열기는 한 번 프로젝트 파일을 갱신한다.
- 중립: 저장 형식·슬롯·게임 상태 직렬화는 엔진이 강제하지 않는다.
