# 0083. 에디터 창 제어를 메뉴바에 통합한다

- 상태: 채택·구현
- 날짜: 2026-10-16
- 관련: [ADR 0006](0006-widget-canvas-and-asset-views.md), [ADR 0027](0027-windows-editor-packaging.md)

## 배경과 제약

사용자는 Windows 기본 제목 표시줄을 없애고 메뉴바 오른쪽에 최소화·최대화·닫기 버튼을 배치하기를 요청했다. 창 이동·크기 조절과 작업 표시줄을 제외한 최대화 영역을 유지해야 한다. 게임 Export와 Core에는 에디터 창 장식을 추가하지 않는다.

## 대안과 판단 기준

- 기본 제목 표시줄은 네이티브 동작을 유지하지만 요청한 화면을 만들 수 없다.
- 테두리 없는 창에서 마우스 좌표로 위치·크기를 매 프레임 직접 변경하면 운영체제의 창 이동·크기 조절을 중복 구현하게 된다.
- LÖVE가 사용하는 SDL 2의 영역 판별 콜백으로 이동·크기 조절을 운영체제에 맡기고 UI에는 창 제어 버튼만 그린다. SDL 2의 Windows 최대화 동작에서 확인한 작업 표시줄 침범은 해당 창의 비클라이언트 계산으로 보정한다.

## 결정 및 근거

1. `WindowFrame`은 현재 OpenGL 창에 SDL hit-test 콜백을 등록하고 기본 제목 표시줄과 테두리를 제거한다. 메뉴바의 빈 공간은 이동 영역, 일반 창의 가장자리 6px은 크기 조절 영역이다. 메뉴·창 제어 버튼·열린 팝업은 이동에서 제외한다. 최대화 상태에서는 크기 조절 영역을 사용하지 않는다. [SDL 영역 판별 계약](https://wiki.libsdl.org/SDL2/SDL_SetWindowHitTest)을 따른다.
2. `WindowControls`는 메뉴바 오른쪽에 최소화·최대화 또는 복원·닫기를 그린다. Root의 우선 입력 콜백으로 팝업 처리 전에 소비하며 EditorApp에서도 게임 입력·참조 선택 전에 같은 경로를 사용한다. 최소화·최대화·복원은 열린 팝업을 유지하고 진행 중인 포인터 캡처만 정리한다. 메뉴바 빈 공간 더블 클릭은 네이티브 제목 영역 동작을 따른다. 닫기는 `love.event.quit()`을 사용해 기존 종료 처리와 Play 정리를 거친다.
3. 프로젝트 시작 화면도 같은 제어 버튼을 사용하고 상단에 빈 이동 영역을 확보한다. 기존 입력 폼·카드·열기 동작은 유지한다.
4. SDL 2의 borderless 최대화는 실제 검증에서 작업 표시줄 영역까지 클라이언트를 확장했다. Win32 창 스타일에 최대화·시스템 메뉴를 유지하고, 원래 창 프로시저의 `WM_NCCALCSIZE` 계산 뒤 최대화한 클라이언트를 현재 모니터의 작업 영역으로 제한한다. [모니터 작업 영역](https://learn.microsoft.com/en-us/windows/win32/api/winuser/ns-winuser-monitorinfo)은 운영체제에서 조회한다. 복원은 기존 네이티브 창 위치·크기를 사용한다.
5. 두 네이티브 콜백은 JIT 컴파일하지 않고 모듈에서 수명을 유지한다. 종료 시 원래 창 프로시저를 복구하고 SDL 콜백 등록을 해제한 뒤 Lua 콜백 메모리를 반환한다. 지원하지 않는 환경이나 설치 실패에서는 기본 창 장식으로 돌아간다. 현재 제품 대상인 Windows/LuaJIT에서 검증한다.
6. `--verify-window <새 출력 폴더>`는 실제 네이티브 창으로 borderless 상태·영역 판별·최대화·작업 영역·복원·최소화·크기 변경을 검증하고 JSON 결과와 에디터 PNG를 기록한다. `--capture-guide`도 같은 창 장식 경로를 사용한다. 일반 테스트는 실제 창 제어를 모의 처리해 테스트 실행 창을 닫지 않는다.
7. Windows 11에서는 `DWMWA_WINDOW_CORNER_PREFERENCE`에 `DWMWCP_ROUND`를 지정해 일반 창의 네이티브 둥근 모서리를 요청한다. 최대화·스냅의 사각 모서리는 [DWM 정책](https://learn.microsoft.com/en-us/windows/apps/desktop/modernize/ui/apply-rounded-corners)에 맡긴다. 창 영역을 직접 잘라 크기 조절 동작을 바꾸지 않으며, 지원하지 않는 Windows에서는 이 선택적 속성만 생략한다. 네이티브 검증은 속성 적용 여부와 최대화·복원 후 유지 여부도 확인한다. Canvas PNG에는 운영체제가 합성하는 외곽 모서리가 포함되지 않는다.

```text
MenuBar (Widget 상속)·ProjectStart ──포함──> WindowControls
WindowControls ──의존──> WindowFrame·LÖVE 창 제어·정상 종료 이벤트
EditorApp·Root ──우선 입력 콜백──> WindowControls
WindowFrame ──소유──> SDL hit-test 콜백·Win32 창 프로시저 콜백
WindowVerification·GuideCapture·main ──의존──> WindowFrame
Core·게임 Export ──에디터 창 장식 의존 없음
```

## 예상 결과

- 긍정: 제목 표시줄 공간을 메뉴바에 통합하면서 이동·크기 조절·최대화·최소화·닫기를 제공한다. 테마와 창 제어 버튼의 색이 일치한다.
- 부정: Windows와 SDL 2의 네이티브 계약에 대한 유지보수가 필요하다. 시스템 제목 표시줄의 아이콘·제목 텍스트는 화면에서 사라진다.
- 중립: 창 제목은 운영체제의 작업 전환·작업 표시줄 식별용으로 유지한다. 프로젝트 저장과 게임 창 정책은 변경하지 않는다.

## 활성화 중 기본 장식 다시 그리기 방지

비활성 창의 메뉴바를 직접 드래그하는 경로에서는 WM_NCACTIVATE의 lParam을 -1로 전달해 SDL 포커스 처리를 유지하면서 기본 제목 표시줄 다시 그리기를 막는다. WM_NCPAINT·비테마 캡션/프레임 그리기도 기본 처리 전에 종료한다. --verify-window에서 활성·비활성 전환 후 클라이언트와 외부 창 크기가 일치하는지 검사한다. Microsoft의 [WM_NCACTIVATE 계약](https://learn.microsoft.com/en-us/windows/win32/winmsg/wm-ncactivate)을 따른다.

## 최대화 시 작업 표시줄 뒤의 창 영역 제거

클라이언트만 작업 영역으로 제한하면 SDL 좌표에서는 2560×1392로 보이더라도 GetWindowRect는 2560×1440 모니터 전체를 덮었다. 이 상태에서는 작업 표시줄 뒤에도 에디터 창이 남아 작업 표시줄의 합성이 검게 바뀔 수 있다. 기본 제목 표시줄을 복구하거나 Explorer의 상태를 강제 갱신하는 대신 원인인 창의 외곽 최대화 계산을 수정한다.

원래 SDL 창 프로시저가 처리한 뒤 [WM_GETMINMAXINFO](https://learn.microsoft.com/en-us/windows/win32/winmsg/wm-getminmaxinfo)의 최대화 위치·크기를 현재 모니터의 작업 영역으로 덮어쓴다. 위치는 모니터 원점 기준 오프셋을 사용해 음수 좌표의 모니터와 위·왼쪽 작업 표시줄도 처리하고 SDL의 최소·최대 추적 크기는 유지한다. 기존 WM_NCCALCSIZE 보정은 같은 작업 영역을 사용한다. 일반 창의 크기 조절·게임 창 정책은 유지한다.

--verify-window는 SDL 크기 외에 GetWindowRect와 GetClientRect를 직접 확인한다. 연결된 각 모니터에서 최대화, 최대화 상태의 최소화·복원, 일반 창 복원과 재최대화를 반복하며 실제 창 외곽이 작업 영역과 같고 클라이언트가 창 전체를 채우는지 검사한다. 변경 전 네이티브 외곽 검사 실패와 변경 후 통과를 재현했다. 현재 검증 환경은 모니터 1개이며 다중 모니터·작업 표시줄 위치별 실측 결과를 의미하지 않는다.
