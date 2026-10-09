# Player 후보 동작 원화 검수 게이트

## 범위와 판정

`scenes/review/player_candidate_motion.tscn`은 본편과 격리된 후보 검수 장면이다. Player, animation manifest, allowlist에는 등록하지 않으며 이 장면의 후보를 승인하지 않는다. 그림 사이 프레임은 합성하지 않는다.

| 항목 | 확보 원화와 표시 | 현재 판정 |
|---|---|---|
| run v4 | `elven_fighter_run_stride_v4_safe_candidate_1254x1254.png` | **미수용 · 동일 보폭.** 앞/뒤 다리 리드와 팔 스윙이 이전 후보와 같아 반대 보폭이 아니다. |
| Num4 safe | `elven_fighter_skill1_rush_contact_v1_safe_candidate_1254x1254.png` | 직선 돌진 접촉 후보. safe 파생 원화이며 미승인이다. |
| Num5 접촉 후보 | `elven_fighter_skill2_spin_contact_v1_candidate_1254x1254.png` | **파일 확보 · 미승인 · 회전 미입증.** 화면상 뻗은 주먹 포즈라 원형 회전 실루엣으로 판정하지 않는다. |

Num4의 직선 방향 실루엣과 접촉 발 후보는 실제 원화에서 검수할 수 있다. Num5 후보 파일은 확보했지만 화면상 뻗은 주먹 포즈로 보여 원형 회전과의 실루엣 차이 또는 회전 지지발 후보를 판정할 수 없다고 표시한다. 지지발은 접촉 후보이며 단일 원화로 확정하지 않는다. 접촉 장면만으로 움직임 중 팝을 판정할 수 없고, Num4/Num5 모두 startup 및 recovery 원화가 없으므로 이를 보간해 완성 애니메이션으로 표시하지 않는다.

검수 창은 1920×1080이며 각 원화는 alpha 5% 실루엣 높이를 게임 기준 192px로 맞춘 뒤 3배 확대한다. Num4 safe, run v4 판정, Num5 확보 후보를 우향과 좌향으로 각각 실제 Window post-draw 렌더링해 스트립에 기록한다. 노란 점은 alpha 하단 중심 참고, 민트 점은 수동 지지발 후보가 지정된 기존 run 원화에만 나타난다.

## 조작

- 숫자 1–8: 대기, 달리기, 점프, 공격 startup, 승인 접촉, run v4 판정, Num4 safe 직선, Num5 후보·회전 판정 대기 선택
- A/D: 좌향/우향, Space: 재생/중단
- 좌/우 화살표: 선택 상태 내 다음/이전 원화
- 위/아래 화살표: 상태 변경

## 실제 Window 스트립 생성

```powershell
godot --path . res://scenes/review/player_candidate_motion.tscn -- --review-capture
```

출력은 `assets/art/review/player_candidate_motion_strip.png`이다. 6개 타일은 행마다 run v4, Num4 safe, Num5 확보 후보를 우향과 좌향으로 캡처한다. Num5 타일에는 미승인·회전 미입증 판정을 표시한다. GUI Window 렌더가 필요하며 headless 결과를 실제 화면 비교로 간주하지 않는다.

## Smoke 검사

```powershell
godot --headless --path . --script res://tests/player_candidate_motion_smoke.gd
```

Smoke는 후보 상태 분리, run v4 미수용 문구, Num5 후보 파일 확보와 미승인·회전 미입증 표시, 방향 전환, 캡처 산출물, manifest 불변을 확인한다. 시각 품질, 지지발 확정, 움직임 중 팝, 원화 승인을 자동 판정하지 않는다.

