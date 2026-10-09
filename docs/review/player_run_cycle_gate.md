# Player Run Stride 후보 격리 검수

## 상태

- v1 원화: `assets/art/player/elven_fighter_run_stride_v1_candidate_1254x1254.png` 확인.
- v2 반대 보폭: `assets/art/player/elven_fighter_run_stride_v2_opposite_candidate_1254x1254.png` 확인. 검수 후보이며 미승인.
- 검수 보드: [player_run_cycle_review.png](../../assets/art/review/player_run_cycle_review.png)는 실제 Godot Window의 post-draw 캡처 타일 9장으로 생성했다.
- 승인 상태: 후보 검수 전용. 본편 Player와 `data/art/animation_manifest.json`에 등록하지 않는다.

## 실행

프로젝트 루트에서 실제 표시 가능한 Godot Window로 실행한다.

```powershell
godot --path . --script tools/capture_player_run_cycle_review.gd
```

도구는 1920×1080 Window의 post-draw 프레임을 세어 반복 재생과 상태 캡처를 만들고, 캡처 타일을 `player_run_cycle_review.png`로 저장한다. headless 실행은 성공으로 처리하지 않는다.

## 해석 규칙

v1/v2를 A/B로 교대 표시하고 양쪽 방향, 루프 경계 전후, 정지→달리기→정지, 방향 반전을 캡처한다. 이번 실행에서는 두 원화 각각 8회씩 총 16회 post-draw 렌더 프레임을 관측했고, 두 원화 cycle period는 240ms 설정 대비 약 243ms로 측정됐다. Window 상태별 180ms 샘플은 5~6 렌더 프레임이었다. 좌향은 각각의 그림을 수평 반전한다. 캡처에서 실제 원화 수와 Window가 그린 프레임 수를 별도로 기록한다.

민트 표시는 원화에서 사람이 지정한 지지발 후보이고, 노랑 표시는 alpha bounding box의 하단 중앙 참고점이다. 투명 경계의 가장 낮은 점은 실제 지지발과 같다고 가정하지 않는다. v1 후보 점은 (1090,1200), v2는 (1168,1225)로 두었고, 기준선에 대한 오차는 각각 약 2.6px과 5.5px로 후보 점 기준 차이는 약 8.2px이다. 실제 발 접지로 확정하기 전 시각 검토가 필요하다. 표시 높이는 v1 346.6px, v2 342.3px(차이 4.3px)이며 너비는 약 334.8px 대 342.7px이다. 원화 크기와 발 후보 차이는 수치 참고이고, 골반 연결, 포니테일 뿌리, 경계 팝은 보드에서 시각 검토해야 한다.

## 제한

현재 v1과 v2 후보 두 장을 확인해 교대 재생한다. Window의 실제 그리기 프레임과 두 그림의 240ms 설정 주기(이번 실행 측정 약 243ms)를 함께 기록한다. 240ms는 후보 재생 설정이며 승인된 목표 주기가 아니다. 발 후보 좌표와 골반·포니테일 연결, 경계 팝은 여전히 캡처 기반 시각 검토이며 자동 승인하지 않는다. 이 문서와 검수 도구는 원화 승인이나 게임 애니메이션 연결을 수행하지 않는다.






