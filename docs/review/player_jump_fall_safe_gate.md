# Jump-fall safe candidate review gate

## 상태와 범위

이 검수는 미승인 원화 후보를 위한 것이다. 준비 스크립트 실행 시 신규 jump-fall 원화 `assets/art/player/elven_fighter_jump_fall_v1_candidate_1254x1254.png`가 존재하여 원본을 보존하고 별도 safe 후보를 만들었다. 원본 SHA-256은 `ea0fd5f4a2dd3df11130d740c99698d3001c2ab51d30915b44ba882d4ae6a8f0`, 크기는 869,573바이트다. 준비 스크립트는 실행 전후 원본 바이트가 같음을 확인했다. 원본 파일 자체는 수정하지 않았다.

비교 보드는 v8 idle, 기존 jump-rise safe, jump-fall 원본과 safe를 표시한다. 좌향 행은 각 전체 캔버스를 한 번 수평 미러했다. 이 자료는 기존 검수를 막지 않는다. 원화 생성이나 기계 검사는 시각 승인으로 간주하지 않으며 Player, manifest, 승인 프레임 레지스트리에 연결하지 않는다.

## safe 후보 처리 기준

`tools/prepare_player_jump_fall_safe.gd`는 입력 파일을 수정하지 않고 별도 `assets/art/player/elven_fighter_jump_fall_v1_safe_candidate_1254x1254.png`를 만들었다. 8방향 인접 픽셀이 없는 alpha 픽셀 243개를 정리하고, 투명 여백을 제외한 전체 작품을 비율 유지해 1254×1254 RGBA8 캔버스에 배치했다. 네 방향 alpha 여백은 L/T/R/B 순으로 136/90/137/90px이며, 외곽 투명 테두리와 고립 alpha 픽셀 0개를 확인했다. 투명 픽셀 RGB는 0으로 설정했다.

기계 측정 결과: 원본 비영 alpha 경계 상자는 `x=0..1203, y=0..1253`; 작품 맞춤 비율은 0.871753×였다. safe 경계 상자는 `x=136..1116, y=90..1163`이다. 준비 스크립트 로그에는 원본 SHA-256, 바이트 수, 제거한 고립 픽셀 수, 배율 및 safe 여백이 출력됐다. smoke는 현재 생성된 safe의 포맷·여백·고립 픽셀·원본 바이트 불변성을 확인하도록 작성했으나 이 작업에서는 별도로 실행하지 않았다.

## 동일 게임 캔버스 비교

`assets/art/review/player_jump_fall_comparison.png`의 각 패널은 1254×1254 전체 캔버스를 동일한 192×192 크기로 축소해 비교한다. 좌향 행은 원본 캔버스를 수평으로 한 번 미러한 결과다. 비교 대상은 v8 idle, 기존 jump-rise safe, jump-fall 원본, jump-fall safe다. 체커 보드는 투명 영역을 보여주고, 노란 십자 표식은 각 패널에서 alpha가 가장 낮은 행의 연속 구간 중심을 가리킨다.

준비 스크립트는 192px 실루엣 경계/높이, 상체 및 하체 alpha 중심, 전체 alpha 중심, 두 부츠 주변의 지정 ROI alpha 중심, 최저 alpha 행의 연결 anchor를 출력한다. 부츠 ROI는 이미지에서 각 신발이 보이는 위치를 기준으로 정한 측정 창이다. 최저 anchor는 양쪽 발을 각각 검출하지 않는다. 최저 anchor는 rise safe `(59,167)`, fall 원본 `(104,184)`, fall safe `(104,172)`다. fall safe는 rise safe보다 실루엣 높이가 10px 크다(159px 대 149px, 약 6.7%); 이는 전체 캔버스 배율에서 관측한 크기 차이며 체감 팝의 승인 판정은 아니다.

| 192px 측정 | v8 idle | jump-rise safe | jump-fall 원본 | jump-fall safe |
|---|---:|---:|---:|---:|
| 실루엣 경계 (x,y,w,h) | 42,12,117,171 | 55,19,103,149 | 49,3,117,182 | 56,14,102,159 |
| torso 중심 y | 82.25 | 82.90 | 81.38 | 81.31 |
| 하체 중심 y | 125.90 | 114.65 | 122.34 | 117.71 |
| 아래쪽 부츠 ROI alpha 중심 (x,y) | 54.71,164.29 | 60.36,157.64 | 105.81,171.14 | 103.86,166.22 |
| 접힌 쪽 부츠 ROI alpha 중심 (x,y) | 147.59,170.77 | 127.30,127.92 | 110.35,139.52 | 111.29,140.26 |

ROI 중심은 지정된 부츠 주변 창 안의 alpha 가중 중심이므로 신발만 분리한 segmentation은 아니다. 두 부츠가 지면에서 떨어져 보이는지, 하강 자세의 자연스러움, identity는 이미지에서 사람이 확인해야 한다. 원본과 safe 사이에 배치·크기 차이가 보이므로 발 anchor 정렬 및 rise→fall 전환 크기 팝도 수동 검수 대상으로 남긴다.

## 사람 검수 — 미완료

- [ ] jump-fall에서 양쪽 부츠가 모두 공중에 있고, 서로의 상대 위치가 의도한 하강 자세로 읽히는지 확인한다.
- [ ] 무릎 굽힘, 몸통 기울기, 망토/포니테일 흐름이 하강 동작으로 읽히는지 확인한다.
- [ ] 얼굴, 귀, 머리, 의상, 장갑, 양쪽 부츠가 같은 elven fighter identity로 유지되는지 확인한다.
- [ ] rise와 fall의 발 anchor가 접지 기준에 맞고, 공중 이동량에 불연속이 없는지 확인한다.
- [ ] 전체 192px 캔버스 비교에서 rise→fall의 실루엣 높이와 체감 크기 팝이 수용 가능한지 확인한다.
- [ ] 좌우 미러가 한 번만 적용되고 장비/표식이 의도치 않게 이중 반전되지 않았는지 확인한다.
- [ ] 승인 전까지 후보를 본편이나 manifest에 연결하지 않는다.

## 재현

```powershell
godot --headless --path . --script res://tools/prepare_player_jump_fall_safe.gd
godot --headless --path . --script res://tests/player_jump_fall_safe_smoke.gd
```

이 작업에서는 `prepare_player_jump_fall_safe.gd`를 실행해 safe 후보와 비교 보드를 생성했고, 실행은 코드 0으로 끝났다. 실행 로그에는 `user://logs`와 Windows 인증서 저장소 접근 경고가 있었다. 별도 smoke 검수는 실행하지 않았다. smoke 통과 여부와 무관하게 위 사람 검수는 필요하다.
