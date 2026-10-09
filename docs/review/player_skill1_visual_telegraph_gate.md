# Num4 직선 돌진 시각 검토

## 구현 범위

- 승인된 v8 정지 그림과 Player 이동·Skill1Hitbox·피해량·쿨다운 코드는 수정하지 않았다.
- Num4에는 임시 절차적 표시를 추가했다. 별도의 실제 주먹 원화가 없으므로 팔/주먹 포즈를 새 승인 그림처럼 가장하지 않는다.
- 시작은 낮은 체중 싣기와 후방 지면 스트로크, active는 전방 직선 경로와 끝의 평행 충격 꺾쇠, recovery는 줄어드는 경로와 발밑 되돌림 표시로 읽힌다.
- 표시 노드는 Player의 `skill_phase`, `skill_phase_remaining`, `facing_direction`을 사용한다. `skill_hit(1)` 때만 짧은 접촉 스파크를 켠다. 취소와 KO에서는 표시를 감춘다.
- 그리기는 Player 월드 원점(발/바닥 기준)에 붙고, 우향·좌향은 실제 방향 부호를 사용한다. Num5는 회전 포즈이므로 원형 회전 표시와 구분된다.

## Window 검토

`assets/art/review/player_skill1_visual_telegraph_window.png`는 실제 1920×1080 Window post-draw 프레임 12개를 2열로 정리한 검토 시트다. 우향과 좌향 각각 startup, 실제 `skill_hit` 접촉, recovery, 취소, KO, Num5 회전 참조 프레임을 담는다. 각 패널은 지면 기준선과 phase 시계, Skill1Hitbox 상태를 함께 표시한다.

이 파일은 검토 캡처이며 승인 Num4 원화가 아니다. 애니메이션 manifest나 본편 art 등록에는 추가하지 않았다. 주먹 자체를 그린 전용 원화가 없는 임시 VFX 표현이라는 제약을 유지한다.

## 검토 결과

- 우향/좌향 Window 캡처에서 12개 상태 프레임을 확보한다.
- 접촉 프레임은 실제 Skill1Hitbox 겹침으로 발생한 `skill_hit(1)`을 기다리며, 회복과 취소는 실제 Player phase 전환을 확인한다.
- 별도 사용자 확인용 회귀 스모크: `godot --path . --script res://tests/player_skill1_visual_telegraph_smoke.gd` (창 있는 renderer 필요).
