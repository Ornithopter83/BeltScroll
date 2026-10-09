# 오프라인 애니메이션 수용 갤러리 handoff

## 열기와 재생성

프로젝트 루트에서 `docs/review/animation_acceptance_gallery.html`을 브라우저로 직접 연다. 서버나 네트워크 연결은 필요 없다. PNG, Window 캡처와 근거 문서는 프로젝트 상대경로로 연결한다.

`tools/build_animation_acceptance_gallery.ps1`은 카드 목록을 만들고 모든 상대 링크 대상을 확인해 HTML을 생성한다. Windows PowerShell 5.1에서 실행한다.

```powershell
.\tools\build_animation_acceptance_gallery.ps1
```

기본 갤러리는 기존 17개 카드, run v3, turn v1, 확보된 turn v2를 별도 카드로 유지한다. 각 PNG 원본이 없을 때는 깨진 이미지 대신 누락 상자를 표시한다. turn v1의 원본·safe 및 turn v2의 원본·safe가 확보되어도 승인 상태로 바뀌지 않는다.

신규 turn v2 원본은 지정 canonical 경로 `assets/art/player/elven_fighter_turn_rear_mid_v2_candidate_1254x1254.png` 또는 대체 원본 `assets/art/player/elven_fighter_turn_pivot_v2_candidate_1254x1254.png`에서 찾는다. 현재 대체 경로 원본이 확보되어 별도 safe 후보 `assets/art/player/elven_fighter_turn_pivot_v2_safe_candidate_1254x1254.png`, 비교판, 실제 Window 캡처와 함께 v1과 분리된 미승인 카드로 표시한다. v2 두 부츠 landmark는 골반 아래 약 61px 간격이며 v8 idle 대비 alpha bounds 폭은 18.9 percent 좁고 높이는 11.0 percent 크다. 지지발 좌표는 수동 추정으로 anchor에 정렬했고 실제 뒤꿈치 접촉·회전축·크기 팝은 사람 수용 전까지 미승인이다.

## 보존된 판정과 자료

- Run v1~v5 원화와 비교·Window 근거를 유지한다. 현재 판정은 동일 보폭이며 반대발 교대가 입증되지 않아 전부 미수용이다. 어떤 후보도 본편에 연결하지 않는다.
- Turn v1 원본과 safe 후보, 실제 Window 캡처와 비교판을 유지한다. 후방 3/4 identity는 읽히지만 달리기형 보폭 및 idle 대비 약 14.4% 폭·13.5% 높이의 크기 팝 때문에 turn 키포즈로 미수용한다. 지지발 접촉선·좌우 대응·anchor는 미검증이다.
- Num5 v1 및 v2는 모두 직선 타격형으로 읽혀 회전 접촉 원화로 미수용한다. v2 safe 및 비교/Window 자료는 검토 근거로만 연결한다.
- Hit 후보의 검정·적색 복장과 idle의 청록·녹색 복장 차이 및 anchor 이동 위험을 표시한다. Jump rise/fall의 발 접지 및 jump anchor는 미검증이며, rise/fall safe 실루엣 높이 6.7% 차이와 체공 미입증 기록을 유지한다.
- 수용된 기존 카드, run v3·v5, 절차적 turn 검수 및 Markdown 수동 기록 다운로드는 계속 제공한다. 창 캡처·자동 검사 결과는 사람의 승인으로 취급하지 않는다.

## 화면 확인과 수동 기록 다운로드

각 원화는 1254×1254 전체 캔버스를 동일하게 192×192px로 표시한다. 좌향은 같은 원본에 CSS 수평 반전을 한 번 적용한다. `3× 확대`는 최근접 보간으로 576×576px 표시한다. 원본을 클릭하면 원본 파일이 열린다. 카드마다 연결된 PNG, 실제 Window 캡처 및 근거 문서는 상대 링크다.

각 카드에서 판정 제안, 근거, 검수자, 검수 일시, 실제 화면 조건을 입력하고 그 카드의 **이 후보 검수 기록 Markdown 다운로드** 버튼을 직접 누른다. 클릭 순간 REVIEW_TEMPLATE 호환 Markdown을 브라우저 다운로드로 만든다. 검수 일시는 비우면 다운로드 시각과 시간대를 기록한다. 입력은 새로고침 후 보존되지 않는다.

수용 제안은 승인이 아니다. 페이지는 자동 저장하지 않고 네트워크로 전송하지 않으며 승인 레지스트리, manifest 또는 allowlist를 읽거나 쓰지 않는다. 다운로드된 기록은 검수 제안으로 남고, 승인 등록은 별도 승인 절차에서만 수행한다.

## 링크 및 기능 점검

```powershell
.\tests\animation_acceptance_gallery_smoke.ps1
```

스모크는 카드 수와 원본·safe·캡처·문서 링크의 실제 존재, turn v1 판정 및 v2 확보/미확보 표기, run v1~v5 동일 보폭 미수용, Num5 v1/v2 직선 타격형 미수용, hit 복장 차이와 jump anchor 미검증을 확인한다. 192px/576px, 좌우 미러, 수동 Markdown 다운로드 페이로드 및 모든 로컬 상대 링크도 점검한다. 이 검사는 연결과 다운로드 계약을 확인하며 사람의 시각 승인이나 자동 승인을 수행하지 않는다.
