# 0051. 목록 안 이름 편집과 Prefab 소속 표시

- 상태: 승인·구현
- 소속 배경색과 묶음 판정은 [ADR 0053](0053-prefab-source-membership-lines.md)으로 대체한다.
- 루트 Rename의 파일명 변경 계약은 [ADR 0054](0054-prefab-root-object-names.md)로 대체한다.
- 파일명의 여러 줄 편집과 계층 드래그·상속 제한은 [ADR 0052](0052-local-scripts-and-fixed-inherited-topology.md)를 따른다.
- 관련: [0041](0041-inspector-picking-over-drag-exceptions.md), [0050](0050-attached-scripts-and-unified-assets.md)

## 배경과 제약

새 창에서 이름을 입력하는 흐름은 계층·파일 목록에서 이름을 바꾸려는 작업과 떨어져 있었다. Prefab 여부만 나타내는 아이콘은 어느 배치 인스턴스에 속하는지 설명하지 못했다. 일반 에셋 선택이 Inspector를 전환한다는 계약은 유지한다.

## 대안과 판단 기준

모달 이름 변경과 목록 안 입력을 비교하여 해당 항목과 입력 위치가 일치하는 목록 안 입력을 선택했다. Prefab 아이콘·글자색·배경색을 비교하여 가독성과 묶음 인식을 기준으로 옅은 배경색을 선택했다. 제한된 색상은 재사용되므로 소속 관계의 근거는 계층과 원본 참조이며 색상은 보조 표시다.

## 결정과 근거

Parent Prefab은 선택 오브젝트의 원본을 편집하는 현재 동작을 유지한다. Add Child는 빈 LObject를 바로 추가한다. New → Prefab은 빈 루트로 파일을 생성한 후 해당 파일 이름을 목록 안에서 편집한다. Enter나 바깥 클릭으로 확정하고 Esc로 취소하며 생성 후 취소는 생성된 파일을 남긴다. 파일은 확장자를 보존하고 에셋 이동 로직으로 이름을 변경하여 ID와 Undo를 유지한다. Prefab Inspector 루트 이름 변경은 원본 파일 이름 변경이다.

Hierarchy와 Prefab 내부 계층에 옅은 소속 배경을 표시하고 선택한 묶음을 강조한다. 수동으로 붙인 독립 오브젝트는 Prefab의 생성 자손으로 취급하지 않는다. 중첩 Prefab은 별도 묶음을 시작하며 돋보기는 원본 에셋을 잠시 강조한다. 에셋 아이콘에는 Level·Lua·Prefab 등 첫 글자를 대문자로 한 확장자를 표시하고 한 줄에 맞춘다.

## 결과

- 긍정: 생성·이름 변경이 해당 목록에서 이어지며 Prefab 소속과 원본 찾기를 함께 제공한다.
- 부정: 좁은 목록에서는 긴 이름이 가려지므로 편집 중 가로 스크롤을 사용한다. 색만으로 모든 묶음을 고유하게 구분할 수는 없다.
- 중립: 기존 CLI의 asset.rename, instance.rename, prefab.child.rename 및 무참조 자손 생성 계약을 재사용한다.
