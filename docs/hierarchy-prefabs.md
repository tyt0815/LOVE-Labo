# 계층 Prefab

Hierarchy에서 루트 오브젝트를 우클릭하고 `Create Prefab...`을 선택한다. 폴더와 이름을 지정하면 루트의 현재 값, 컴포넌트 값과 모든 자손 오브젝트를 저장한다. 원래 레벨의 오브젝트는 그대로 남는다. CLI에서는 `prefab create --instance <authoring-id> --name PF_Name`을 사용하며 `--level` 생략 시 기본 레벨을 읽는다.

Prefab Inspector의 순서는 오브젝트 계층 → 선택 오브젝트의 Parent Class → 오브젝트 프로퍼티 → 컴포넌트 계층 → 선택 컴포넌트 프로퍼티다. 인스턴스 Inspector는 오브젝트 프로퍼티 → 컴포넌트 계층 → 컴포넌트 프로퍼티만 표시한다. Save는 Inspector 제목 오른쪽에 있다. Prefab 루트 Transform은 표시하지 않으며 자손 Transform은 부모 오브젝트 기준이다.

오브젝트 계층의 부모를 우클릭하여 `Add Child → Pick Source...`을 선택하고 Asset Browser 또는 Hierarchy에서 대상을 클릭한다.

- LObject Lua 클래스: 클래스 기본값을 사용하는 자식.
- Prefab: 원본 Prefab을 참조하는 자식. 원본 값 변경을 상속한다.
- 레벨 인스턴스: 현재 값과 자손을 복사한 자식. 원래 인스턴스를 옮기지 않는다.

성공하면 새 자식을 선택한다. Esc·우클릭은 취소하며 잘못된 대상은 오류를 표시하고 선택 모드를 유지한다. 일반 에셋 선택·이동·레벨 배치 드래그의 의미는 그대로다. Inspector 계층에 직접 드롭하는 기능은 제공하지 않는다.

내부 `object` 참조는 Prefab 계층의 스포이드로 선택하고 찾기는 해당 노드를 잠시 강조한다. 새 계층을 생성하거나 전체 계층을 복제하면 내부 기본 참조는 새 자손을 가리킨다. 캡처 범위 밖 레벨 객체 참조가 있으면 생성이 거절된다. None이나 내부 대상으로 바꾼 뒤 다시 캡처한다.

부모 Prefab의 자손은 안정적인 ID로 상속하며 자식 Prefab에서 바꾼 프로퍼티·Transform 필드만 override로 저장한다. 레벨에 배치하면 자손도 Hierarchy에 나타난다. 연결된 자손을 원래 그룹 밖으로 분리하면 현재 값을 보존한 독립 가지가 되고 원래 그룹은 그 가지를 다시 생성하지 않는다.

연결된 자손만 캡처하거나 복사하여 원래 Prefab 루트를 제외하는 경우에는 Lua 클래스와 현재 유효 값을 저장한다. 원래 루트가 자손에 적용한 프로퍼티·컴포넌트 override도 포함하며 캡처된 가지 안의 참조는 새 가지에 연결한다. 인스턴스 전체 복사는 원본 연결과 자손 제거 경로를 함께 보존하므로 삭제한 손자도 다시 생성되지 않는다.

따로 배치한 Prefab 계층을 자식으로 붙인 뒤 함께 캡처해도 그 중첩 원본의 자손 ID를 보존한다. 원본 클래스가 없는 기본 LObject 자손도 저장·배치·생성할 수 있다. 저장된 레벨의 구체화 자손이 최신 원본에서 사라졌으면 Play와 Export한 게임에서 해당 가지를 초기화 전에 제거한다. 제거된 객체를 가리키는 참조는 자동으로 다른 대상에 연결하지 않고 누락 오류를 표시한다.

두 Inspector 트리는 처음에 각각 3행 높이로 열리며 아래쪽 손잡이로 크기를 조절한다. 긴 트리에는 자체 스크롤바가 표시된다. Hierarchy, Asset Browser의 폴더·파일, Inspector 전체, 선택 다이얼로그와 드롭다운도 overflow일 때 스크롤바를 표시한다.

저장 형식·상속과 생성 규칙은 [ADR 0042](adr/0042-hierarchy-prefab-definitions.md), 스크롤·크기 조절은 [ADR 0043](adr/0043-list-scrollbars-and-resizable-inspector-trees.md)를 따른다. 기존 단일 오브젝트 Prefab도 계속 읽는다. `world:spawnLObject(template, transform, overrides)`는 자손을 함께 생성하고 루트 LObject를 반환한다.
