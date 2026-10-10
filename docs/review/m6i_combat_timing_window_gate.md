# M6I Combat Timing Window Gate

Godot Window의 `scenes/game/main.tscn`에서 실제 플레이어·ForestRaider 노드를 실행해 기록했습니다. 측정시각은 `Time.get_ticks_usec()`와 물리 프레임 번호를 사용합니다.

## 입력 출처

이 자동 실행에서 `Input.parse_input_event(InputEventKey)`로 보낸 J, Num4, Num5는 자동 이벤트 표식과 device 16으로 `auto_input_event`에 분류합니다. 나머지 실제 Window 키 입력은 `physical_keyboard`로 별도 기록합니다. 이번 캡처 실행에서 물리 키 입력이 없으면 그 사실을 UNVERIFIED로 표시합니다.

## 판정

FAIL/UNVERIFIED는 관찰 실패를 성공으로 치환하지 않습니다. 배우 위치만 장면 준비를 위해 배치했으며 체력, 피해, 적의 공격 결과를 직접 수정하거나 전투 내부 시작/명중/승리 함수를 호출하지 않았습니다.

| 상태 | 시각(usec) | 관찰 |
|---|---:|---|
| CAPTURE | 831561 | 00 · 실제 전투 씬 · 입력 전 · 실제 Window · physics_frame=9 player_hp=5 attack=0/idle skill=0/idle hitstun=0.000 |
| TRACE | 860840 | synthetic InputEventKey keycode=74 action=attack |
| OBSERVED | 861649 | basic_1 startup frame=12 |
| CAPTURE | 912335 | 기본 1타 · 선딜 · hp=3 · physics_frame=14 player_hp=5 attack=1/startup skill=0/idle hitstun=0.000 |
| OBSERVED | 943152 | 기본 1타 active frame=17 hitbox.monitoring=true overlap=1 |
| OBSERVED | 946297 | basic_1 actual_attack_hit frame=17 |
| CAPTURE | 962516 | 기본 1타 · 명중 윈도우 · hitbox=true · physics_frame=17 player_hp=5 attack=1/active skill=0/idle hitstun=0.000 |
| TRACE | 962819 | synthetic InputEventKey keycode=74 action=attack |
| CAPTURE | 1095756 | 기본 1타 · 후딜 · hp=2 · physics_frame=25 player_hp=5 attack=1/recovery skill=0/idle hitstun=0.000 |
| OBSERVED | 1260717 | basic_2 startup frame=36 |
| CAPTURE | 1296011 | 기본 2타 · 선딜 · hp=2 · physics_frame=37 player_hp=5 attack=2/startup skill=0/idle hitstun=0.000 |
| OBSERVED | 1358839 | 기본 2타 active frame=42 hitbox.monitoring=true overlap=1 |
| OBSERVED | 1363496 | basic_2 actual_attack_hit frame=42 |
| CAPTURE | 1383126 | 기본 2타 · 명중 윈도우 · hitbox=true · physics_frame=42 player_hp=5 attack=2/active skill=0/idle hitstun=0.000 |
| TRACE | 1383370 | synthetic InputEventKey keycode=74 action=attack |
| CAPTURE | 1545307 | 기본 2타 · 후딜 · hp=0 · physics_frame=52 player_hp=5 attack=2/recovery skill=0/idle hitstun=0.000 |
| OBSERVED | 1727992 | basic_3 startup frame=64 |
| CAPTURE | 1763131 | 기본 3타 · 선딜 · hp=0 · physics_frame=65 player_hp=5 attack=3/startup skill=0/idle hitstun=0.000 |
| OBSERVED | 1843475 | 기본 3타 active frame=71 hitbox.monitoring=true overlap=1 |
| OBSERVED | 1845515 | basic_3 actual_attack_hit frame=71 |
| CAPTURE | 1861959 | 기본 3타 · 명중 윈도우 · hitbox=true · physics_frame=71 player_hp=5 attack=3/active skill=0/idle hitstun=0.000 |
| CAPTURE | 2062822 | 기본 3타 · 후딜 · hp=0 · physics_frame=83 player_hp=5 attack=3/recovery skill=0/idle hitstun=0.000 |
| OBSERVED | 2326903 | 기본 콤보 종료 및 이동 가능 시점 frame=100 phase=idle |
| OBSERVED | 2326975 | 기본 콤보 실피해 hp=3→0 |
| TRACE | 2376702 | synthetic InputEventKey keycode=4194442 action=skill_1 |
| OBSERVED | 2409808 | Num4 선딜 phase=startup cooldown=1.333 |
| CAPTURE | 2429049 | Num4 · 선딜 · cooldown=1.33 · physics_frame=105 player_hp=5 attack=0/idle skill=1/startup hitstun=0.000 |
| OBSERVED | 2544086 | Num4 명중 윈도우 phase=active hitbox=true |
| OBSERVED | 2544258 | skill_1 actual_skill_hit frame=113 |
| OBSERVED | 2544426 | skill_1 actual_skill_hit frame=113 |
| CAPTURE | 2563668 | Num4 · 명중 윈도우 · hitbox=true · physics_frame=113 player_hp=5 attack=0/idle skill=1/active hitstun=0.000 |
| OBSERVED | 2711115 | Num4 후딜 진입=true cooldown=1.079 |
| CAPTURE | 2730219 | Num4 · 후딜 · cooldown=1.08 · physics_frame=123 player_hp=5 attack=0/idle skill=1/recovery hitstun=0.000 |
| OBSERVED | 3126992 | Num4 종료/이동 가능 frame=148 |
| OBSERVED | 3127054 | Num4 production skill_hit signal count=2 |
| OBSERVED | 3127077 | Num4 실제 피해 hp=3→0 |
| TRACE | 3177286 | synthetic InputEventKey keycode=4194443 action=skill_2 |
| OBSERVED | 3210374 | Num5 선딜 phase=startup cooldown=1.783 |
| CAPTURE | 3229780 | Num5 · 선딜 · cooldown=1.78 · physics_frame=153 player_hp=5 attack=0/idle skill=2/startup hitstun=0.000 |
| OBSERVED | 3411480 | Num5 명중 윈도우 phase=active hitbox=true |
| OBSERVED | 3411675 | skill_2 actual_skill_hit frame=165 |
| CAPTURE | 3430981 | Num5 · 명중 윈도우 · hitbox=true · physics_frame=165 player_hp=5 attack=0/idle skill=2/active hitstun=0.000 |
| OBSERVED | 3610624 | Num5 후딜 진입=true cooldown=1.414 |
| CAPTURE | 3629933 | Num5 · 후딜 · cooldown=1.41 · physics_frame=177 player_hp=5 attack=0/idle skill=2/recovery hitstun=0.000 |
| OBSERVED | 4161214 | Num5 종료/이동 가능 frame=210 |
| OBSERVED | 4161274 | Num5 production skill_hit signal count=1 |
| OBSERVED | 4161294 | Num5 실제 피해 hp=3→1 |
| OBSERVED | 4278850 | 기본 콤보·Num4·Num5 이후 실제 이동 입력으로 조작 재개=true 이동량=28.0px |
| OBSERVED | 4329361 | 적 반격 선딜=true frame=220 |
| CAPTURE | 4348717 | 적 반격 · 선딜 · physics_frame=220 player_hp=5 attack=0/idle skill=0/idle hitstun=0.000 |
| OBSERVED | 4445766 | player_hit stage=1 frame=227 hitstun=0.000 |
| OBSERVED | 4445885 | 적 반격 active=true |
| CAPTURE | 4464956 | 적 반격 · 명중 윈도우 · physics_frame=227 player_hp=4 attack=0/idle skill=0/idle hitstun=0.203 |
| OBSERVED | 4465023 | 플레이어 피격/경직 frame=227 hitstun=0.203 hp=4 |
| CAPTURE | 4482204 | 플레이어 피격 · 경직 · hitstun=0.20 · physics_frame=228 player_hp=4 attack=0/idle skill=0/idle hitstun=0.187 |
| OBSERVED | 4679517 | 플레이어 경직 회복 frame=241 remaining=0.000 |
| OBSERVED | 4794634 | 플레이어 경직 회복 실제 이동 입력으로 조작 재개=true 이동량=28.0px |
| CAPTURE | 4813900 | 플레이어 피격 · 회복 완료 · physics_frame=248 player_hp=4 attack=0/idle skill=0/idle hitstun=0.000 |
| OBSERVED | 6939726 | Godot Window 캡처 매트릭스 저장=true frames=20 |
| INPUT:auto_input_event | 860742 | key=J physics_frame=11 |
| INPUT:auto_input_event | 962751 | key=J physics_frame=17 |
| INPUT:auto_input_event | 1383310 | key=J physics_frame=42 |
| INPUT:auto_input_event | 2376613 | key=Num4 physics_frame=102 |
| INPUT:auto_input_event | 3177154 | key=Num5 physics_frame=150 |
| INPUT:auto_input_event | 4178575 | key=A physics_frame=210 |
| INPUT:auto_input_event | 4694718 | key=A physics_frame=241 |
| UNVERIFIED | 6940415 | 실제 물리 키보드 이벤트는 이 자동 Window 실행에서 관찰되지 않음 |

## 캡처

실제 Window 프레임 매트릭스: `assets/art/review/m6i_combat_timing_matrix.png` (20 frame(s)).

