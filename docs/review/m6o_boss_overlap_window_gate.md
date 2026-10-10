# M6O Boss 겹침·F10 Window 검증 게이트

## 실행 증거

- 실행 방식: production Player/Boss 씬을 비-headless Godot Window에서 실행하고, 실제 물리 프레임의 `AttackArea.get_overlapping_bodies()`와 Player/Boss HP를 관찰했다. 공격은 Boss AI가 위치를 보고 시작했다.
- 입력 출처: `source=auto_input_event`; 물리 키보드 검증은 아니다. 캡처된 Window: Windows, 1280×720, 10 프레임. F10 ON 관측=true, 같은 windup Window의 OFF/ON 프레임 차이 확인=true.
- 직접 `receive_hit` 호출 또는 HP 대입으로 타격/KO를 만들지 않았다. KO는 Player J 공격의 production Area2D overlap으로 확인했다.

## 실측

| 시나리오 | 상태 | Player 기준 위치 | 범위 및 깊이 | 실제 overlap | HP | 판정 |
|---|---|---:|---|---|---:|---|
| slash_right_inner | active | (86.0, 0.0) | r=67.0, 중심 Δy=0.0 | body=true / area=false | 5→3 | 기대대로 |
| slash_left_inner | active | (-86.0, 0.0) | r=67.0, 중심 Δy=0.0 | body=true / area=false | 5→3 | 기대대로 |
| slash_outside_circle | active | (220.0, 0.0) | r=67.0, 중심 Δy=0.0 | body=false / area=false | 5→5 | 기대대로 |
| slash_overlap_beyond_66_depth | active | (86.0, 67.0) | r=67.0, 중심 Δy=67.0 | body=false / area=true | 5→5 | 기대대로 |
| slam_inner | active | (0.0, 0.0) | r=125.0, 중심 Δy=0.0 (제한 105) | body=true / area=false | 5→3 | 기대대로 |
| slam_overlap_beyond_105_depth | active | (0.0, 106.0) | r=125.0, 중심 Δy=106.0 (제한 105) | body=true / area=false | 5→5 | 기대대로 |
| duplicate_body_and_area_overlap | active | (86.0, 0.0) | r=67.0, 중심 Δy=0.0 | body=true / area=true | 5→3 | 기대대로 |
| boss_KO_by_Player_J | 피격 경로 | Player J | production Hitbox1 Area2D | Boss HP 1→0, boss_ko=1 | 직접 피격 호출 없음 | 실제 Player 공격 |
- Boss 런타임 코드는 수정하지 않았다. F10 윤곽과 실제 overlap/HP 사이에서 재현된 불일치가 없다.

## 상태 및 판정

- `windup`: AttackArea monitoring OFF 확인. `active`: 실제 overlap과 HP 판정. `recovery`: monitoring OFF 확인.
- 중복 검증은 동일 Player CharacterBody와 child Area2D가 Boss Area2D에 동시에 겹치도록 구성했으며, production attack_damage 한 번만 HP에서 차감되는지 검사했다.
- slash F10 outline은 AttackArea의 실제 CircleShape2D를 그린다. slam도 실제 CircleShape2D(반지름 125)를 그린다. 측정 결과 위반 시에만 런타임 코드 변경이 필요하다.
- 자동 검증 결과는 사람의 Window 육안 승인이 아니다. **사람 Window 승인: PENDING** (`human_window_approval=PENDING`).

## 결과

- PASS
