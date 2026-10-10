# M6U 실시간 본편 AI 교전 게이트

> 기존 여섯 표본과 caveat는 아래에 역사 기록으로 유지한다. HIGH는 관측 중 hitbox 재배치 호출을 제거하고 피해 신호 순간의 실제 Shape 겹침·HP 전이를 추가했다. 최신 독립 실행은 9개 표본 PASS이며 상세 근거는 `m6u_high_followup_review.md`와 `temp/m6u_high_live_extended3.log`에 있다.

## 목적과 실행 방식

M6S의 고정 120px 표적 PASS 이후, `tests/m6u_live_encounter_window_smoke.gd`를 추가해 `scenes/game/main.tscn`의 실제 플레이어, Raider, Boss로 입력을 흘렸다. 이 검증은 보이는 Godot Window에서 실행하며 60 및 15 물리 틱/초를 각각 설정한다. 입력은 `Input.action_press()`로 이동, 방어, J, Num4, Num5 순서로 전달한다.

Raider는 본편의 첫 웨이브 상태에서 AI를 계속 실행한다. Boss 표본은 본편 Boss 인스턴스에 게임과 동일한 `set_combat_active(true)` 진입점을 호출하고, 테스트 플레이어가 3구역을 이동할 수 있도록 런타임 구역 인덱스만 설정한다. Boss의 추적, windup, active, recovery, 피격 경직은 멈추지 않는다. 표적을 주먹 위치로 이동하거나 적 물리 처리를 끄지 않는다.

각 `M6U|SAMPLE|` JSON 행에는 입력 방향, 플레이어/적 시작·끝 좌표, 두 캐릭터의 이동 거리와 깊이 변화, 적 시작·끝 HP, 플레이어 HP, 피격 신호, 물리 접촉 쿼리 표본, 공격 단계·스킬 명중 ID, 적 AI 위상과 경직 관측을 기록한다.

## Window 실행 결과

| 물리 설정 | 교전 | 적 HP 변화 | 명중/AI 관측 | 플레이어 피해 |
|---|---|---:|---|---:|
| 60 FPS | Raider, 오른쪽 접근 및 아래 깊이 이동 | 3 → 0 | J1·J2, 적 경직, windup/active/recovery | 5 → 4 |
| 60 FPS | Raider, 왼쪽 접근 및 위 깊이 이동 | 3 → 0 | J1·J2, 적 경직, windup/active/recovery | 5 → 4 |
| 60 FPS | Boss, 본편 AI 활성 | 20 → 9 | J1·J2·J3, Num4·Num5, slash·slam 상태, 물리 접촉 쿼리 32회 표본 | 5 → 5 |
| 15 FPS | Raider, 오른쪽 접근 및 아래 깊이 이동 | 3 → 0 | J1·J2, 적 경직, windup/active/recovery | 5 → 4 |
| 15 FPS | Raider, 왼쪽 접근 및 위 깊이 이동 | 3 → 0 | Num4 명중 1회와 Raider windup/active/recovery 관측 | 5 → 3 |
| 15 FPS | Boss, 본편 AI 활성 | 20 → 9 | J1·J2·J3, Num4·Num5, slash·slam 상태, 물리 접촉 쿼리 6회 표본 | 5 → 4 |

전체 여섯 표본에서 PASS했다. Raider는 실제 3 HP 적이 J1/J2에 쓰러져, 그 뒤 입력한 J3 및 스킬이 추가 적 피해를 내지 않는 경우가 있다. 공격 시퀀스 전체의 단계별 명중은 20 HP Boss 표본에서 확인했다. Raider 왼쪽 15 FPS 행은 적의 `raider_hit` 신호와 HP 감소를 확인했지만 외부 프레임 표본 쿼리는 0회였다. 따라서 저 FPS 개별 쿼리 표본 수를 접촉 여부의 유일한 판정으로 쓰지 않고 실제 적 피격 신호와 HP 전이를 함께 기록한다.

Boss AI는 두 물리 설정 모두 slash와 slam 상태를 거쳤다. Boss의 공격이 플레이어를 맞힌 기록은 15 FPS에서 1 HP 감소, 60 FPS에서 0 HP 감소다. Raider AI는 두 FPS 설정 모두 플레이어에게 피해를 줬다. 60 FPS Boss 행에서 플레이어 피해를 확인하지 못했다는 사실도 PASS 로그와 별도로 남긴다.

## 판정 및 코드 변경

이번 본편 입력 표본에서 실제 물리 접촉은 대상 HP 감소와 적 피격 반응으로 확인됐다. 실패 표본은 공격 단계 중 적이 먼저 죽거나 입력 전에 AI에 맞아 공격이 중단된 경우로 재현됐으며, 거리만으로 피해를 적용하거나 hitbox 반경·쿨다운·피해량을 키우는 수정은 하지 않았다. 플레이어/적 전투 코드는 변경하지 않았다. 기존 M6S 피해, 깊이 제한, 중복 타격 방지 로직은 그대로 둔다.

Window 프로세스는 정상 종료하고 `M6U|SUMMARY|PASS|samples=6`을 출력했다. 실행 환경에서 `user://logs` 로그 파일 생성 실패와 Windows root certificate store 읽기 오류도 출력됐으나, 렌더 Window는 열렸고 검증 프로세스는 PASS 결과를 냈다.

## HIGH 사후 접촉 관측과 양방향 확장

`_probe_contact`는 이전에 `_update_fist_hitbox`를 호출해 관측 중 Shape를 재배치했다. 최신 관측은 기존 Shape를 읽는 쿼리만 수행한다. Raider/Boss receive 신호는 HP 감소·KO receiver 비활성화 전에 발생하므로, 이 시점에 이미 배치된 두 Shape의 `Shape2D.collide`와 production `intersect_shape`의 해당 대상 포함 여부를 동기 기록한다. 이후 Player 공격/스킬 신호에서 HP 감소, hitstun 또는 KO flash를 기록한다. 모든 피해 이벤트가 active phase의 실제 두 겹침과 HP 감소를 만족해야 PASS다. 추가 관측이 공격 phase·위치·damage 경로를 호출하거나 변경하지 않는다.

원래 15FPS 왼쪽 Raider 행의 외부 접촉 표본 0은 유지된다. 같은 Num4 피격 이벤트는 실제 Shape/쿼리 접촉 true, HP 3→0, KO flash 0.14초다. J1 시작 뒤 적 active 공격이 Player를 경직시켰고 후속 J 입력 시 경직 0.22/0.0867초가 기록됐다. 따라서 이 행을 J1~3 명중 PASS로 표기하지 않는다. AI recovery까지 실제 block 입력으로 기다린 별도 왼쪽 15FPS 표본은 J2와 Num5 접촉, HP 3→0을 확인했다. 3HP Raider는 조기 KO로 모든 공격의 추가 피해를 확인할 수 없다.

Boss의 왼쪽 명중 표본은 오른쪽 경기장 밖에서 시작하지 않는다. Player는 기존 오른쪽 접근과 같은 유효 시작점에서 왼쪽/깊이 이동으로 활성 Boss를 유인하고, 실제 오른쪽 이동으로 반대편을 돌아 깊이를 맞춘 다음 왼쪽 이동→J→Num4/5를 입력한다. 표적 위치·체력·AI를 매 타격마다 주입하지 않는다. 60/15FPS 양방향 네 Boss 행 모두 J1/2/3·Num4/5의 5개 동기 접촉 이벤트, HP 20→19→17→14→11→9, hitstun, slash/slam 상태를 기록했다. Boss Player 피해는 오른쪽 15FPS에서만 1HP, 나머지 세 Boss 행에서는 0이다.

초기 확장 실험에서 Boss.x+260의 경기장 밖 Player 초기화가 경계 보정과 0명중/Player KO를 유발했다. 그 FAIL 로그는 `temp/m6u_high_live_extended.log`와 `extended2.log`에 남겼다. 유효 경기장 시작점 및 실제 유인/회전 입력으로 수정한 최종 실행은 9개 표본 모두 명중을 기록했다. 이는 테스트 준비 결함 수정이며 전투 물리 수정으로 보고하지 않는다. 60/15는 `physics_ticks_per_second`와 `max_fps` 설정값이고, 실제 OS 키보드 및 사람이 플레이한 60FPS 성능 인증은 아니다.
