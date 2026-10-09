# 오프라인 애니메이션 수용 갤러리 handoff

## 열기

프로젝트 루트에서 `docs/review/animation_acceptance_gallery.html`을 파일 탐색기나 브라우저로 연다. 서버, 네트워크, 빌드가 필요 없다. 갤러리의 PNG와 Window 캡처, 근거 문서는 프로젝트 안의 상대경로를 사용한다.

`tools/build_animation_acceptance_gallery.ps1`은 등록된 리뷰 항목을 읽고 파일 존재 여부를 확인해 HTML을 재생성한다. 새 항목의 경로와 판정 질문을 갱신한 뒤 Windows PowerShell 5.1에서 다음을 실행한다.

```powershell
.\tools\build_animation_acceptance_gallery.ps1
```

출력 대상은 `docs/review/animation_acceptance_gallery.html`이다. 이미지 입력이나 근거 문서가 없으면 깨진 링크 대신 `누락 파일`을 표시한다. turn은 전용 원화가 없는 상태이므로 기존 Window turn strip과 실제 상태 캡처로 연결한다.

## 포함 범위

- 기존 승인: v8 idle과 attack1/2/3 contact. 승인은 기존 manifest 및 프레임 레지스트리에서 읽은 상태이며 이 갤러리가 등록을 변경하지 않는다.
- 수동 검수: run stride v1/v2/v4, turn 상태, jump rise/fall, hit, skill1 돌진, skill2 v1/v2 회전 포즈, attack1/3 startup.
- 각 카드: 원본 PNG의 192×192 전체 캔버스 표시, 좌우 미러 비교, 선택 safe 파생본, 후보별 identity·접지/anchor·프레임 팝 점검 질문, 캡처/문서 링크.
- 전역 참고: 실제 Window 애니메이션 상태 매트릭스와 QA gameplay Window 캡처.

3× 버튼은 각 192px 표시를 nearest-neighbor 방식으로 576px로 바꾼다. 좌우 방향 이미지는 후보 하나를 수평으로 미러해 비교하므로 별도 원화나 별도 승인 포즈가 아니다.

## 수동 판정과 승인 경계

textarea는 현재 페이지의 임시 메모이며 저장/내보내기하지 않는다. 페이지는 `data/art/reviewed_frame_allowlist.json`이나 manifest를 읽어 승인 판정을 재계산하지 않고, 어떤 레지스트리 파일에도 쓰지 않는다. 카드의 상태 문구는 작성 시점의 검수 문서와 manifest를 근거로 갱신해야 한다.

검수자는 [수동 원화 검수 기록 양식](records/REVIEW_TEMPLATE.md)을 별도로 열어 후보별로 `수용 제안`, `수정 요청`, `반려` 중 하나와 근거를 직접 기록한다. 갤러리 생성이나 스모크 통과는 시각 승인 증거가 아니다. 승인 프레임 등록은 별도 승인 절차에서 수행한다.

## 링크 점검 스모크

```powershell
.\tests\animation_acceptance_gallery_smoke.ps1
```

스모크는 HTML 생성, 필수 카드/문구, 모든 로컬 이미지·문서 링크, turn 원화 누락 표시, 레지스트리 쓰기/브라우저 저장 기능 부재를 점검한다. 이는 파일 wiring 확인이며 캐릭터 identity, 접지, 프레임 팝 또는 사람의 수용 판정을 확인하지 않는다.
