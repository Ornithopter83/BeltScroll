# M6S 실제 전투 피해 게이트

## 조사 결과

- 플레이어의 기본 공격 Shape는 반경 13, 14, 15px이고 스킬 Shape는 16, 15px다. `_update_fist_hitbox()`가 화면에 표시 중인 스프라이트의 주먹 좌표를 받아 `Area2D.global_position`에 넣고, `_query_fist_targets()`는 그 Shape의 `global_transform`으로 `direct_space_state.intersect_shape()`를 호출한다. 쿼리는 물리 프레임에서 `move_and_slide()` 뒤 실행되므로 플레이어 이동은 반영된다. 수동 쿼리의 좌표는 PhysicsServer의 Area 중첩 캐시가 아닌 전달된 Transform을 사용한다.
- 공격 핀은 pose sprite가 바뀌는 프레임에 플레이어 뒤쪽으로도 이동했다. 그래서 화면상의 공격 상태만 유지되고, 작은 원 Shape는 적과 겹치지 않는 경우가 있었다. M6R 검증은 가짜 표적을 핀 위치에 직접 생성해 이 문제와 통상 전투 간격을 검증하지 못했다.
- Raider ReceiveArea는 루트 아래 30px, 반경 25px에 있어 플레이어 주먹의 상체 높이와 수백 픽셀 차이가 났다. Boss ReceiveArea도 상체 실루엣보다 낮고 범위가 좁았다.

## 변경

- HIGH 보완에서 controller의 공격별 pin 보정과 X 클램프를 제거했다. 승인 원화의 실제 손을 국소 메시로 움직이고, 화면에 렌더링되는 삼각형에서 주먹 좌표를 보간한다. `get_fist_contact_global()`와 Shape 중심은 같은 좌표다. 공격 Flash도 같은 접점을 따른다.
- 기본 타격과 Num4 돌진은 전방의 실제 hit receiver까지 남은 거리와 접촉 도달 범위를 보고 이동량을 제한한다. 피해는 여전히 실제 주먹 Shape가 적 ReceiveArea 또는 물리 몸체와 겹칠 때만 적용된다. 활성 구간, 회복 시간, 피해량, 넉백은 유지했다.
- Raider ReceiveArea는 상체 중심(y=-326), 반경44px다. 원 외곽 48개 표본 모두 실제 상체 알파 안에 들어간다. Boss 시각 루트는 발 위치를 유지하며 2.2배, y=-114.4로 설정했다. Boss ReceiveArea는 y=-320, 반경45px, 높이160px 캡슐이며 모든 외곽 표본이 실제 Head/Torso 다각형 내부에 들어간다. 기존 반경54px·높이260px 캡슐은 빈 공간을 포함하여 축소했다.
- 물리 쿼리 전에 현재 위상과 좌우 방향을 시간 진행 없이 동기화한다. 전투 자세는 위상 시간에서 직접 계산하며 렌더 프레임 수에 의존하는 이중 보간을 제거했다. 렌더 후에도 활성 Shape 위치를 실제 손에 맞춘다. 기존 startup/active/recovery, 피해량과 1회 피해 계약은 유지한다.

## Window 검증

`tests/m6s_real_combat_damage_window_smoke.gd`는 Godot의 실제 Window에서 `Input.action_press()`로 전투 입력을 흘려 보낸다. 표적을 주먹 위치로 옮기지 않고, 플레이어와 실제 Raider/전투 활성 Boss를 120px 간격으로 배치했다.

| 표적 | 입력 | 실제 HP 피해 | 실제 Shape 쿼리 겹침 |
|---|---|---:|---|
| Raider | J 1~3타 | 6 (1+2+3) | 확인 |
| Raider | Num4 / Num5 | 3 / 2 | 확인 |
| 활성 Boss | J 1~3타 | 6 (1+2+3) | 확인 |
| 활성 Boss | Num4 / Num5 | 3 / 2 | 확인 |

각 기본 타격은 hit 신호 1회씩, 각 스킬은 1회 발생을 확인했다. 기존 기본/스킬 활성 시간은 0.105/0.12/0.14초와 0.12/0.18초다. 좌우 120px 실전 피해와 J1~3 전체·Num4·Num5 각각의 후방/깊이 60px/허공 미명중을 추가했다. 단일 J의 400px 허공 검사는 유지한다. 전체 콤보와 돌진은 물리 이동으로 400px 표적에 도달할 수 있어, 전체 궤적 밖의 허공 표적은 700px로 배치한다. Num5 깊이 검사는 Shape가 겹치는 decoy도 별도로 거부한다. M6Q의 y=-19 가짜 발 리시버 게이트는 이 실제 적 게이트를 실행하는 호환 진입점으로 바꿨고, M6R의 주먹/Shape 일치·작은 반경·1회 피해 계약은 별도로 유지한다.

최종 HIGH 증거와 실행 결과는 [M6T 검토 기록](m6t_high_review.md)을 참조한다. 사람의 최종 육안 승인을 뜻하지 않는다.

Godot 실행 로그에서 사용자 로그 디렉터리 쓰기 실패와 Windows root certificate store 읽기 오류가 출력됐지만, Window 렌더러가 열렸고 테스트 프로세스는 정상 종료 코드 0으로 PASS를 반환했다.
