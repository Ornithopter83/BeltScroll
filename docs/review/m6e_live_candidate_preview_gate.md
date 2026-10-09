# M6E 현행 v8 / 다크 판타지 후보 Window 검수

## 범위와 소스

`scenes/review/m6e_live_candidate_preview.tscn`은 루트가 독립 `Window`인 승인 전용 검수 씬이다. 왼쪽에는 현행 `elven_fighter_reference_v8_1254x1254.png`, 오른쪽에는 `elven_fighter_dark_fantasy_attack1_sheet_v1_candidate_1254x1254.png`의 2×2 셀을 좌상→우상→좌하→우하 순서로 표시한다. 양쪽 모두 실제 `forest_ruins_v1_1920x1080.png` 배경 위에서 alpha 기준 높이 192 화면 픽셀, y=850 공통 발 기준선으로 비교한다.

후보 셀은 원본 시트에서 독립 crop하며 보간·회전·변형 없이 120ms 간격으로 재생한다. 화면에 직전 셀 대비 변경 픽셀 수, 현재 셀 alpha 경계 수치, 하단 alpha 중심 추정 좌표를 보여 준다. Space 또는 화면 버튼은 재생/일시정지, 좌우 화살표와 버튼은 프레임 단위 이동, R 또는 반복 버튼은 반복 전환, Home은 첫 프레임 선택이다. 반복이 꺼진 상태에서 수동 이동은 양 끝 셀에서 멈춘다.

## 결함 표시 및 판정 한계

현재 셀의 alpha 경계 T/B/L/R 픽셀 수와 하단 alpha 중심 추정 좌표를 표시한다. 경계에 alpha가 남으면 셀 절단 또는 이웃 셀 혼입 가능성을 빨강으로 표시한다. 민트색 하단 추정 표식과 기준선은 기계적 시각 참고값이다. 실제 지지발, 프레임 의도 순서, 인물 동일성 및 애니메이션 완성도는 사람 검토가 필요하다.

## 격리 경계

미리보기 자산과 실행 코드는 `scenes/review`, `scripts/review`, `assets/art/review`, `tests`, `docs/review`에 한정한다. PlayerArt, manifest, allowlist, 런타임 애니메이션 등록, 충돌·전투 판정은 변경하지 않는다. 후보 승인도 수행하지 않는다. `assets/art/review/m6e_live_candidate_preview.png`는 2560×1440 실제 Window 캡처의 정지 보드이며, 동작은 Window에서 직접 확인한다.

실행: `godot --path . scenes/review/m6e_live_candidate_preview.tscn`

정적 스모크 확인: `godot --headless --path . --script tests/m6e_live_candidate_preview_window_smoke.gd`
