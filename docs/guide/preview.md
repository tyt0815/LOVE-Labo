# 미리보기와 Prefab 썸네일

Inspector 하단의 **Preview**는 프로퍼티 스크롤과 분리된 영역입니다. 이미지, Prefab 계층, 선택한 인스턴스와 자손을 보여줍니다. 처음 높이는 에셋 브라우저와 같고, Inspector 프로퍼티와 Preview 사이의 경계를 드래그해 높이를 바꿉니다.

![편집 중인 Prefab 미리보기](images/preview-live.png)

프로퍼티를 바꾸면 저장하지 않아도 바로 반영됩니다. 미리보기는 별도의 오브젝트를 만들며 `load`와 `update`를 실행하지 않습니다. `configure`에서 등록한 배치·영역 바인딩은 미리보기 교체·종료와 구성 실패 때 정리하며, 게임 `load`를 실행하지 않은 미리보기에는 `unload`도 호출하지 않습니다. Project·Level 미리보기에도 같은 규칙을 적용합니다. 게임 초기화 상태에 의존하는 사용자 `draw`는 미리보기에서 오류가 표시될 수 있으므로 선언한 기본값으로도 그릴 수 있게 작성하세요.

**Background** 버튼을 누르면 버튼 바로 아래에 색상 선택 팝오버가 열립니다. 아래 공간이 부족하면 버튼 위로 펼쳐집니다. 색을 지정하지 않으면 현재 테마의 뷰포트 배경색을 사용합니다. Prefab 배경은 해당 에셋의 편집 값으로 저장하며 Undo/Redo와 Save All 대상에 포함됩니다. 이미지·인스턴스 배경은 현재 에디터 세션의 표시 설정입니다.

![배경색 선택기](images/background-picker.svg)

1. 오른쪽 세로 막대에서 색상을 고른 뒤 왼쪽 사각형에서 채도와 밝기를 조절합니다. 드래그하는 동안 실제 Preview 배경에도 바로 표시됩니다.
2. R·G·B에 0–255 숫자를 입력하거나 HEX에 `2468AC`처럼 6자리 값을 입력합니다. 앞에 `#`을 붙여도 됩니다. 유효한 값은 입력 중에도 미리 표시합니다. Enter는 현재 입력을 확정하고 Tab은 다음 입력칸으로 이동합니다.
3. **Theme default**는 테마 기본색을 미리 표시합니다. **Apply**를 누르면 설정을 확정하고 **Cancel**·Esc·팝오버 바깥 클릭은 원래 색으로 되돌립니다. 미리 표시하는 동안에는 Prefab 문서·Undo 이력·썸네일을 변경하지 않습니다. Prefab에서 기본색을 적용하면 저장된 배경색 지정을 지웁니다.

![이미지 미리보기](images/preview-image.png)

## 저장 썸네일

Prefab을 저장하면 저장된 값과 배경색으로 썸네일을 생성합니다. CLI나 외부 도구로 만든 Prefab도 에셋 브라우저에서 처음 표시할 때 썸네일을 자동 생성하므로 저장 버튼을 다시 누를 필요가 없습니다. 브라우저는 유효한 PNG를 재사용하며 매 프레임 Prefab을 렌더링하지 않습니다. 미저장 편집은 Preview에만 보이고 썸네일은 마지막 저장 상태를 유지합니다.

![저장된 Prefab 썸네일](images/preview-thumbnail.png)

참조한 Prefab·스크립트·이미지가 바뀌면 다음 캐시 조회 때 썸네일을 재생성합니다. 외부에서 수정한 파일은 Project → Refresh로 다시 조회할 수 있습니다. 여러 셀은 프레임마다 순차 처리하므로 잠시 기본 아이콘으로 보일 수 있습니다. 시각적으로 그릴 내용이 없거나 생성에 실패하면 기본 Prefab 아이콘을 사용합니다. 실패한 항목은 Refresh 후 다시 시도합니다. 썸네일은 프로젝트 `.labo/Thumbnails` 캐시이며 게임 Export에 포함되지 않습니다.

CLI에서 같은 결과를 확인하려면 다음 명령을 사용합니다. `generated`가 true이면 새로 생성했고 false이면 기존 캐시를 재사용했습니다. load·update는 실행하지 않습니다.

```powershell
love src --cli asset thumbnail --project D:/Games/MyGame --asset Assets/PF_Player.prefab
```

CLI는 보통 창 없이 시작합니다. 새 썸네일이나 PNG 미리보기를 렌더링할 때만 최소 크기의 창을 생성하고 최소화하여 그래픽 컨텍스트를 준비합니다. 이미 열린 에디터 창의 크기는 바꾸지 않습니다. 유효한 썸네일 캐시를 재사용할 때는 창을 생성하지 않습니다.

## CLI

```text
asset.preview --asset Assets/PF_Player.prefab --output D:/Captures/Player.png
asset.preview --level Assets/L_Start.level --instance 3 --output D:/Captures/Instance.png
```

`--size`는 정사각형 PNG 크기이며 16–2048 범위입니다. `--background "[230,230,230]"`으로 캡처 배경을 지정합니다. CLI도 게임 초기화·업데이트 없이 같은 미리보기 렌더링을 사용합니다.
