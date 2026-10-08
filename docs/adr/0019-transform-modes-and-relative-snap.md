# 0019. 2D 변환 모드와 시작점 기준 스냅

- 상태: 채택
- 후속 부분 대체: [ADR 0021](0021-begin-play-and-orthographic-rotation.md)의 X/Y 직교 투영 회전·100 단위 그리드
- 후속 부분 대체: [ADR 0020](0020-independent-snaps-and-inspector-selection.md)의 모드별 스냅 저장·회전 정규화
- 날짜: 2026-10-09
- 부분 대체: [ADR 0018](0018-translation-gizmo-and-snap-controls.md)의 자유 이동 사각형·원점 정렬 스냅·이동 전용 도구
- 확장: [ADR 0017](0017-components-instance-properties-and-prefab-placement.md)의 Sprite 위치·렌더링 계약

## 배경과 제약

사용자는 이동 중심을 하얀 원으로 바꾸고 스냅을 월드 원점 대신 드래그 시작점 기준으로 적용하도록 요청했다. 이동·회전·스케일 모드와 UE 단축키를 사용하고 월드 축과 기즈모 색을 통일해야 한다. 2D XY 평면, 중앙 월드 원점, Y 양수 아래 방향, Edit/Runtime 분리를 유지하며 기존 레벨 파일도 읽는다.

## 대안과 판단 기준

- [UE 공식 Transform 문서](https://dev.epicgames.com/documentation/en-us/unreal-engine/transforming-actors-in-unreal-engine)의 회전 링·스케일 축 끝 큐브와 중앙 비례 스케일 핸들을 2D로 적용한다. X/Y축 회전은 평면 밖 기울기를 요구하므로 Z축 하나만 제공한다.
- 스케일을 화면 축으로 표시하면 회전된 Sprite의 실제 크기 축과 맞지 않는다. 이동은 월드 축, 스케일은 로컬 축을 사용하며 색 역할은 공유한다.
- 축마다 스케일에 고정 값을 더하면 비균등 스케일의 비율이 깨진다. 중앙 드래그는 두 초기 스케일에 같은 비율을 곱한다. 화면 이동에 지수 배율을 적용해 확대/축소를 대칭적으로 느끼게 한다.
- 데이터 기본값을 항상 저장하면 기존 파일 diff가 불필요하게 커진다. 로드 시 rotation=0, scaleX/Y=1로 복원하고 기본값은 저장에서 생략한다.

## 결정 및 근거

1. `TransformGizmo`가 이동·회전·스케일 핸들의 화면 기하와 변환 계산을 담당한다. 이전 TranslationGizmo를 대체한다. SceneView는 선택·drag·mode·snap 상태를 소유하고 계산을 위임한다.
2. 이동 중심은 반경 7px의 하얀 원이며 원형으로 히트 검사한다. X/Y 핸들과 월드 X/Y축은 같은 `axisX/axisY` 색 역할을 사용한다. 활성·호버는 두께로 구별하며 색을 다른 축 색으로 바꾸지 않는다.
3. 스냅은 `시작 좌표 + 반올림(누적 이동량 / 단위) × 단위`로 적용한다. 단위 100과 시작 X=20이면 120/-80에 도달한다. 복제 위치는 원본 기준, 새 Prefab 배치는 기준 객체가 없으므로 커서 위치를 사용한다. 회전·스케일 스냅은 이번 범위에 포함하지 않는다.
4. 회전은 Z축 링을 사용한다. 각도 차이는 ±180도 경계에서 감싸서 누적하고 중앙을 통과할 때는 각도 갱신을 보류한다. 화면의 양수 각도는 시계 방향이며 `transform.rotation`은 도 단위다.
5. 스케일은 로컬 X/Y축 끝 사각형과 중앙 하얀 사각형이다. 축 끝은 해당 스케일만 변경하며 중앙은 화면 오른쪽/위 이동에서 두 축 비율을 유지하며 확대한다. 반대 방향은 축소하고 드래그 최소 스케일은 0.01이다. 음수·0·비유한 스케일은 저장·Inspector에서 거부한다.
6. 공개 LObject Transform에 `rotation`, `scaleX`, `scaleY`를 추가한다. Core Transform 모듈의 검증·복사·직렬화·좌표 역변환을 Level, Runtime, Inspector, Sprite 렌더링이 공유한다. 컴포넌트 상대 위치도 owner의 스케일·회전을 적용한다. 히트 검사는 같은 변환의 역변환으로 계산한다.
7. `ViewportControls`는 Widget을 상속하고 Scene Canvas가 소유한다. 이전 SnapControls를 대체하여 Move/Rotate/Scale 버튼과 기존 스냅 필드를 제공한다. W/E/R로 모드 선택, Space로 순환한다. 텍스트 편집·팝업·Play가 단축키보다 우선한다. 모드 변경 중 드래그는 원래 Transform으로 복원한다.
8. Escape는 위치·회전·스케일 전체를 복원한다. Level 저장·재열기·복제와 Runtime 초기화는 모든 Transform 값을 독립적인 테이블로 복사하며 Play 변경을 편집 데이터에 반영하지 않는다.

## 예상 결과

- 긍정: 상대 스냅으로 기존 위치 오프셋을 보존하고, 세 모드가 Inspector·저장·Sprite 선택과 같은 의미로 동작한다. UE 단축키와 축 색 규칙을 공유한다.
- 부정: 기존 절대 격자 정렬 방식과 드롭 스냅이 바뀐다. 중앙 스케일의 조작량은 화면 픽셀 기준이며 음수 스케일을 통한 뒤집기는 지원하지 않는다.
- 중립: 3D 기울기·부모 객체 Transform 계층·회전/스케일 스냅·피벗 편집은 포함하지 않는다. Prefab에는 기존 컴포넌트 상대 위치를 유지하고 배치 인스턴스의 Transform을 확장한다.
