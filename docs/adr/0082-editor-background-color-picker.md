# 0082. 편집 배경은 테마를 기본으로 하고 공용 색상 선택기로 조절한다

- 상태: 채택·구현
- 날짜: 2026-10-16
- 부분 대체: [ADR 0060](0060-isolated-live-previews-and-saved-thumbnails.md)의 흰색 기본 배경과 숫자 입력 UI, [ADR 0067](0067-fixed-play-pause-stop-controls.md)의 스냅 우측 배치
- 관련: [ADR 0081](0081-ue-inspired-default-theme.md)

## 배경과 제약

Preview의 흰색 기본 배경이 어두운 기본 테마와 맞지 않는다. 편집 Scene View에서도 배경색을 선택하되 게임 실행의 배경과 렌더링 계약은 유지해야 한다. 기존 Prefab의 명시적인 배경색과 Undo/Redo·저장 동작도 보존한다.

## 대안과 판단 기준

- 숫자 입력만 유지하면 원하는 색을 찾기 어렵다. 팔레트와 RGB·HEX를 함께 제공한다.
- 원형 색상환과 사각형 SV 팔레트 중 채도·밝기를 각각의 축으로 조절할 수 있는 사각형을 선택한다. 색상은 옆의 세로 막대에서 고른다.
- 배경을 게임 카메라나 레벨 프로퍼티로 저장하면 편집 표시와 게임 출력을 혼동한다. Scene 배경은 세션 상태로 둔다. Prefab은 기존 에셋별 저장 계약을 유지한다.
- 배경을 흰색 또는 새 어두운 색으로 고정하면 다른 테마와 어긋난다. 지정을 생략하면 현재 테마의 `viewportBackground`를 사용한다.

## 결정 및 근거

1. Preview 버튼은 `Background`, 배경과 그리드를 함께 설정하는 Scene View 버튼은 `Colors`로 표시한다. 각각의 설정 범위를 이름에 드러낸다. 공용 `ColorPicker`에서 SV 평면·색상 막대·RGB 0–255·6자리 HEX를 제공한다. HEX는 선택적인 `#`을 허용한다.
2. 선택기는 해당 버튼 아래에 붙는 팝오버로 연다. 아래 공간이 부족하면 위로 펼치고 화면 경계를 보정한다. 화면 전체를 어둡게 덮지 않으며 그림자를 추가하지 않는다. 팔레트 드래그와 유효한 RGB·HEX 입력은 실제 화면에 즉시 미리 표시한다. 저장값과 분리된 일시 표시 상태를 사용해 문서 변경·이력·썸네일 생성 없이 확인하고, Apply로 한 번 확정한다. Cancel·Esc·바깥 클릭은 일시 상태를 지워 원래 색으로 돌아간다. 바깥 클릭을 뒤쪽 편집으로 전달하지 않는다. Apply는 왼쪽, Cancel은 오른쪽에 둔다.
3. Scene 팝오버는 Background·Grid lines 탭으로 배경과 격자 선 색을 각각 조절하고 함께 확정·취소한다. 기본색은 각각 `viewportBackground`·`grid`를 따른다. Theme default는 선택한 탭의 명시적 색 지정을 제거한다. Scene의 두 색과 이미지·인스턴스 Preview 배경은 에디터 세션 설정이다. Prefab 배경은 기존 `previewBackground`에 저장하며 기본색 복원 시 필드를 제거한다. 게임 데이터 형식과 Play 배경은 변경하지 않는다. Play·Pause에서는 Scene Colors 버튼을 비활성화한다.
4. Viewport Toolbar에서 스냅은 좌측, 실행 버튼은 중앙, Colors는 우측에 둔다. 겹칠 폭이면 실행 행 아래로 내리고 필요하면 Colors도 별도 행에 둔다.
5. `Color` 모듈에서 RGB 검증, HEX·HSV 변환과 테마 기본값을 공유한다. Preview·Scene View는 선택기와 무관하게 이 모듈을 사용한다.
6. 썸네일 영수증 버전을 2로 올리고 기본 배경색을 기록한다. 테마 기본색이 달라지면 이전 썸네일을 재생성해 흰색 캐시가 남는 것을 막는다. 캐시 일관성을 위해 명시적 배경이 있는 Prefab도 함께 무효화한다.
7. 기존 `--capture-guide`에 `--theme`를 추가해 사용자 설정 파일 변경 없이 밝은·어두운 테마를 검증한다. 배경 선택기와 편집 배경 캡처도 포함한다.

```text
ViewportToolbar ──포함──> 스냅 / 실행 / Colors 컨트롤
ViewportToolbar·PreviewPanel ──생성──> ColorPicker (Widget 상속)
ColorPicker ──변경·닫기 콜백──> SceneView·PreviewPanel의 일시 표시 상태
ColorPicker ──확정 콜백──> SceneView·PreviewPanel의 설정값
ColorPicker·SceneView·Preview·PreviewCache ──의존──> Color ──의존──> Theme
```

## 예상 결과

- 긍정: Preview와 Scene의 색상 선택 방식이 같고, 숫자를 몰라도 색을 고르거나 HEX로 정확히 지정할 수 있다.
- 부정: 좁은 화면에서는 툴바 높이가 늘어난다. 첫 실행과 테마 변경 후 기존 썸네일이 다시 생성된다. Scene 배경은 에디터 재실행 시 초기화된다.
- 중립: 게임 렌더링·카메라·레벨 저장값은 유지한다. 기존 Prefab의 명시적인 배경색은 그대로 사용한다.
