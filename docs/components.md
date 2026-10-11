# 부착 스크립트와 프로퍼티

LObject에 스크립트를 여러 개 부착합니다. 모든 스크립트가 소유 오브젝트의 Transform을 사용하므로 서로 다른 위치가 필요하면 자손 LObject를 만듭니다.

```text
LObject — 소유 → Transform, 자손 LObject, Script 인스턴스 목록
Script ← 상속 — Camera / Sprite / Pointer / Rect / Canvas / 사용자 정의
Bounds ← 의존 — Sprite / Pointer / Rect의 선택적 영역 계산
```

Prefab Inspector의 **Add Script**에서 기본 스크립트나 Lua 에셋을 고릅니다. `s1` 같은 부착 ID는 프로퍼티 재정의·참조의 키이며 파일 이름과 별개입니다. 그룹의 Remove로 제거하고 헤더 우클릭으로 순서를 바꿉니다. 같은 Lua 파일을 여러 번 부착해도 상태는 독립적입니다. **배치 인스턴스에서는 추가·제거·정렬할 수 없고 값만 수정합니다.**

| 스크립트 | 기능 |
|---|---|
| Camera | viewWidth, viewHeight, zoom; 공용 카메라 투영 |
| Sprite | image, fillParent, sortingOrder; 이미지 그리기 |
| Pointer | 사각형 또는 boundsSource, inputPriority, blockPointer; 포인터 소비 |
| Rect | width, height, fillParent; 보이지 않는 영역 |
| Canvas | width, height, matchViewport; 화면 좌표계 시작 |

선언된 `properties`만 Inspector에 표시됩니다. `group`을 지정하면 별도 그룹으로 묶이며 기본 그룹은 부착 ID와 스크립트 타입입니다. number/string/boolean 외에 image, object, script, prefab를 지원합니다. `lobjectTemplate`은 prefab의 호환 별칭입니다. object는 같은 계층·레벨의 LObject, script는 그 오브젝트의 특정 부착 인스턴스입니다.

이미지·Prefab·부모 Prefab은 스포이드로 에셋을 선택합니다. 오브젝트·스크립트 참조는 인스턴스를 선택하며 스크립트가 여러 개면 부착 ID를 고릅니다. 찾기는 에셋을 잠시 강조하거나 대상을 프레이밍합니다. 일반 선택과 충돌하므로 Inspector 필드에 드래그앤드롭하지 않습니다.

숫자·문자 편집은 저장 전에도 초안에 즉시 반영됩니다. 재설정은 해당 상속 기본값으로 돌아갑니다. Prefab은 형식 4, 레벨은 형식 3입니다. 옛 컴포넌트 코드·Prefab은 자동 변환하지 않습니다. Sources 이동과 코드 전환은 별개이며 자세한 결정은 [ADR 0050](adr/0050-attached-scripts-and-unified-assets.md)을 참조하세요.
