# Num5 회전 예고 Window 검토

## 구현 범위

- 기존 Skill2 startup 0.22초, active 0.18초, recovery 0.55초 시계를 그대로 읽는 임시 절차적 VFX를 추가했다. 전투 컨트롤러의 이동, 피해, 판정, 쿨다운과 승인 원화는 수정하지 않았다.
- startup은 자주색 원호와 바닥 원으로 회전을 예고한다. active는 분홍·흰색 원호를 회전 방향으로 펼쳐 원형 타격 궤적을 표시한다. recovery는 원호가 반대 방향으로 짧아지고 바닥 충격 잔상이 커지며 사라져 감속 복귀를 보여준다.
- Num4의 청록색 평행 직선 돌진 선과 끝의 직선형 꺾쇠에 대비해 Num5는 분홍·보라 원호, 회전 접선 표시, 원형 충격 잔상을 사용한다.
- 접촉 스파크는 `skill_hit(2)`가 발생하고 실제 `Hitboxes/Skill2Hitbox`가 monitoring 중일 때만 짧게 보인다. 취소 상태를 animator가 확인하거나, 피격·KO 신호가 오면 VFX와 접촉 잔상을 즉시 지운다.
- 효과는 캐릭터의 발 기준 월드 위치에 붙인 임시 절차 표현이다. 승인된 Num5 원화 애니메이션이 완성되었다고 주장하지 않으며 원화 manifest에도 등록하지 않았다.

## 실제 Window 캡처

`assets/art/review/player_skill2_visual_telegraph_window.png`는 본편 Player 장면의 실제 1920×1080 Window post-draw 캡처 12개를 2열 × 6행으로 구성한 1920×3240 검토 시트다. 우향과 좌향 각각 startup, Skill2Hitbox 접촉, recovery, 취소, 피격, KO 상태를 담는다. 접촉 패널은 테스트 receiver가 실제 Skill2Hitbox에 겹쳐 `skill_hit(2)` 신호가 발생한 active 상태에서 캡처한다.

캡처 재생성 및 상태 검증:

```powershell
& 'C:\Project\Godot\godot.exe' --path . --script res://tests/player_skill2_visual_telegraph_smoke.gd
```

이 캡처는 시각 검토 자료이며 승인 원화나 완성 애니메이션으로 취급하지 않는다.
