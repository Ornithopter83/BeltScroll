# M6K Num4 직선 돌진 가독성 검토 게이트

## 적용 범위

- `scripts/effects/player_skill1_dash_visual.gd`의 절차적 VFX만 수정했다. 피해량, 쿨다운, 이동 속도, 활성 시간, 충돌 모양과 물리 판정은 변경하지 않았다.
- startup은 낮은 전방 축적 자세와 뒤쪽으로 당기는 짧은 선으로 준비 동작을 보여 준다.
- active는 `Hitboxes/Skill1Hitbox`의 회전·중심·사각형 길이를 조회해 그 축을 따라 가속 궤적과 전방 주먹 끝을 그린다. 효과의 전방은 현재 플레이어 방향값이 아니라 실제 공격 박스 방향을 따른다.
- recovery는 직선 잔광과 발밑 감속 표식을 짧게 접어 돌진 후 감속을 보여 준다. 원형 회전이나 원형 충격파를 사용하지 않아 Num5의 회전 효과와 구별한다.
- `skill_hit(1)`은 Skill1Hitbox가 활성이고 실제 active phase일 때만 접촉 효과를 켠다. 겹친 hit receiver 위치를 우선 사용하고, 없으면 실제 hitbox 중심에 표시한다.
- 방향이 바뀌면 실제 hitbox 축을 다음 렌더에서 다시 읽어 이전 방향의 흔적을 남기지 않는다. 기술 phase 종료, KO, hitstun, 플레이어 피격 신호, 기술 취소 시 표시와 접촉 잔광을 지운다.

## 확인 게이트

`tests/m6k_skill1_dash_readability_smoke.gd`는 다음을 확인하도록 작성했다.

- Player 장면이 설치하는 Skill1 VFX가 존재한다.
- VFX 방향·주먹 선단이 실제 108×58 Skill1Hitbox 변환과 크기를 참조한다.
- 실제 Skill1Hitbox overlap으로 `skill_hit(1)`이 발생하고 접촉 잔광이 켜진다.
- startup/active/recovery cue가 있으며 원형 그리기가 없다.
- hitstun 및 취소 때 VFX가 사라진다.

스모크 실행 명령:

```powershell
godot --headless --path . --script res://tests/m6k_skill1_dash_readability_smoke.gd
```

2026-10-10 HIGH 재검증에서 `tests/m6k_skill1_dash_readability_smoke.gd`가 PASS했다. 기존 `interrupted`와 `point` 타입 추론 파스 오류에 명시적 GDScript 타입을 부여해 Player의 `VisualAnimator`가 컴파일되고 Skill1DashVisual이 설치됩니다. 실제 Player 장면에서 startup 표시, Skill1Hitbox overlap에 따른 `skill_hit(1)` 및 접촉 flash, 취소와 피격 잔류 제거까지 실행 검증했습니다. 피해·쿨다운·이동·물리 판정 계약은 변경하지 않았습니다.

수정 후 실제 gameplay Window 16프레임도 다시 캡처했으며, Num4 phase와 중단 후 이동 복귀가 자동 게이트를 통과했습니다. 기준 MP4에서 대응 시각 프레임을 신뢰성 있게 추출하지 못했고 사람의 최종 시각 승인도 대기 중입니다. 자동 캡처는 Num5 대비 연출의 사람 승인을 대신하지 않습니다.
