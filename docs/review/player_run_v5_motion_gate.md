# Player run v5 motion review gate

## 검수 범위

- 실제 1920×1080 windowed Godot Window에서 본편 `scenes/player/player.tscn`의 Player controller와 `PlayerVisualAnimator` 시계를 구동한다.
- 입력을 오른쪽에서 왼쪽으로 바꾸어 본편 방향 전환을 캡처한다. 원화 후보는 본편 PlayerArt의 메모리 texture만 교체하며 Player animation manifest, pose bank, runtime registry에 등록하지 않는다.
- v1 원본과 v5 후보는 파일 바이트에서 직접 읽어 alpha 경계를 자른 다음 1254×1254 투명 캔버스 안쪽에 90px 여백으로 임시 fit한다. safe 산출물은 입력으로 사용하지 않는다.
- 민트 점은 v1/v5 각 원본에서 수동 선택한 지지 신발 위치를 임시 fit 좌표로 옮긴 시각 후보, 주황 점은 골반 근사점이다. alpha 경계는 실제 접지/물리 판정이 아니다.

## 확보 현황

- 기존 v1 원본 후보: `elven_fighter_run_stride_v1_candidate_1254x1254.png` 확보.
- run_stride_v5 원본 후보: `elven_fighter_run_stride_v5_far_leg_forward_candidate_1254x1254.png` 확보. SHA-256 `310F7A6F95B0966247754986095042D275839891B80C73C187383B35D920F6E2`, 1,186,277 bytes. 별도 v5 safe: 1254×1254 RGBA8, alpha 여백 L/R/T/B `102/102/125/125px`, 고립 픽셀 0개. v1과 같은 방향 접촉 자세로 표시해 교대 재생했다.
- 실행 시 3열 strip에서 v1과 v5의 팔다리/골반 구도를 대조했다. 캡처에서 v5는 v1의 같은 접촉 보폭으로 보여 독립된 반대발 접지 및 발 교차를 입증하지 못했다.

## 판정 기준 및 현재 판정

- 192px 실루엣 목표와 캡처별 실제 화면 alpha 높이, 골반/발 anchor 좌표 및 인접 샘플의 수직 pop을 캡처 로그로 남긴다.
- 좌우 이동은 본편 입력과 `facing_direction`으로 확인한다. 좌우 방향은 `VisualRoot`의 기존 scale mirror만 사용한다.
- 접지 후보와 발 교차는 캡처 strip에서 시각 검토한다. 단일 포즈 반복은 반대 보폭을 입증하지 못하며 같은 보폭을 정상 run cycle로 인정하지 않는다.
- v5는 확보되었지만 같은 보폭으로 판정되어 정상 run cycle로 인정하지 않는다. v1/v5 반복은 반대발 교차를 보여주지 않는다.
- 캡처 측정(2026-10-10 재검수): alpha 실루엣 높이 190.17–193.95px (192px 목표 근접), 인접 프레임 높이 최대 변화 3.42px, 발 anchor 후보 최대 수직 변화 8.01px. 골반/발 마커는 source alpha 위치를 기준으로 화면에 겹쳐 표시한다.
- 이 strip은 네 위상 시점의 원화 비교다. 한 장씩인 v1/v5 원화 사이의 완전한 보폭 loop 주기나 순간 pop 없는 연속 주기는 승인하지 않는다.
- 미승인 원화 승인: 미수행. 본편 런타임 등록: 없음.

## 증거

- `assets/art/review/player_run_v5_motion_strip.png`: 실제 Godot Window post-draw 프레임으로 만든 좌/우 이동 및 run 위상 비교 strip.
- `assets/art/review/player_run_v5_antiphase_comparison.png`: v1 safe와 v5 safe의 전체 캔버스 192px 우/좌향 고정 비교.
- 실행 로그의 `SAMPLE`, `METRIC`, `SOURCE`, `GATE` 행: 화면 실루엣 높이, anchor 좌표/pop, v5 확보 여부와 미승인/미등록 상태.
