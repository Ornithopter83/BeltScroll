# M6N enemy collision alignment gate

## 판정값 기록

아래 값은 장면과 공격 상태에서 `CollisionShape2D`의 실제 `Shape2D`, 부모 `Area2D` 위치를 읽은 값이다. F10 collision overlay에서 보이는 원점은 각 Area2D의 런타임 전역 변환이며, 크기는 다음 Shape2D 값과 일치해야 한다. 위치는 적 root 기준 로컬 좌표이며 Boss slash의 좌우 부호는 바라보는 방향에 따라 바뀐다.

| 적 / 상태 | 판정 | 실제 모양과 크기 | 중심 위치 | 실루엣·접촉 비교 |
|---|---|---|---|---|
| Raider | 몸체 CollisionShape2D | 캡슐, 반경 18, 높이 42 | `(0, -19)` | 발 기준 y `-40..2`, 폭 36. 작은 발판/몸통 충돌 footprint이며 큰 원화 전체를 막지 않는다. |
| Raider | ReceiveArea | 원, 반경 30 | `(0, -19)` | 몸체를 감싸며 y `-49..11`. 공격 가능한 몸통과 상단 회피 여유를 포함한다. |
| Raider | AttackArea 활성 중 | 사각형 `78×48` | `(±54.72, -30)` | 바라보는 방향 전방에 놓이고 y `-54..-6`의 상체 접촉대와 겹친다. 범위 밖 거리를 추가 명중시키는 보조 판정은 없다. |
| Boss | 몸체 CollisionShape2D | 캡슐, 반경 31, 높이 78 | `(0, -37)` | 발 기준 y `-76..2`, 폭 62. 장갑 몸통과 발을 받치며 머리 장식은 물리 통로를 막지 않는다. |
| Boss | ReceiveArea | 원, 반경 54 | `(0, -39)` | 몸통 중심에 놓여 y `-93..15`, 몸 실루엣을 충분히 포함한다. 비활성/KO 때 `monitorable=false`다. |
| Boss slash | AttackArea 활성 중 | 원, 반경 67 | `(방향×86, -47)` | 전방 베기 telegraph와 겹치는 상체 원형 접촉부. 좌우 방향을 따라간다. 깊이 허용치는 root 기준 66이다. |
| Boss slam | AttackArea 활성 중 | 원, 반경 125 | `(0, -18)` | 지면 telegraph의 넓은 충격 구역. 깊이 허용치는 root 기준 105이다. |

Boss의 비활성 AttackArea는 기본 slash 반경 67 원으로 초기화되어 표시된다. 공격 준비 시에도 `monitoring=false`이며 활성 단계에서 slash/slam 도형과 위치를 갱신한 후 `monitoring=true`가 된다.

## 발견 및 변경

Boss 판정 비교에서 두 가지 런타임 불일치를 확인했다. Player를 직접 찾는 fallback이 실제 Area2D 겹침 바깥에서도 AttackArea 중심과 Player root 사이 별도 거리로 추가 명중시킬 수 있다(slash 112, slam 125). 또 깊이 허용값은 이 fallback에만 적용되고, Area2D 겹침 처리에는 적용되지 않는다. 스모크는 slash 원형 범위 밖 fallback 명중과 slam 원에 실제 겹치는 y=120 대상(허용치 105 초과)의 피해를 재현한다. 보정은 `scripts/enemies/ruins_warden_boss.gd`의 판정 경로 변경이 필요하지만 이번 작업의 지정 WRITE_PATH에 포함되지 않아 수정하지 않았다. 따라서 Boss의 런타임 명중 경로는 아직 완료되지 않았다.

Boss 장면 초기 AttackArea가 몸체 캡슐 리소스를 참조해 F10 비활성 표시가 공격 도형과 달랐다. 초기 shape를 slash 반경 67 원으로 고쳤고 런타임 slam에서 기존처럼 반경 125 원으로 교체된다. Raider의 몸체·수신·직사각형 공격 크기와 공격 배치는 실루엣 및 windup→active 접촉 기준과 정렬되어 있어 변경하지 않았다.

Raider 피격은 기존 `_cancel_attack()`이 AttackArea와 flash를 끈다. KO 시 본체 layer와 ReceiveArea도 내려간다. Boss 피격 역시 `_cancel_attack()`으로 전조와 공격 감지를 끄며, 비전투/KO 때 본체와 ReceiveArea를 비활성화한다.

## 실행 게이트

`tests/m6n_enemy_collision_alignment_smoke.gd`는 게임 씬의 실제 Raider/Boss를 인스턴스화하고, layer 1의 `CharacterBody2D` 캡슐 수신자를 붙여 Area2D 물리 overlap을 확인한다. Raider 사각형 안/바깥, Boss slash 전방/원형 범위 바깥, slam 원의 허용 깊이 초과 overlap 재현, 실제 `receive_hit` 호출 횟수, KO 후 AttackArea/ReceiveArea 비활성을 검사한다. 거리 계산으로 겹침을 흉내 내지 않는다.

자동 실행 결과: `godot.exe --headless --path . --script tests/m6n_enemy_collision_alignment_smoke.gd`와 기존 `tests/m6n_f10_collision_overlay_smoke.gd`가 모두 PASS했다. F10 스모크는 실제 모양 종류·slash/slam 반경과 위치 추적, F10 전환, 카메라 투영 및 KO 표시 상태를 확인했다. Godot가 두 실행에서 `user://logs` 쓰기 실패를 경고했지만 스모크는 PASS로 끝났다. 문서화한 Boss 범위/깊이 초과 명중은 테스트가 의도적으로 재현해 기록한 현 동작이다. Window에서 F10을 켠 실제 게임 화면의 픽셀 외곽과 사람이 본 준비·접촉 애니메이션에 대한 수동 영상 검수는 기록하지 않았다.
