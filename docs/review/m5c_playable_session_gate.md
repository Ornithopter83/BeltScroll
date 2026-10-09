# M5C 실제 플레이 세션 검수

- 실행: `C:/Project/Godot/godot.exe --path <project> --script res://tools/capture_m5c_playable_session.gd`
- 자식 프로세스 종료 코드: `0`
- 결과: **PASS**
- 입력 범위: 합성 InputMap/InputEvent이며 OS 물리 키보드·마우스 입력은 검증하지 않음.
- 캡처: `assets/art/review/m5c_playable_session_window.png` (스크립트가 생성; 실패 시 마지막 상태 프레임 포함)

## 확인 범위

| 경로 | 관측 |
|---|---|
| `move_right`, `move_left`, `jump`, `block` | 프레임 번호와 좌표·방향·상태 전이 기록 |
| `attack` 1~3단계 | 실물 hitbox, 신호, Raider HP/경직, hit-stop, 카메라 trauma |
| 합성 Num4/Num5 키 이벤트 | InputMap `skill_1`/`skill_2`, 실제 startup 및 쿨다운 HUD |
| 화면 | Player/Raider 체력바, 스킬 HUD, 쿨다운, 타이틀·조작 메뉴의 post-draw 프레임 |

Num4/Num5 입력 경로는 `InputEventKey`를 InputMap에 전달합니다. `DIRECT_STATE_PREVIEW` 캡처만 검수기에서 스킬 변수를 직접 설정하며 실제 입력 성공 증거로 계산하지 않습니다. 원본 검수 이미지 디렉터리의 텍스처가 main 장면 Sprite2D에 표시되지 않는 검사도 통과했습니다.

실행 중 Godot가 `user://logs` 쓰기 및 시스템 CA 읽기 오류를 출력했지만 캡처 프로세스는 종료 코드 0으로 완료했습니다.

## 실행 로그 (프레임·상태·입력 경로)

```text
ERROR: Failed to open 'user://logs/godot2026-10-09T21.15.00.log'.
   at: copy (core/io/dir_access.cpp:429)
ERROR: Failed to open log file for writing: user://logs/godot.log
   at: rotate_file (core/io/logger.cpp:169)
Godot Engine v4.7.2.stable.mono.official.ed1daf0bf - https://godotengine.org
OpenGL API 3.3.0 Core Profile Context 26.8.1.260806 - Compatibility - Using Device: ATI Technologies Inc. - AMD Radeon RX 6900 XT

ERROR: Failed to read the root certificate store.
   at: get_system_ca_certificates (platform/windows/os_windows.cpp:2582)
PASS: Window renderer available
PASS: existing main.tscn loads
PASS: live Player and ForestRaider instances
PASS: Player health HUD exists
PASS: skill HUD exists
PASS: Player Camera2D exists
PASS: no review-directory artwork is visible in main.tscn
PASS: ForestRaider health bar is visible in the live HUD
PASS: move_right
PASS: direction reversal
PASS: jump
PASS: block
PASS: basic attack stage 1
PASS: attack 1 recovery
PASS: combo buffer 1 to 2
PASS: basic attack stage 2
PASS: attack 2 recovery
PASS: combo buffer 2 to 3
PASS: basic attack stage 3
PASS: Num4 production skill input
PASS: Num5 production skill input
PASS: live input path reduced Raider health
PASS: production title menu scene instance
PASS: title and start button visible
PASS: controls menu opens from title scene
PASS: controls menu returns to title
PASS: post-draw Window capture board saved (16 frames, err=0)
CAPTURE_PNG: C:/AI-AGENT/Worker/BeltScroll/assets/art/review/m5c_playable_session_window.png
CAPTURE_COUNT: 16
TRACE: ART_TEXTURE node=/root/Main/StageBackground path=res://assets/art/stage/forest_ruins_v1_1920x1080.png visible=true
TRACE: ART_TEXTURE node=/root/Main/YSortActors/Player/VisualRoot/PlayerArt path=res://assets/art/player/elven_fighter_reference_v8_clean_candidate_1254x1254.png visible=true
TRACE: ART_TEXTURE node=/root/Main/YSortActors/ForestRaider1/VisualRoot/RaiderArt path=res://assets/art/enemies/forest_raider_reference_v1_final_candidate_1254x1254.png visible=true
TRACE: ART_TEXTURE node=/root/Main/YSortActors/ForestRaider2/VisualRoot/RaiderArt path=res://assets/art/enemies/forest_raider_reference_v1_final_candidate_1254x1254.png visible=true
TRACE: ART_TEXTURE node=/root/Main/YSortActors/ForestRaider3/VisualRoot/RaiderArt path=res://assets/art/enemies/forest_raider_reference_v1_final_candidate_1254x1254.png visible=true
TRACE: POST_DRAW frame=1 title=01 MAIN START physics=9 state=frame=9 pos=(960.0, 780.0) facing=(0.0, 1.0) jump=false block=false attack=0/idle skill=0/idle cooldowns=[0.0, 0.0] hp=5 raider_hp=8 camera_trauma=0.000 hitstop=1.000
TRACE: CHECK move_right=PASS | action=move_right x=960.0 to 1039.3 facing=(1.0, 0.0) physics=27
TRACE: POST_DRAW frame=2 title=02 MOVE RIGHT physics=31 state=frame=31 pos=(1062.667, 780.0) facing=(1.0, 0.0) jump=false block=false attack=0/idle skill=0/idle cooldowns=[0.0, 0.0] hp=5 raider_hp=8 camera_trauma=0.000 hitstop=1.000
TRACE: CHECK direction reversal=PASS | action=move_left x=1062.7 to 1002.0 facing=(-1.0, 0.0) physics=45
TRACE: POST_DRAW frame=3 title=03 TURN LEFT physics=47 state=frame=47 pos=(988.0001, 780.0) facing=(-1.0, 0.0) jump=false block=false attack=0/idle skill=0/idle cooldowns=[0.0, 0.0] hp=5 raider_hp=8 camera_trauma=0.000 hitstop=1.000
TRACE: CHECK jump=PASS | action=jump is_jumping=true jump_v=-348.7 height=59.1 physics=57
TRACE: POST_DRAW frame=4 title=04 JUMP physics=62 state=frame=62 pos=(988.0001, 780.0) facing=(-1.0, 0.0) jump=true block=false attack=0/idle skill=0/idle cooldowns=[0.0, 0.0] hp=5 raider_hp=8 camera_trauma=0.000 hitstop=1.000
TRACE: POST_DRAW frame=5 title=05 BLOCK physics=91 state=frame=91 pos=(988.0001, 780.0) facing=(-1.0, 0.0) jump=false block=true attack=0/idle skill=0/idle cooldowns=[0.0, 0.0] hp=5 raider_hp=8 camera_trauma=0.000 hitstop=1.000
TRACE: CHECK block=PASS | pressed is_blocking=true; released is_blocking=false physics=93
TRACE: signal raider_hit physics=105
TRACE: signal attack_hit stage=1 physics=105 hitstop=1.000
TRACE: hit-stop observed stage=1 physics=105 scale=0.080
TRACE: POST_DRAW frame=6 title=06 ATTACK 1 physics=107 state=frame=107 pos=(951.2303, 780.0) facing=(-1.0, 0.0) jump=false block=false attack=1/active skill=0/idle cooldowns=[0.0, 0.0] hp=5 raider_hp=7 camera_trauma=0.030 hitstop=1.000
TRACE: CHECK basic attack stage 1=PASS | action=attack stage=1 phase=active hitbox=true hit_signal=true target_hp=8 to 7 hitstun=0.145 hitstop_seen=true camera_trauma=0.030 physics=107
TRACE: CHECK attack 1 recovery=PASS | phase=recovery frame=111
TRACE: CHECK combo buffer 1 to 2=PASS | attack_stage=2 phase=startup physics=123
TRACE: signal raider_hit physics=128
TRACE: signal attack_hit stage=2 physics=128 hitstop=1.000
TRACE: hit-stop observed stage=2 physics=128 scale=0.080
TRACE: POST_DRAW frame=7 title=07 ATTACK 2 physics=130 state=frame=130 pos=(901.2021, 780.0) facing=(-1.0, 0.0) jump=false block=false attack=2/active skill=0/idle cooldowns=[0.0, 0.0] hp=5 raider_hp=7 camera_trauma=0.130 hitstop=1.000
TRACE: CHECK basic attack stage 2=PASS | action=attack stage=2 phase=active hitbox=true hit_signal=true target_hp=8 to 6 hitstun=0.200 hitstop_seen=true camera_trauma=0.130 physics=130
TRACE: CHECK attack 2 recovery=PASS | phase=recovery frame=136
TRACE: CHECK combo buffer 2 to 3=PASS | attack_stage=3 phase=startup physics=149
TRACE: signal raider_hit physics=156
TRACE: signal attack_hit stage=3 physics=156 hitstop=1.000
TRACE: hit-stop observed stage=3 physics=156 scale=0.080
TRACE: POST_DRAW frame=8 title=08 ATTACK 3 physics=160 state=frame=160 pos=(824.9362, 780.0) facing=(-1.0, 0.0) jump=false block=false attack=3/active skill=0/idle cooldowns=[0.0, 0.0] hp=5 raider_hp=7 camera_trauma=0.190 hitstop=1.000
TRACE: CHECK basic attack stage 3=PASS | action=attack stage=3 phase=active hitbox=true hit_signal=true target_hp=8 to 5 hitstun=0.222 hitstop_seen=true camera_trauma=0.190 physics=160
TRACE: POST_DRAW frame=9 title=09 HIT REACTION physics=168 state=frame=168 pos=(827.4362, 780.0) facing=(-1.0, 0.0) jump=false block=false attack=3/recovery skill=0/idle cooldowns=[0.0, 0.0] hp=5 raider_hp=7 camera_trauma=0.000 hitstop=1.000
TRACE: CHECK Num4 production skill input=PASS | synthetic InputEventKey mapped=true action=skill_1 skill_id=1 phase=startup cooldown=1.350 source=production_input
TRACE: POST_DRAW frame=10 title=NUM4 SKILL 1 physics=192 state=frame=192 pos=(727.4362, 780.0) facing=(-1.0, 0.0) jump=false block=false attack=0/idle skill=1/startup cooldowns=[1.23333333333333, 0.0] hp=5 raider_hp=7 camera_trauma=0.000 hitstop=1.000
TRACE: CHECK Num5 production skill input=PASS | synthetic InputEventKey mapped=true action=skill_2 skill_id=2 phase=startup cooldown=1.800 source=production_input
TRACE: POST_DRAW frame=11 title=NUM5 SKILL 2 physics=235 state=frame=235 pos=(673.2693, 780.0) facing=(-1.0, 0.0) jump=false block=false attack=0/idle skill=2/startup cooldowns=[0.51666666666667, 1.7] hp=5 raider_hp=7 camera_trauma=0.000 hitstop=1.000
TRACE: POST_DRAW frame=12 title=14 COOLDOWN HUD physics=292 state=frame=292 pos=(673.2693, 780.0) facing=(-1.0, 0.0) jump=false block=false attack=0/idle skill=0/idle cooldowns=[0.0, 0.75] hp=5 raider_hp=7 camera_trauma=0.000 hitstop=1.000
TRACE: POST_DRAW frame=13 title=13 DIRECT HUD PREVIEW physics=300 state=frame=300 pos=(673.2693, 780.0) facing=(-1.0, 0.0) jump=false block=false attack=0/idle skill=1/active cooldowns=[0.0, 0.75] hp=5 raider_hp=7 camera_trauma=0.000 hitstop=1.000
TRACE: DIRECT_STATE_PREVIEW: skill_id/phase/remaining assigned by capture harness for HUD rendering only; excluded from live input pass.
TRACE: POST_DRAW frame=14 title=14 TITLE MENU physics=314 state=player=unavailable
TRACE: POST_DRAW frame=15 title=15 MENU CONTROLS physics=321 state=player=unavailable
TRACE: POST_DRAW frame=16 title=16 MENU RETURN physics=327 state=player=unavailable
TRACE: ART_POLICY: main.tscn production textures are used; no assets/art/review texture is attached to gameplay actors.
TRACE: PHYSICAL_KEYBOARD_MOUSE: NOT_TESTED; synthetic InputEventKey resolved through InputMap only.
TRACE: cooldown_observation: cooldown values logged at Num4/Num5 production startup and in post-phase HUD capture.
m5c_playable_session: all checks passed

```
