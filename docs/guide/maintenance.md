# 문서 빌드와 화면 캡처

사용자 가이드 원본은 이 저장소의 docs에 있습니다. 개발 중 임시 동작을 모두 문서화하지 않고, 커밋 전에 사용자 동작·UI·API·CLI가 변경됐는지 확인해 관련 가이드·예제·이미지를 같은 커밋에서 갱신합니다.

## 로컬 미리보기

```powershell
python -m pip install -r docs/requirements.txt
python -m mkdocs build --strict
python -m mkdocs serve
```

기본 테마는 무료 MkDocs readthedocs입니다. 사이드바 목차와 검색을 제공하며 생성 결과는 build/docs-site에 둡니다. 공개 문서는 [LÖVE Labo 사용자 가이드](https://tyt0815.github.io/LOVE-Labo/)에서 확인합니다. 2026-10-10 첫 배포에서 주요 문서·화면 이미지·검색 데이터의 공개 응답을 검증했습니다.

## 실제 화면 재생성

```powershell
love src --capture-guide C:/Work/new-capture-folder
python scripts/updateGuideImages.py C:/Work/new-capture-folder
python -m mkdocs build --strict
```

capture-guide는 새 출력 폴더와 그 아래 임시 예제 프로젝트를 만들고 레벨·카메라·Sprite·Prefab·Game View를 PNG로 캡처한 뒤 종료합니다. 기존 폴더는 덮어쓰지 않습니다. 사용자 프로젝트를 조작하지 않습니다. 원본은 guide/images/original, 주석 이미지는 guide/images에 둡니다. 원·번호 표시는 SVG 오버레이로 만들며 원본 픽셀은 변경하지 않습니다.

UI 배치가 바뀌면 updateGuideImages.py의 표시 위치도 실제 화면을 보고 갱신합니다. 스크린샷과 단계 설명은 함께 검토합니다.

## 자동 배포

`.github/workflows/docs.yml`은 PR에서 strict 빌드를 검증하고 main에 push되면 GitHub Pages로 배포합니다. 저장소 Settings → Pages의 Source는 GitHub Actions를 사용합니다. 공개 저장소의 기본 github.io 주소에는 별도 도메인이 필요하지 않습니다.

배포 경로는 [GitHub Pages 공식 워크플로 안내](https://docs.github.com/en/pages/getting-started-with-github-pages/using-custom-workflows-with-github-pages)를 따릅니다. MkDocs 빌드는 [공식 배포 안내](https://www.mkdocs.org/user-guide/deploying-your-docs/)를 참고합니다.
