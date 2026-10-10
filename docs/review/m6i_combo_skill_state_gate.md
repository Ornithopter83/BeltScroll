# M6I 콤보·스킬 상태 검수 게이트

## 상태와 입력 규칙

- 기본 공격은 startup → active → recovery 순서로 진행한다. 1/2/3타 시간은 각각 `0.075/0.105/0.20초`, `0.085/0.12/0.22초`, `0.10/0.14/0.28초`다.
- 각 hitbox는 active 진입 시 켜지고 active 종료와 함께 꺼진다. startup·recovery에서는 비활성이다. 각 타격 단계 진입 때만 대상 중복 기록을 비우므로 한 단계 안의 다중 physics tick은 같은 대상을 재명중하지 않는다.
- 공격 선입력은 0.60초 동안 보존하고 recovery가 끝날 때 소비한다. 1→2→3 단계가 끝나면 콤보 상태와 버퍼를 초기화하며, 다음 입력은 1타부터 시작한다.
- Num4는 전방 돌진, Num5는 제자리 회전 공격이다. 스킬 hitbox는 각각 전방 52px 중심의 `108×58` 직사각형(전방 최대 약 106px, 깊이 ±29px)과 반경 64px 원이다. active 동안 대상별 한 번만 명중한다.
- Num4/Num5 startup·active·recovery는 각각 `0.16/0.12/0.42초`, `0.22/0.18/0.55초`다. 쿨다운은 각각 1.35초와 1.8초이며 발동 시점에 적용한다. 피격 또는 가드로 중단되어도 쿨다운은 유지된다.
- 스킬 중 기본 공격 입력은 무시한다. 가드 입력과 피격은 스킬을 즉시 취소하고 skill hitbox를 끈다. 피격은 기본 콤보도 취소하며, KO는 공격·스킬 상태 및 모든 hitbox를 종료한다. 쿨다운 감소 외에는 취소 후 잔여 phase 타이머가 남지 않는다.
- 가드 중/점프 중/피격 경직 중/KO 상태에서는 새 공격과 스킬 발동을 받지 않는다. 경직 타이머가 끝나면 다음 physics tick부터 이동과 공격 입력이 재개된다.

## 계약 유지

`attack_started(stage)`, `attack_hit(stage)`, `player_hit(stage)`, `player_ko`, `skill_started(skill_id)`, `skill_hit(skill_id)` 신호와 기존 신호 인자 형식은 유지한다. HUD가 읽는 공격 단계/진행도와 스킬 쿨다운 변수도 기존 이름과 데이터 형식을 유지한다. Num4/Num5 입력 매핑은 프로젝트 InputMap 소유로 둔다.

## 자동 스모크

`godot --headless --path . --script res://tests/m6i_combo_skill_state_smoke.gd` 실행으로 시간 경계, 콤보 버퍼 소비, 새 콤보 복귀, 스킬 cooldown/입력 차단, 피격 중단 및 대상 중복 방지를 확인한다. Window에서의 타격 거리·애니메이션 인수 검수는 별도 수동 항목이다.
