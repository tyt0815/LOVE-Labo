# 다중 선택과 오브젝트 계층

- 에셋 파일/폴더 목록과 썸네일의 빈 곳에서 왼쪽 드래그하면 겹치는 항목을 영역 선택한다. Ctrl+클릭은 추가/해제, Shift+클릭은 범위 선택, Ctrl+A는 전체 선택이다.
- 선택한 에셋을 폴더로 드래그하거나 우클릭 Move로 함께 이동한다. Delete 또는 우클릭 Delete는 확인창을 연다. 다중 이동·삭제는 Ctrl+Z 한 번으로 복구하고 Ctrl+Shift+Z로 다시 실행한다. 이름 변경은 단일 선택에서 제공한다.
- Hierarchy와 뷰포트는 선택 상태를 공유한다. 빈 곳 드래그로 영역 선택, Ctrl+클릭으로 추가/해제한다. Hierarchy의 Shift+클릭은 범위 선택이다. Inspector는 마지막 선택한 객체의 프로퍼티를 표시한다.
- 뷰포트에서 선택한 객체 또는 이동 기즈모를 드래그하면 함께 이동한다. 부모와 자식이 함께 선택되어도 자식이 두 번 움직이지 않는다. 회전·스케일은 선택한 최상위 객체 각각에 적용한다. Esc로 취소한다.
- Hierarchy에서 선택한 객체를 다른 객체에 드롭하면 자식으로 부착한다. 현재 부모 위에 다시 드롭하면 최상위로 분리한다. 다중 선택에서는 선택된 최상위 객체들이 모두 해당 부모의 직접 자식일 때 함께 분리한다. 빈 곳에 드롭하거나 Detach from Parent를 실행해도 최상위로 분리한다. 월드 위치는 유지하며 로컬 회전·스케일은 새 부모 기준으로 유지한다. 이후 부모의 위치·회전·스케일을 따른다. 자기 자신이나 자손 아래로는 부착할 수 없다.
- Hierarchy와 뷰포트 우클릭 메뉴는 Duplicate, Delete, Frame Selection, Detach from Parent, Select All을 제공한다. 복제와 삭제는 자손도 포함하고 부모·자식 동시 선택은 중복 처리하지 않는다. 복제된 프로퍼티의 기존 인스턴스 참조는 원래 참조 대상을 유지한다.
- 여러 Prefab을 뷰포트나 Hierarchy로 드롭할 수 있다. Hierarchy 객체 위로 드롭하면 해당 부모의 로컬 원점에 배치한다. 새 이름은 `PF_Enemy 1`, `PF_Enemy 2`처럼 Prefab 파일 이름과 숫자로 지정한다.

```text
Level / World가 오브젝트 목록 소유
부모 LObject
├─ 루트 SceneComponent → 자손 컴포넌트 (해당 LObject가 소유)
└─ 자식 LObject (부모 Transform에 종속)
   ├─ 루트 SceneComponent → 자손 컴포넌트
   └─ 자손 LObject
```

오브젝트 부착과 컴포넌트 상속·부착은 별개다. 런타임 `object:attachTo(parent)`는 로컬 Transform을 유지하며 부모를 바꾸고 `object:attachTo(nil)`은 분리한다. `object:getWorldTransform()`은 합성된 월드 행렬을 반환한다. `object.transform`은 루트의 실제 로컬 Transform이다. CLI의 `instance reparent`는 에디터 드래그와 같이 월드 위치를 유지한다.
