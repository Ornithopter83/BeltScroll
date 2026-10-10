# M6U HIGH 사후 독립 검토 — 2026-10-10

## 검토 범위와 체크아웃

HQ #676/#677/#678, WORK/BUILD 및 제공된 QA 원문을 기준으로 현재 소스와 실제 Windows OpenGL Window를 검토했다. HEAD와 로컬 origin/main은 모두 `37659af51dff2fee85b7d1e01625b6acf89638be`다. Git commit/push/reset/rebase/fetch 및 .git 변경은 하지 않았다. 따라서 원격 서버 최신 커밋 갱신 여부는 미확인이다.

시작부터 dirty 트리였다: player mesh GRID 64, pose/animator getter, overlay 주석, M6U 4종 테스트·게이트, M6Q 리뷰 PNG/문서 및 생성 sidecar 등이 이미 있었다. 아래 결과는 보완한 작업 트리의 독립 검증이며 pristine HEAD 결과가 아니다. 기존 QA의 원본 4건 FAIL 캡처와 이후 HIGH PASS를 소급 승인하지 않는다. BUILD는 manifest 부재로 skipped였고 이번에도 별도 export 빌드를 주장하지 않는다.

## 확인한 결함 및 실제 보완

1. 모션 검사의 일부 입력/대기 구간은 샘플이 없었다. 여러 프레임 이동을 한 프레임 점프로 합산했고 걷기 이후 갱신된 최대값을 끝에서 재검사하지 않아 `frame_jump=38`에도 `fail=0`이 가능했다. `frame_post_draw` 전 구간 수집, 최종 제한 검사, 렌더/물리 인덱스 CSV 및 각 phase Window PNG를 추가했다. 실제 이동을 공격/스킬 끝까지 유지하고 J1/2 combo_hold 및 모든 startup/active/recovery의 Window 출현을 검사한다. 위치 제한 30px는 유지했다.
2. 골반 getter는 렌더 위치 대신 목표 sine amplitude를 반환했다. 현재는 실제 메시 삼각형의 원화 좌표 `(660,600)` 보간점으로 source px 상승을 읽는다. 보행·접촉점 변형 함수, 공격 contact-point 인터페이스, 타이밍은 수정하지 않았다.
3. 새로 스킬까지 전 구간 검사하면서 raw mesh edge 약 400px가 검출됐다. UV alpha를 대조하면 큰 간격은 투명 원화 모서리였다. 실제 alpha가 있는 UV 선분(1 texel 필터 여유 포함)의 최대값과 투명 간격을 따로 기록했다. 가시 간격 제한 150px를 유지하며, 투명 간격도 출력해 감추지 않는다. 이는 표시 결함을 고친 결과가 아니라 대리 지표의 적용 영역을 구분한 것이다. 전체 픽셀 메시 접힘/찢김 심사를 완료했다는 뜻은 아니다.
4. AI 검사의 외부 contact probe가 `_update_fist_hitbox`를 호출해 관측 중 Shape를 재배치했다. 이를 제거했다. 현재는 receive 신호 직전 상태의 기존 Shape2D 두 도형 겹침 및 실제 production query의 대상 포함 여부를 읽고, Player hit 신호에서 HP 감소/경직/KO flash를 함께 기록한다. 모든 피해 신호에 active 접촉 근거가 있어야 통과한다. 입력 시점의 경직·phase·root gap 및 실제 attack_started/skill_started도 기록한다.
5. M6N 두 실패는 현 씬과 다른 Circle/좌표 fixture였다. Raider `(0,-326)`, circle r44 및 Boss `(0,-320)`, capsule r45/h160을 명시하고 기존 overlap·피해 콜백·범위 밖 거부·깊이 제한·KO assertions를 유지했다. 이 변경은 fixture migration이며 실제 피해를 증명하는 새 기대값으로 취급하지 않는다.
6. M6Q capture가 SHA 실패를 확인하기 전에 리뷰 PNG/문서를 생성했다. SHA256 검사를 scene 생성/출력 전에 수행하도록 보완했다. 원래 SHA와 입력 경로는 유지했다. 부재/불일치 입력을 정상 영상으로 대체하지 않는다.
7. overlay HEAD diff는 주석 2줄뿐이고 HEAD에도 하반원 `0..PI`가 이미 있다. WORK의 “하반원 렌더 오류를 수정했다”는 서술을 정정했다. 새 기하/충돌 물리 수정은 없다.

## 실제 Window 재검증

실행 엔진은 `Godot 4.7.2.stable.mono.official.ed1daf0bf`, AMD OpenGL Compatibility다. 공통 명령은 아래와 같고 각 로그 경로는 표에 기록했다.

```powershell
& 'C:\Project\Godot\Godot_v4.7.2-stable_mono_win64_console.exe' --path . --script res://tests/<script>.gd --log-file C:/AI-AGENT/Worker/BeltScroll/temp/<log>.log
```

| 검사 | 결과 | 증거 / 범위 |
|---|---|---|
| m6u_live_encounter_window_smoke | PASS, exit 0, samples=9 | `temp/m6u_high_live_extended3.log`; live main.tscn AI, 좌우 Raider와 Boss, 60/15 물리 틱·렌더 상한 설정, 추가 15FPS 왼쪽 recovery 표본 |
| m6u_actual_motion_window_smoke | PASS, exit 0 | `temp/m6u_high_motion_final.log`, `temp/m6u_high_motion/frames.csv` 및 phase PNG; Player 실제 입력, 적 AI만 표시 격리를 위해 중지 |
| m6n_enemy_collision_alignment_smoke | PASS, exit 0 | `temp/m6u_high_m6n.log`; 현 Receiver fixture와 기존 공격/깊이/KO 계약 |
| m6u_f10_boss_receive_independent_window_smoke | PASS, exit 0, 36 landmarks | `temp/m6u_high_capsule.log`; Boss slash/slam/zoom+scroll/KO 각각 6/6, Player J2 active/inactive 및 Raider Receive 각각 4/4 |
| m6u_legacy_combat_contract_smoke | PASS, exit 0 | `temp/m6u_high_legacy.log`; 별도 손/Shape 원점 정합 및 고정 120px production Receiver HP 피해 계약 |
| m6q_visual_collision_regression_smoke | 입력 부재로 FAIL, exit 1 | `temp/m6u_high_m6q.log`; observed SHA=MISSING. 리뷰 md 및 PNG 실행 전후 SHA 동일. 참조 영상 비교 미검증 |

모션 최종 출력:

```text
M6U_ACTUAL_MOTION_SUMMARY|fail=0|phases=4|support_samples=193|support_residual=0.000|pelvis_lift=18.00|frame_jump=18.67|mesh_edge=130.35|transparent_edge=393.05|render_frames=256|physics_gap=4
```

CSV의 실제 최대 접지 잔차는 0.000366 world px, 골반 상승은 17.998047 source px다. 보행 네 위상과 양발 교대, 모든 J/스킬 phase 및 J1/2 combo_hold가 렌더됐다. 256개 연속 Window 프레임에서 전신 소스 1개와 이동/공격 중 비관련 IDLE 부재를 검사했다. 렌더 프레임 사이 최대 4 물리 틱이 진행했으므로 “모든 물리 틱 캡처”나 실제 벽시계 60FPS 인증을 주장하지 않는다. 기존 WORK 14.00/110.93 및 QA 38.00/111.89와는 수집 범위가 달라 직접 동일 수치로 비교할 수 없다. 동일 보완 코드의 직전 실행 `m6u_high_motion_run3.log`도 같은 요약 수치를 냈다.

AI 교전 최종 HP/명중:

| 설정 | 표본 | 적 HP | 실제 명중 | Player HP |
|---|---|---:|---|---:|
| 60 | Raider 우/깊이 아래 | 3→0 | J1/J2 | 5→4 |
| 60 | Raider 좌/깊이 위 | 3→0 | J1/J2 | 5→4 |
| 60 | Boss 우 | 20→9 | J1/J2/J3, Num4/Num5 | 5→5 |
| 60 | Boss 좌/깊이 이동·회전 접근 | 20→9 | J1/J2/J3, Num4/Num5 | 5→5 |
| 15 | Raider 우/깊이 아래 | 3→0 | J1/J2 | 5→4 |
| 15 | Raider 좌/기존 입력 | 3→0 | Num4; J는 적 피격으로 중단 | 5→3 |
| 15 | Raider 좌/실제 guard recovery 후 입력 | 3→0 | J2, Num5 | 5→2 |
| 15 | Boss 우 | 20→9 | J1/J2/J3, Num4/Num5 | 5→4 |
| 15 | Boss 좌/깊이 이동·회전 접근 | 20→9 | J1/J2/J3, Num4/Num5 | 5→5 |

네 Boss 행은 각각 HP `20→19→17→14→11→9`와 active 단계 동기 접촉 5건, hitstun, slash/slam을 기록한다. 기존 15FPS 왼쪽 Raider 외부 표본 0은 여전히 0이다. 해당 Num4 receive 순간에는 Shape 겹침과 intersect_shape 대상 포함 모두 true, HP 3→0 및 KO flash 0.14초였다. 따라서 이 행의 표본 0을 가짜 접촉으로 대체하지 않았고 J1~3 명중 PASS로 표기하지 않는다. 다른 recovery 입력 표본에서 basic J2 피해를 독립 확인했다. Raider 3HP 조기 KO와 60FPS Boss Player 무피해 caveat를 유지한다.

초기 Boss 좌측 확장 실험은 Player를 Boss.x+260에 놓아 production 경기장 밖에서 시작했고, 경계 보정·Player KO·0명중이 발생했다. FAIL 로그 `m6u_high_live_extended.log`, `extended2.log`를 보존했다. 현재 좌측 표본은 유효 시작점에서 실제 이동으로 AI Boss를 왼쪽으로 유인하고 반대편을 돌아온다. Boss를 이동시키거나 AI/HP를 주입해 명중시킨 것이 아니다. 유효 준비를 고친 최종 9개 표본에는 전체 교전 0명중 행이 없다. 전투 코드는 변경하지 않았다.

캡슐 검사는 F10 OFF/ON의 HP, transform, layers/masks/monitoring/monitorable 불변을 확인했다. slash/slam receiver monitoring on, KO off/unmonitorable도 확인했다. 최신 KO 구간은 Boss physics를 끄지 않고 production 쓰러짐 회전·scale이 진행함을 확인하면서 root-owned Receiver가 그 변환을 상속하지 않는지 검사한다. slash/slam의 검사 fixture는 공격 상태를 만들어 픽셀 외곽을 조사하는 계약이며 live AI 피해의 증거로 혼용하지 않는다. 전체 M6P/J1~3/Num4/5/미러·HUD 및 M6R·M6Q 구 contact PASS는 QA의 동일 기하 독립 결과도 근거로 유지한다. 이번 별도 legacy 실행도 J1/2/3·왼쪽 J1·Num4/5 손/Shape origin 오차 <0.1 및 주먹 반경 J≤15/Num≤16을 확인하고, 정지 120px Raider/Boss 피해 각각 combo 6/Num4 3/Num5 2를 검사했다. 이 정지 표적 계약은 위 9개 live AI 표본과 구분한다.

## 잔여 위험과 미인수

- M6Q 참조 MP4가 없으므로 SHA가 일치하는 원본 영상 회귀는 미검증이다. 해당 FAIL을 PASS로 변경하지 않았다.
- 로컬 origin/main 최신성 및 pristine HEAD 검증을 주장하지 않는다. Worker의 원격 갱신 확인이 필요하다.
- 실제 OS 키보드 J/Num/F10과 사람 육안 승인은 미인수다. 입력은 Input.action_press, F10은 overlay callback이다. PNG/수치 검사는 사람 승인을 대체하지 않는다.
- QA의 원 M6S 네 실패 캡처별 before/after 대응은 확인하지 못했다. 현재 입력 경로의 독립 결과를 소급 해소 근거로 사용하지 않는다.
- 메시 edge는 가시 UV 선분의 대리 지표다. 투명 393.05px 변형을 기록했으며 전체 삼각형의 픽셀 접힘 여부까지 완전 증명하지 않는다.
- Godot의 root certificate store 경고는 계속 출력됐다. 이번 실행은 workspace 안 log-file로 기록했고 parsing/scene-load FAIL은 최종 통과 게이트에서 없었다.

미승인 PNG 일반 게임 표시·manifest·allowlist 승격, collision shape/layer/mask 변경, 피해량·쿨다운·깊이 제한·중복 타격·접촉점 시간 변경은 없다.
