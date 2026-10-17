# 0091. 레벨 목록 검증과 준비 상태의 정리 책임을 공유한다

- 상태: 채택·구현
- 날짜: 2026-10-17
- 확장: [0028 공용 로딩](0028-agent-cli-and-standalone-game-export.md), [0085 공개 배치 API](0085-public-projection-layout-and-input.md), [0087 객체 유지 전환](0087-carried-objects-across-levels.md)

## 배경과 제약

Level과 World가 lobjects의 table 여부만 확인하고 ipairs로 읽으면 문자열 키나 구멍 뒤의 객체를 조용히 버린다. WorldLoader.prepare는 load 없이 configure 바인딩을 만들지만 실패 반환과 일부 검증 호출에서 정리가 빠졌다. GameView도 투영 제공자나 디버그 출력의 예외가 그래픽 상태 복구를 우회할 수 있었다. Core의 Editor 독립성과 기존 빈 Lua 목록의 호환성을 유지해야 한다.

## 대안과 판단 기준

- Editor와 Runtime에 배열 검사를 각각 두면 데이터 계약이 다시 갈라진다.
- 저장 문서의 버전·Prefab 계약 전체를 Core로 옮기면 Runtime이 필요로 하지 않는 저작 책임까지 들어간다. 이번에는 공통으로 필요한 연속 배열 형태 검사만 Core에 둔다.
- prepare가 자동으로 결과를 폐기하면 Play·전환·미리보기에서 사용할 수 없다. 준비 상태를 받는 호출자와 검증 결과만 받는 호출자를 구분한다.
- 호출자가 개별 오류를 잡는 것만으로는 이미 변경한 그래픽 상태를 복구하지 못한다. 상태를 시작한 GameView가 복구 책임도 가진다.

## 결정 및 근거

1. core.Array.isDense는 양의 연속 정수 키로만 구성한 table을 검사한다. 빈 table은 기존 빈 레벨과 호환되게 허용한다. Level.fromData와 World.fromLevelData가 이를 공용으로 사용하며 객체별 저작·실행 검증은 기존 책임에 둔다.
2. WorldLoader.prepare는 구성 실패·예외 시 부분 World와 자신이 생성한 Project 호스트를 폐기한다. 전환을 위해 빌린 Project 세션은 종료하지 않는다. load를 시작하지 않은 Script에는 unload를 호출하지 않고 configure 바인딩만 정리한다.
3. prepare 성공 시 호출자가 World를 소유하여 활성화하거나 dispose한다. WorldLoader.validate는 준비·폐기까지 담당하고 객체 수만 반환한다. CLI 검증·편집 후 검증·플러그인 사용 검증·게임 Export는 이 함수를 사용한다. 기존 CLI 명령과 응답 형식은 유지한다.
4. World.dispose는 아직 활성화되지 않아 Project.world가 nil인 준비 상태의 전용 Project 호스트도 정리한다. preserveProject=true나 다른 World에 연결된 세션은 유지한다.
5. GameView.draw는 투영 평가부터 게임·디버그 출력까지 하나의 보호 구간에서 수행한다. 자신의 그래픽 상태를 복구한 뒤 오류를 호출자에게 전달한다.

```text
Level · World ──의존──> core.Array (연속 배열 형태 검사)
CLI · Export · PluginOperations ──의존──> WorldLoader.validate
WorldLoader.validate ──준비·폐기──> World ──소유──> 전용 Project 호스트
전환 후보 World ──공유 참조──> 기존 Project 호스트 (실패 시 유지)
GameView ──시작·복구──> 출력 중 그래픽 상태
```

상속·인터페이스 계층은 추가하지 않는다.

## 예상 결과

- 긍정: 잘못된 목록을 조용히 축소하지 않으며 검증 실패·성공 양쪽에서 임시 바인딩을 정리한다. 게임 출력 오류가 에디터 그래픽 상태로 새지 않는다.
- 부정: 이전에 일부 항목을 무시하고 읽던 비정상 레벨은 이제 오류로 거절한다.
- 중립: 파일 버전·게임 공개 API·CLI 명령은 바꾸지 않는다. 사용자 Lua의 임의 전역 변경·외부 부작용을 되돌리는 트랜잭션은 제공하지 않는다.
