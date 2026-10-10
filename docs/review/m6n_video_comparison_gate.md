# M6N 콤보·판정 창 비교 게이트

## 판정

- 원본 영상 해시: `113A486A3D025A1166FA1143D8B1A7139412883B2A6751343947535530B03814` (요청 SHA256과 일치)
- 원본 영상 프레임 비교: **UNVERIFIED**. 현재 환경에 `ffmpeg`/`ffprobe` 실행 파일이 없고, 플레이어가 노출되지 않아 원본 프레임 추출을 수행하지 못함.
- 캡처 방식: Godot 4.7.2-stable (official)의 비-headless Window Viewport에서 실제 `scenes/game/main.tscn`과 production Player/Raider/Boss 노드를 구동해 PNG 연속 프레임 시트 생성. 입력 이벤트는 전부 자동 주입이다 (`source=auto_input_event`, device=16); 물리 키보드 입력 없음, `human_visual_approval=false`.
- 캡처 창: Windows, 1280x720, 프레임 수 51. PNG: `assets/art/review/m6n_combo_hitbox_contact_sheet.png`. 자동 키 이벤트 18개.

## 관측 결과

| 항목 | 관측 |
|---|---|
| 콤보 타임라인 | 1타 → combo_hold → 2타 → combo_hold → 3타 active 후 idle 복귀: true |
| 타격 사이 IDLE 프레임 | 0 (stage 1 진입부터 stage 3 active 전까지 계측; combo_hold는 IDLE로 세지 않음) |
| 활성 판정 샘플 수 | 1타 4, 2타 5, 3타 3 physics frames |
| 판정 중심 − 플레이어 중심 | 1타 x 39.9..39.9, y 0.0..0.0, 2타 x 52.2..52.2, y 0.0..0.0, 3타 x 66.7..66.7, y 0.0..0.0 world px; 실제 Area2D 변환을 매 physics frame 읽음 |
| 실제 Raider 적중 시 Raider 중심 − Player 판정 중심 | x -7.8, y 0.0 world px |
| Raider HP (Player J) | 3 → 2 |
| Player HP (Raider 공격) | 5 → 4 |
| Player HP (Boss 공격) | 4 → 2 |
| Boss HP (Player J) | 20 → 19 |
| F10 | OFF 상태 확인=true, ON 상태 확인=true (자동 F10 key event) |

## 재현·해석 제한

- 콤보 프레임 계측 중 적 AI를 정지하고 Raider를 화면 밖으로 옮겨 Player 상태 머신을 분리했다. Raider/Boss HP 구간에서는 production `receive_hit` 경로와 live 노드의 HP 값을 관측했으며, HP 직접 대입 또는 내부 피해 함수 호출은 하지 않았다. Boss는 게임 씬의 기본 진행 순서상 비활성이라 별도 구간에서 `set_combat_active(true)`로 켰다.
- 캐릭터와 박스 차이는 판정 Area2D 중심과 Player 월드 중심의 차이다. 캔버스/카메라 투영 후 보이는 스프라이트 외곽과의 픽셀 차이를 뜻하지 않는다.
- 이 자료는 자동 입력 및 자동 캡처 결과이며 수동 플레이·육안 승인 증거가 아니다. 원본 영상과의 시각 비교 gate는 UNVERIFIED 상태를 유지한다.

## 프레임 로그

| 시트 칸 | 구간 |
|---:|---|
| 1 | `01_walk_start` |
| 2 | `walk_00` |
| 3 | `walk_06` |
| 4 | `walk_12` |
| 5 | `walk_18` |
| 6 | `02_walk_stop` |
| 7 | `03_F10_OFF` |
| 8 | `04_F10_ON` |
| 9 | `combo_start_098` |
| 10 | `combo_stage1_hold_102` |
| 11 | `combo_stage1_hold_104` |
| 12 | `combo_stage1_hold_106` |
| 13 | `combo_stage1_hold_108` |
| 14 | `combo_stage1_hold_110` |
| 15 | `combo_stage1_hold_112` |
| 16 | `combo_stage1_hold_114` |
| 17 | `combo_stage1_hold_116` |
| 18 | `combo_stage1_hold_118` |
| 19 | `combo_stage1_hold_120` |
| 20 | `combo_stage1_hold` |
| 21 | `combo_stage2_hold_130` |
| 22 | `combo_stage2_hold_131` |
| 23 | `combo_stage2_hold_133` |
| 24 | `combo_stage2_hold_135` |
| 25 | `combo_stage2_hold_137` |
| 26 | `combo_stage2_hold_139` |
| 27 | `combo_stage2_hold_141` |
| 28 | `combo_stage2_hold_143` |
| 29 | `combo_stage2_hold_145` |
| 30 | `combo_stage2_hold_147` |
| 31 | `combo_stage2_hold_149` |
| 32 | `combo_stage2_hold_151` |
| 33 | `combo_stage2_hold` |
| 34 | `combo_stage3_active_160` |
| 35 | `combo_stage3_active` |
| 36 | `combo_finish_164` |
| 37 | `combo_finish_166` |
| 38 | `combo_finish_168` |
| 39 | `combo_finish_170` |
| 40 | `combo_finish_172` |
| 41 | `combo_finish_174` |
| 42 | `combo_finish_176` |
| 43 | `combo_finish_178` |
| 44 | `combo_finish_180` |
| 45 | `combo_finish_182` |
| 46 | `combo_finish_184` |
| 47 | `combo_finish_186` |
| 48 | `raider_player_hit` |
| 49 | `raider_hit_player` |
| 50 | `boss_hit_player` |
| 51 | `player_hit_boss` |

`M6N_FRAME` rows are printed to the Godot capture log; each row includes physics frame, phase, monitoring flag, world positions, and observed HP.
