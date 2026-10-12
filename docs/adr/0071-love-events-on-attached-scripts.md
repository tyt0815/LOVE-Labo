# 0071. LÖVE 이벤트를 부착 스크립트에 전달한다

- 상태: 승인·구현
- 관련: [0069](0069-script-identity-and-editor-authored-attachments.md), [0067](0067-fixed-play-pause-stop-controls.md), [0068](0068-camera-letterbox-for-world-and-screen-ui.md), [0045](0045-bounds-and-game-pointer-components.md)

## 배경과 제약

게임 기능은 일반 Lua·LÖVE API로 구현하고 Labo는 편집 데이터와 실행 구조를 연결한다. Host가 최상위 LÖVE 콜백을 소유하므로 프로젝트가 직접 덮어쓰면 에디터 입력과 충돌한다. 부착 Script에 update·draw처럼 이벤트 콜백을 선언하는 경로가 필요하다. Editor Play·Export·CLI가 같은 실행 계약을 사용해야 한다.

## 대안과 판단 기준

- 전역 love 콜백을 프로젝트에서 교체하면 에디터·프로젝트 간 소유권과 복구 문제가 생긴다.
- 입력 액션·소비·우선순위 시스템을 추가하면 LÖVE 연결이라는 요구를 넘어선다.
- LÖVE 이름·인자를 유지한 부착 스크립트 브로드캐스트는 기존 생명주기와 활성 상태를 재사용한다.

## 결정 및 근거

키보드·문자·마우스·터치·조이스틱·게임패드와 focus·mousefocus·visible·resize를 Script에 제공한다. ScriptEvents가 허용 목록·순서·오류 처리와 화면 좌표 변환을 공유한다. World는 dispatchEvent로 위임한다. 부모부터 자손, 동일 객체의 부착 순서로 호출하며 enabled=false는 제외한다. 이벤트 시작 시 후보를 고정하고 각 호출 직전에 객체·부착의 생존과 활성 상태를 확인한다. 새 Spawn은 다음 이벤트부터 받는다. 반환값은 무시하고 예외만 실행 오류로 처리한다.

마우스·터치는 실제 게임 영역 왼쪽 위 기준의 픽셀 좌표로 전달한다. 카메라 논리 해상도로 재조정하거나 월드 좌표로 바꾸지 않는다. dx·dy와 기타 인자·장치 식별자는 그대로 유지한다. 영역 밖 새 입력은 제외하고 영역 안에서 시작한 입력의 move·release는 영역 밖에서도 받는다. 이 기록은 입력 소비와 무관하며 Pause·포커스 상실·Stop에서 정리한다. Pointer의 판정·소비·캡처는 기존 선택적 기능으로 유지하며 일반 이벤트 전달 뒤에 실행한다.

Editor는 Game View 포커스에서 키보드·문자·컨트롤러 입력을 전달하며 팝업·스포이드·Pause 중 입력은 전달하지 않는다. 에디터 단축키는 우선한다. 휠은 키보드 포커스와 무관하게 커서가 실제 게임 영역에 있을 때 전달한다. focus·mousefocus·visible은 호스트 창 상태다. resize는 실제 게임 영역 크기이며 초기 실행과 레벨 전환 시 새 World의 첫 update 전에 전달한다. Editor의 영역 변화는 재배치와 update 전 검사로 감지하며 Pause 중 변화는 재개 시 반영한다. Export는 World 교체 직후와 창 resize 시 실제 영역을 계산한다.

quit·파일/폴더 드롭·threaderror·lowmemory·displayrotated 및 run·conf·errorhandler는 이번 Script 이벤트 범위에 포함하지 않는다. 종료 취소나 파일 임포트처럼 호스트 고유 의미를 무심코 스크립트 전체에 전달하지 않는다. 레벨 Lua 콜백은 이번에 확장하지 않는다.

level.events는 같은 ScriptEvents 경로에 이벤트를 주입하고 결과 상태를 읽으며 문서를 저장하지 않는다. Joystick 객체가 필요한 이벤트는 CLI JSON으로 대체하지 않는다. Export의 --verify-events는 실제 Host 콜백 검증에 사용한다.

## 예상 결과

- 긍정: 일반 LÖVE 이벤트 이름으로 게임 코드를 작성하며 별도 입력 시스템을 강제하지 않는다.
- 부정: 전역 이벤트이므로 게임의 UI와 플레이어 중 누가 처리할지는 게임 코드가 결정해야 한다. 에디터 단축키·포커스 때문에 Editor와 Export의 입력 수신 범위에는 명시적 차이가 있다.
- 중립: 기존 Pointer 계약, 부착 구조, 데이터 형식과 플러그인 제공 원칙은 유지된다.
