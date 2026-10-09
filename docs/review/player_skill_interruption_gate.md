# Player 스킬 피격 중단 검수

- 실행 방식: 본편 `scenes/game/main.tscn`의 Player와 ForestRaider를 사용한 실제 Window 통합 검수
- 상대 타격: ForestRaider AI의 windup → AttackArea monitoring → Player.receive_hit 경로. `_cancel_skill` 직접 호출 없음. 검수 중 스킬의 공격 대상 등록만 끄기 위해 Raider collision_layer를 0으로 두고 Raider의 공격 Area는 정상 실행했습니다.
- 동기화 설정: 실제 입력으로 목표 스킬 단계에 진입한 뒤 frame sync 동안 해당 단계가 유지되도록 남은 phase timer를 최소 0.30초로 맞췄습니다. ForestRaider의 windup_duration은 0초로 설정해 본편 AI의 windup → active 전환을 다음 physics tick에 실행했습니다.
- 공간 설정: 다른 Raider는 physics 처리에서 제외하고 arena 가장자리로 옮겨 separation이 피격을 막지 않게 했습니다. 공격하는 ForestRaider는 계속 hit_receivers 그룹과 본편 AttackArea/receive_hit 경로를 사용했습니다.
- 방향 캡처: 두 우향/좌향 이미지 모두 실제 `RenderingServer.frame_post_draw` 이후 Window Viewport에서 획득. 원본 프레임을 좌우로 배치했습니다.

- 적 공격 시작: skill=1 phase=startup dir=우향 physics_frame=5 ticks_msec=956
- 피격 확인: skill=1 wanted_phase=startup observed_phase=startup dir=우향 event={player_hit: phase=startup physics_frame=7 ticks_msec=958} render_frame=4 render_ticks_msec=1308 cooldown=0.983
- 적 공격 시작: skill=1 phase=startup dir=좌향 physics_frame=42 ticks_msec=1818
- 피격 확인: skill=1 wanted_phase=startup observed_phase=startup dir=좌향 event={player_hit: phase=startup physics_frame=44 ticks_msec=1819} render_frame=9 render_ticks_msec=2161 cooldown=0.983
- 적 공격 시작: skill=1 phase=active dir=우향 physics_frame=88 ticks_msec=2778
- 피격 확인: skill=1 wanted_phase=active observed_phase=active dir=우향 event={player_hit: phase=active physics_frame=90 ticks_msec=2780} render_frame=15 render_ticks_msec=3124 cooldown=0.833
- 적 공격 시작: skill=1 phase=active dir=좌향 physics_frame=131 ticks_msec=3745
- 피격 확인: skill=1 wanted_phase=active observed_phase=active dir=좌향 event={player_hit: phase=active physics_frame=133 ticks_msec=3747} render_frame=21 render_ticks_msec=4088 cooldown=0.833
- 적 공격 시작: skill=1 phase=recovery dir=우향 physics_frame=181 ticks_msec=4819
- 피격 확인: skill=1 wanted_phase=recovery observed_phase=recovery dir=우향 event={player_hit: phase=recovery physics_frame=183 ticks_msec=4934} render_frame=29 render_ticks_msec=5277 cooldown=0.717
- 적 공격 시작: skill=1 phase=recovery dir=좌향 physics_frame=237 ticks_msec=6013
- 피격 확인: skill=1 wanted_phase=recovery observed_phase=recovery dir=좌향 event={player_hit: phase=recovery physics_frame=239 ticks_msec=6015} render_frame=36 render_ticks_msec=6360 cooldown=0.717
- 적 공격 시작: skill=2 phase=startup dir=우향 physics_frame=271 ticks_msec=6870
- 피격 확인: skill=2 wanted_phase=startup observed_phase=startup dir=우향 event={player_hit: phase=startup physics_frame=273 ticks_msec=6872} render_frame=41 render_ticks_msec=7213 cooldown=1.433
- 적 공격 시작: skill=2 phase=startup dir=좌향 physics_frame=308 ticks_msec=7722
- 피격 확인: skill=2 wanted_phase=startup observed_phase=startup dir=좌향 event={player_hit: phase=startup physics_frame=310 ticks_msec=7723} render_frame=46 render_ticks_msec=8066 cooldown=1.433
- 적 공격 시작: skill=2 phase=active dir=우향 physics_frame=358 ticks_msec=8796
- 피격 확인: skill=2 wanted_phase=active observed_phase=active dir=우향 event={player_hit: phase=active physics_frame=360 ticks_msec=8798} render_frame=53 render_ticks_msec=9141 cooldown=1.217
- 적 공격 시작: skill=2 phase=active dir=좌향 physics_frame=408 ticks_msec=9874
- 피격 확인: skill=2 wanted_phase=active observed_phase=active dir=좌향 event={player_hit: phase=active physics_frame=410 ticks_msec=9876} render_frame=60 render_ticks_msec=10218 cooldown=1.217
- 적 공격 시작: skill=2 phase=recovery dir=우향 physics_frame=468 ticks_msec=11062
- 피격 확인: skill=2 wanted_phase=recovery observed_phase=recovery dir=우향 event={player_hit: phase=recovery physics_frame=470 ticks_msec=11175} render_frame=69 render_ticks_msec=11518 cooldown=1.050
- 적 공격 시작: skill=2 phase=recovery dir=좌향 physics_frame=531 ticks_msec=12359
- 피격 확인: skill=2 wanted_phase=recovery observed_phase=recovery dir=좌향 event={player_hit: phase=recovery physics_frame=533 ticks_msec=12472} render_frame=78 render_ticks_msec=12814 cooldown=1.050
- evidence_png=C:/AI-AGENT/Worker/BeltScroll/assets/art/review/player_skill_interruption_window.png; left_source=(1920, 1080); right_source=(1920, 1080)

## 회귀 및 결과
- 검수 케이스 12개: Num4/Num5 × startup/active/recovery × 우향/좌향
- 피격 콜백은 `player_hit` signal에서 실제 피격 단계, physics frame, monotonic tick을 기록합니다.
- 추가 회귀: 가드 피해·경직 감소, 실제 공격 KO, Player 공격 hit-stop, 세션 재시작 time scale 복구
- 결과: PASS
