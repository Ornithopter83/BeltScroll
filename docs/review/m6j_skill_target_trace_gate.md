# M6J Skill Target Trace Gate

실제 `scenes/game/main.tscn`의 Player와 ForestRaider 씬 인스턴스에 keypad 입력 이벤트를 보냈습니다. 물리 프레임마다 체력 변화와 `skill_hit` 신호를 관찰했습니다. 적은 전투 준비를 위해 판정 위치에 배치하고 AI 물리 처리만 멈췄으며, 체력·피해·명중 함수는 직접 설정하거나 호출하지 않았습니다.

## 이전 Num4 중복 신호 원인

이전 M6I 캡처에는 Num4 `skill_hit` 두 건이 모두 physics frame 113에 기록됐고 추적하던 Raider HP는 3→0이었습니다. 그 도구는 신호에 연결된 타깃 ID/HP를 기록하지 않았으므로 저장된 과거 로그만으로 당시 두 번째 타깃의 정체는 복원할 수 없습니다. 이번 재현에서는 원래 씬의 TrainingDummy와 Raider가 각각 피해를 받았고, 같은 판정 영역에 배치한 두 Raider도 Num4에서 같은 물리 프레임에 각각 피해를 받았습니다.

원인은 중복 피해가 아니라 대상별 정상 다중 타격입니다. 생산 코드 `scripts/player/player_controller.gd`의 `_check_skill_hitbox()`는 `get_instance_id()`를 키로 `_skill_hit_targets`를 확인하고 각 고유 대상의 `receive_hit()` 뒤에 `skill_hit.emit(skill_id)`를 한 번 호출합니다. 두 대상이 한 active 물리 프레임에 겹치면 신호는 2회 발생하지만 각 인스턴스는 한 번만 피해를 받습니다. 아래 ID·HP·frame 기록과 생산 신호 수가 일치하는지 확인합니다.

## 관찰 결과

| 상태 | 물리 프레임 | 상세 |
|---|---:|---|
| INPUT | 8 | Input.parse_input_event physical_keycode=4194442 physics_frame=8 |
| OBSERVED | 11 | M6I_legacy_Num4_layout 원래 Num4 입력 startup=true |
| SIGNAL | 20 | M6I_legacy_Num4_layout skill_hit skill_id=1 physics_frame=20 frame_signal_count=1 |
| HIT | 21 | M6I_legacy_Num4_layout instance_id=42849011477 name=LegacyNum4_Raider hp=3→0 physics_frame=20 skill_id=1 same_frame_signal_count=1 |
| SIGNAL | 27 | M6I_legacy_Num4_layout skill_hit skill_id=1 physics_frame=27 frame_signal_count=1 |
| HIT | 28 | M6I_legacy_Num4_layout instance_id=35299264085 name=TrainingDummy hp=1000→997 physics_frame=27 skill_id=1 same_frame_signal_count=1 |
| OBSERVED | 58 | M6I_legacy_Num4_layout target instance_id=42849011477 name=LegacyNum4_Raider hp=3→0 hits=1 |
| OBSERVED | 58 | M6I_legacy_Num4_layout target instance_id=35299264085 name=TrainingDummy hp=1000→997 hits=1 |
| OBSERVED | 58 | M6I_legacy_Num4_layout 실행 전체 production skill_hit 신호=2 실제 피해 대상=2 |
| OBSERVED | 58 | 원래 배치 재현: Raider와 TrainingDummy 두 개별 hit_receiver가 각 1회 맞아 Num4 신호 합계 2회 발생 |
| INPUT | 102 | Input.parse_input_event physical_keycode=4194442 physics_frame=102 |
| OBSERVED | 103 | Num4/single 실제 keypad 입력으로 startup=true frame=103 |
| SIGNAL | 111 | Num4/single skill_hit skill_id=1 physics_frame=111 frame_signal_count=1 |
| HIT | 112 | Num4/single instance_id=45365594042 name=Num4_single_Target1 hp=3→0 physics_frame=111 skill_id=1 same_frame_signal_count=1 |
| OBSERVED | 146 | Num4/single target instance_id=45365594042 name=Num4_single_Target1 hp=0→0 attributed_hits=1 |
| OBSERVED | 146 | Num4/single production skill_hit signals=1 distinct damaged targets=1 |
| TRACE | 146 | Num4/single frame_summary={ "111": { "count": 1, "skill_id": 1 } } |
| INPUT | 190 | Input.parse_input_event physical_keycode=4194442 physics_frame=190 |
| OBSERVED | 191 | Num4/same_area_pair 실제 keypad 입력으로 startup=true frame=191 |
| SIGNAL | 199 | Num4/same_area_pair skill_hit skill_id=1 physics_frame=199 frame_signal_count=1 |
| SIGNAL | 199 | Num4/same_area_pair skill_hit skill_id=1 physics_frame=199 frame_signal_count=2 |
| HIT | 200 | Num4/same_area_pair instance_id=47747958556 name=Num4_same_area_pair_Target1 hp=3→0 physics_frame=199 skill_id=1 same_frame_signal_count=2 |
| HIT | 200 | Num4/same_area_pair instance_id=48033171383 name=Num4_same_area_pair_Target2 hp=3→0 physics_frame=199 skill_id=1 same_frame_signal_count=2 |
| OBSERVED | 234 | Num4/same_area_pair target instance_id=47747958556 name=Num4_same_area_pair_Target1 hp=0→0 attributed_hits=1 |
| OBSERVED | 234 | Num4/same_area_pair target instance_id=48033171383 name=Num4_same_area_pair_Target2 hp=0→0 attributed_hits=1 |
| OBSERVED | 234 | Num4/same_area_pair production skill_hit signals=2 distinct damaged targets=2 |
| OBSERVED | 234 | Num4/same_area_pair 같은 영역의 두 인스턴스 각각 1회 피해: 2 대상, 2 신호 |
| TRACE | 234 | Num4/same_area_pair frame_summary={ "199": { "count": 2, "skill_id": 1 } } |
| INPUT | 278 | Input.parse_input_event physical_keycode=4194442 physics_frame=278 |
| OBSERVED | 279 | Num4/out_of_range 실제 keypad 입력으로 startup=true frame=279 |
| OBSERVED | 319 | Num4/out_of_range target instance_id=50700748735 name=Num4_out_of_range_Target1 hp=3→3 attributed_hits=0 |
| OBSERVED | 319 | Num4/out_of_range production skill_hit signals=0 distinct damaged targets=0 |
| OBSERVED | 319 | Num4/out_of_range 범위 밖 대상 무피해·무신호 확인 |
| TRACE | 319 | Num4/out_of_range frame_summary={  } |
| INPUT | 363 | Input.parse_input_event physical_keycode=4194442 physics_frame=363 |
| OBSERVED | 364 | Num4/persistent_overlap 실제 keypad 입력으로 startup=true frame=364 |
| SIGNAL | 372 | Num4/persistent_overlap skill_hit skill_id=1 physics_frame=372 frame_signal_count=1 |
| HIT | 373 | Num4/persistent_overlap instance_id=52965672901 name=Num4_persistent_overlap_Target1 hp=1000→997 physics_frame=372 skill_id=1 same_frame_signal_count=1 |
| OBSERVED | 407 | Num4/persistent_overlap target instance_id=52965672901 name=Num4_persistent_overlap_Target1 hp=997→997 attributed_hits=1 |
| OBSERVED | 407 | Num4/persistent_overlap production skill_hit signals=1 distinct damaged targets=1 |
| OBSERVED | 407 | Num4/persistent_overlap active 지속 겹침 frames=8, 대상당 피해 1회, 신호=1 |
| TRACE | 407 | Num4/persistent_overlap frame_summary={ "372": { "count": 1, "skill_id": 1 } } |
| INPUT | 413 | Input.parse_input_event physical_keycode=4194443 physics_frame=413 |
| OBSERVED | 414 | Num5/single 실제 keypad 입력으로 startup=true frame=414 |
| SIGNAL | 426 | Num5/single skill_hit skill_id=2 physics_frame=426 frame_signal_count=1 |
| HIT | 427 | Num5/single instance_id=54223964102 name=Num5_single_Target1 hp=3→1 physics_frame=426 skill_id=2 same_frame_signal_count=1 |
| OBSERVED | 471 | Num5/single target instance_id=54223964102 name=Num5_single_Target1 hp=1→1 attributed_hits=1 |
| OBSERVED | 471 | Num5/single production skill_hit signals=1 distinct damaged targets=1 |
| TRACE | 471 | Num5/single frame_summary={ "426": { "count": 1, "skill_id": 2 } } |
| INPUT | 527 | Input.parse_input_event physical_keycode=4194443 physics_frame=527 |
| OBSERVED | 528 | Num5/same_area_pair 실제 keypad 입력으로 startup=true frame=528 |
| SIGNAL | 540 | Num5/same_area_pair skill_hit skill_id=2 physics_frame=540 frame_signal_count=1 |
| SIGNAL | 540 | Num5/same_area_pair skill_hit skill_id=2 physics_frame=540 frame_signal_count=2 |
| HIT | 541 | Num5/same_area_pair instance_id=56992204731 name=Num5_same_area_pair_Target1 hp=3→1 physics_frame=540 skill_id=2 same_frame_signal_count=2 |
| HIT | 541 | Num5/same_area_pair instance_id=57277417400 name=Num5_same_area_pair_Target2 hp=3→1 physics_frame=540 skill_id=2 same_frame_signal_count=2 |
| OBSERVED | 585 | Num5/same_area_pair target instance_id=56992204731 name=Num5_same_area_pair_Target1 hp=1→1 attributed_hits=1 |
| OBSERVED | 585 | Num5/same_area_pair target instance_id=57277417400 name=Num5_same_area_pair_Target2 hp=1→1 attributed_hits=1 |
| OBSERVED | 585 | Num5/same_area_pair production skill_hit signals=2 distinct damaged targets=2 |
| OBSERVED | 585 | Num5/same_area_pair 같은 영역의 두 인스턴스 각각 1회 피해: 2 대상, 2 신호 |
| TRACE | 585 | Num5/same_area_pair frame_summary={ "540": { "count": 2, "skill_id": 2 } } |
| INPUT | 641 | Input.parse_input_event physical_keycode=4194443 physics_frame=641 |
| OBSERVED | 642 | Num5/out_of_range 실제 keypad 입력으로 startup=true frame=642 |
| OBSERVED | 697 | Num5/out_of_range target instance_id=60314093504 name=Num5_out_of_range_Target1 hp=3→3 attributed_hits=0 |
| OBSERVED | 697 | Num5/out_of_range production skill_hit signals=0 distinct damaged targets=0 |
| OBSERVED | 697 | Num5/out_of_range 범위 밖 대상 무피해·무신호 확인 |
| TRACE | 697 | Num5/out_of_range frame_summary={  } |
| INPUT | 754 | Input.parse_input_event physical_keycode=4194443 physics_frame=754 |
| OBSERVED | 755 | Num5/persistent_overlap 실제 keypad 입력으로 startup=true frame=755 |
| SIGNAL | 767 | Num5/persistent_overlap skill_hit skill_id=2 physics_frame=767 frame_signal_count=1 |
| HIT | 768 | Num5/persistent_overlap instance_id=62981670691 name=Num5_persistent_overlap_Target1 hp=1000→998 physics_frame=767 skill_id=2 same_frame_signal_count=1 |
| OBSERVED | 812 | Num5/persistent_overlap target instance_id=62981670691 name=Num5_persistent_overlap_Target1 hp=998→998 attributed_hits=1 |
| OBSERVED | 812 | Num5/persistent_overlap production skill_hit signals=1 distinct damaged targets=1 |
| OBSERVED | 812 | Num5/persistent_overlap active 지속 겹침 frames=12, 대상당 피해 1회, 신호=1 |
| TRACE | 812 | Num5/persistent_overlap frame_summary={ "767": { "count": 1, "skill_id": 2 } } |
| OBSERVED | 814 | 생산 코드 대조: _check_skill_hitbox는 대상 instance_id를 _skill_hit_targets에 1회 기록하고, 각 receive_hit 직후 skill_hit를 1회 emit |

## 대상별 실제 HP 변화

| 시나리오 | 인스턴스 ID | 이름 | HP 전→후 | 물리 프레임 | skill_id | 같은 프레임 신호 수 |
|---|---:|---|---:|---:|---:|---:|
| M6I_legacy_Num4_layout | 42849011477 | LegacyNum4_Raider | 3→0 | 20 | 1 | 1 |
| M6I_legacy_Num4_layout | 35299264085 | TrainingDummy | 1000→997 | 27 | 1 | 1 |
| Num4/single | 45365594042 | Num4_single_Target1 | 3→0 | 111 | 1 | 1 |
| Num4/same_area_pair | 47747958556 | Num4_same_area_pair_Target1 | 3→0 | 199 | 1 | 2 |
| Num4/same_area_pair | 48033171383 | Num4_same_area_pair_Target2 | 3→0 | 199 | 1 | 2 |
| Num4/persistent_overlap | 52965672901 | Num4_persistent_overlap_Target1 | 1000→997 | 372 | 1 | 1 |
| Num5/single | 54223964102 | Num5_single_Target1 | 3→1 | 426 | 2 | 1 |
| Num5/same_area_pair | 56992204731 | Num5_same_area_pair_Target1 | 3→1 | 540 | 2 | 2 |
| Num5/same_area_pair | 57277417400 | Num5_same_area_pair_Target2 | 3→1 | 540 | 2 | 2 |
| Num5/persistent_overlap | 62981670691 | Num5_persistent_overlap_Target1 | 1000→998 | 767 | 2 | 1 |

## 판정

시나리오별 PASS/FAIL은 실제 keypad 이벤트, production 신호, 물리 프레임 관찰, 타깃별 실제 HP 변화로 판정합니다. `same_area_pair`의 두 명중은 서로 다른 인스턴스에 각 1회 피해가 확인될 때 정상 다중 타격입니다. 한 대상의 변화 행이 1개이고 HP가 감소했으면 중복 피해가 아닙니다.

스모크 종료 요약: fail=0, unverified=0, target HP-change rows=10.
