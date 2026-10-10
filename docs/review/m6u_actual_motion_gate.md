# M6U 실제 이동 표시 검증 게이트

> 아래의 기존 WORK 실행 수치(14.00/110.93, 150개)는 역사 기록이다. QA는 38.00/111.89를 재현했다. 최신 HIGH 측정 방식과 결과는 `m6u_high_followup_review.md`를 기준으로 읽는다. 기존 `fail=0`을 전체 콤보/스킬 프레임의 연속성 판정으로 사용하지 않는다.

## 실행 대상과 입력

`tests/m6u_actual_motion_window_smoke.gd`는 격리된 보행 미리보기 대신 `scenes/game/main.tscn`의 실제 Player를 띄운다. Player physics를 끄거나 위치·공격 상태를 직접 대입하지 않는다. `move_right`를 눌러 본편 이동을 만들고, 이동 중 J를 입력한 뒤 콤보 연결 구간에 J를 다시 입력해 1·2·3타를 진행한다. 이어 Num4/Num5에 연결된 `skill_1`/`skill_2` 입력을 각각 보내고, 걷기와 기술 전환의 연속 Window 프레임을 검사한다.

검증은 Window 렌더러에서 실행한다.

```powershell
& 'C:\Project\Godot\godot.exe' --path . --script res://tests/m6u_actual_motion_window_smoke.gd
```

## 측정 기준

- 실제 이동 중 보행 stride의 네 사분면(왼발 접지·passing, 오른발 접지·passing), 좌우 지지발 교대, 변형 메시가 그리는 지지발과 고정된 지지점의 잔차, 골반 상승을 연속 프레임에서 측정한다.
- 걷기와 공격/기술 handoff 때 Player, `PlayerArt`, 공격 pose 및 DEBUG 후보의 전신 표시 소스가 한 개만 보이는지 검사한다. 미승인 PNG는 게임 표시·manifest·allowlist에 넣지 않는다.
- 실제 이동 위치의 프레임 간 차이와 변형 격자 이웃 정점 간 길이로 순간 점프와 메시 찢김의 대리 지표를 기록한다. 이것은 픽셀 단위 사람이 보는 실루엣 심사를 대체하지 않는다.
- 입력 구간의 animator 상태와 visible source를 연속 추적해 이동 중 IDLE 끼어듦을 찾는다. 공격의 contact point 인터페이스와 controller phase duration은 변경하지 않는다.

## 판정 메모

검증 체크아웃의 `HEAD`와 로컬 `origin/main` ref는 모두 `37659af51dff2fee85b7d1e01625b6acf89638be`였다. 저장소 지침상 fetch는 실행하지 않았으므로 원격 최신 상태 갱신 여부는 확인하지 않았다.

2026-10-10 Window 실행 결과:

```text
M6U_ACTUAL_MOTION_SUMMARY|fail=0|phases=4|support_samples=150|support_residual=0.000|pelvis_lift=18.00|frame_jump=14.00|mesh_edge=110.93
```

실제 `move_right` 입력으로 네 위상과 좌우 지지 교대가 모두 발생했고, 렌더 완료 프레임 150개에서 지지점을 측정했다. 접지 잔차 최대 0.000, 골반 상승 최대 18.00 source px, 인접 메시 정점 최대 길이 110.93 source px, 프레임 간 Player 이동 최대 14.00 world px였다. J 입력으로 콤보 1·2·3타와 combo_hold를 진행했고, Num4/Num5 입력은 각각 본편 skill 상태를 활성화했다. 입력 구간마다 전신 표시 소스 하나만 렌더되었고, 이동 중 IDLE 침범은 없었다.

격자 해상도를 32에서 64로 높여 보행·공격 변형 표면의 큰 인접 정점 간격을 낮췄다. 실제 접지 잔차는 렌더 완료 프레임 기준으로 1.5 px 이하였다. 공격 contact-point 인터페이스와 공격/기술 phase duration은 변경하지 않았다. 후보 PNG, manifest, allowlist는 수정하지 않았다. 이 체크아웃에서 QA의 원 M6S 4건과 HIGH 판정 기록은 찾지 못했으므로 각각의 원본 캡처 주장을 대조하지는 못했으며, 위 본편 입력 시퀀스로 독립 표시 경로를 재검증했다. Window smoke는 exit code 0으로 끝났다. Godot는 user 로그 경로 쓰기와 시스템 CA store 관련 환경 오류를 출력했으나 렌더 검증 결과에는 영향을 주지 않았다.

## HIGH 사후 측정 보완

이전 `_capture_frame`은 일부 입력/대기 구간에서 호출되지 않았다. 그동안의 누적 이동을 단일 프레임 이동으로 합산했고, 걷기 구간 검사 뒤 최대값이 커져도 최종 검사하지 않았다. 최신 검증은 `RenderingServer.frame_post_draw`의 모든 연속 프레임을 한 번씩 기록하고, 걷기→J1/2/3→combo_hold→걷기→Num4/5 전 구간의 최대 이동·메시 길이·접지 잔차를 끝에서 검사한다. 이동 입력을 공격/스킬 완료까지 유지해 실제 걷기 복귀를 검증한다. 각 J 및 스킬의 startup/active/recovery와 J1/2 combo_hold가 실제 Window에 나타났는지도 확인한다. 물리 틱 수와 렌더 프레임 수를 따로 기록하므로 여러 물리 틱이 한 렌더 프레임 사이에 진행한 경우를 숨기지 않는다.

골반 상승은 `abs(sin(stride))*18` 목표값 대신 실제 메시 삼각형의 `(660,600)` 보간점을 읽는다. 접지 잔차는 렌더 메시 지지점과 저장된 월드 앵커 사이 world px, 골반 상승은 1254px 원화의 source px다. 최대 메시 간격은 UV 선분과 1 texel 필터 여유에 실제 alpha가 있는 이웃 정점에서 측정한다. 투명 영역의 최대 간격도 `transparent_edge`로 별도 출력한다. 기본 간격 제한 150px와 실제 연속 프레임 위치 제한 30px를 유지했다. 이 두 대리 지표만으로 모든 픽셀 실루엣·발 미끄러짐·메시 접힘을 사람 육안 승인한 것으로 간주하지 않는다.

연속 수치 CSV 및 네 보행 위상·콤보·스킬 상태의 실제 Window PNG는 `temp/m6u_high_motion/`에 보관한다. 검증 전용 출력이며 일반 게임 표시, manifest, allowlist에 등록하지 않는다. GRID 32→64와 animator/pose telemetry는 이번 HIGH 시작 전에 있던 dirty 변경이고, 이번 추가 production 변경은 골반 계측 getter뿐이다. `player_walk_motion.gd`와 공격 접촉점 getter·타이밍은 수정하지 않았다.
