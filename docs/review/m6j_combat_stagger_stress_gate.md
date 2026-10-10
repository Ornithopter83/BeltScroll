# M6J 전투 경직 스트레스 게이트

## 검증 방식

`tests/m6j_combat_stagger_stress_smoke.gd`에서 Player 원본 씬을 실행했습니다. 공격, Num4/Num5, 방향 이동, 가드 입력은 프로젝트 `InputMap`에 등록된 `InputEventKey`를 복제해 `Input.parse_input_event()`로 전송하고, 프레임마다 눌림과 해제를 분리했습니다. 상태와 신호, hitbox의 실제 `monitoring` 값, 위치, 체력 및 `Engine.time_scale`을 확인했습니다.

스킬 및 공격의 선딜·활성·후딜 중단 시나리오는 해당 단계까지 키 이벤트로 실행한 다음, 플레이어의 기존 `receive_hit()` 계약을 호출해 적중을 전달했습니다. 따라서 이 게이트는 입력·중단 상태 처리를 검사하며 적의 공격 hitbox 배치와 물리 접촉 시점은 별도 검사 대상입니다.

## 결과

- 고속 키 연타에서 입력 버퍼는 콤보 순서를 지키고 세 단계보다 많은 공격을 만들지 않았습니다. 단계별 선입력은 1→2→3 순서로 실행됐습니다.
- 공격 중 Num4/Num5 입력, 스킬 실행 중 재입력, Num4 쿨다운 중 재입력이 새 발동을 만들지 않았습니다. Num4와 Num5는 각각 실행됐습니다.
- 기본 공격 활성 판정과 스킬 활성 hitbox를 확인했습니다. 공격 피격 취소 및 스킬 선딜·활성·후딜 피격 후 공격·스킬 hitbox가 꺼졌습니다.
- 경직 중 이동, 공격 및 스킬 입력이 차단됐습니다. 더 긴 연속 피격은 경직을 갱신했고, 경직 종료 후 이동과 공격 입력이 다시 동작했습니다.
- 키 입력으로 가드 상태에 진입해 피해와 경직 감소를 확인했습니다. 치명타는 KO 신호를 한 번 내고 입력으로 상태가 되살아나지 않았습니다.
- 중첩 hit-stop 요청 후 감속 상태를 유지하고 원래 `Engine.time_scale`로 복구했습니다.
- 재현되는 플레이어 컨트롤러 결함이 없어 `scripts/player/player_controller.gd`는 변경하지 않았습니다. 공격·스킬 신호, 판정 상수, HUD와 에디터 설정도 수정하지 않았습니다.

## 실행한 검증

모두 종료 코드 0으로 통과했습니다.

| 명령 | 결과 |
|---|---|
| `godot --headless --path . --script tests/m6j_combat_stagger_stress_smoke.gd` | 스트레스 게이트 통과 |
| `godot --headless --path . --script tests/player_combat_smoke.gd` | 실제 판정, 피격 복귀 및 KO 회귀 통과 |
| `godot --headless --path . --script tests/m6i_combo_skill_state_smoke.gd` | 단계 타이밍, 입력 버퍼 및 스킬 상태 통과 |
| `godot --headless --path . --script tests/m6i_enemy_stagger_interruption_smoke.gd` | 적 경직·갱신 및 기존 전투 계약 통과 |

이 실행 환경은 `user://logs` 로그 파일 생성과 OS 루트 인증서 읽기 오류를 출력했지만, 테스트 실행과 판정에는 영향을 주지 않았고 모든 명령은 성공 종료했습니다.
