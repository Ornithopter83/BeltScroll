# M6I 전투 포즈 동기화 게이트

## 점검 범위

본편 상태 우선순위는 `final-down > 피격/경직 > Num4·Num5 > 기본 1·2·3타 > 이동·점프·대기`다. 애니메이터의 승인 포즈 선택도 같은 해석 결과를 사용한다. 피격 플래시가 남아 있는 프레임에는 오래된 공격·스킬 필드가 남더라도 해당 포즈를 표시하지 않는다. 경직 해제 뒤에는 컨트롤러가 공격을 취소한 새 상태를 표시한다.

공격 단계별 활성 판정 시간은 Player 컨트롤러 값 `0.105 / 0.120 / 0.140초`와 시각 타이머를 비교한다. Num4/Num5 활성 시간은 각각 `0.120 / 0.180초`다. 새 스모크는 공격 단계별 활성 시작에서 실제 Hitbox `monitoring` 값, 애니메이션 상태, phase progress를 기록하고, Window process frame과 표시 pose key를 같은 행에 남긴다. Num 스킬은 임시 procedural 모션으로 기록한다.

## Window 스모크

```powershell
$OutputEncoding = [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new()
godot --path . --script res://tests/m6i_combat_visual_sync_smoke.gd
```

실제 Window Viewport가 필요한 검사다. 결과의 `m6i-window-sample` 행에는 Window frame, 컨트롤러 phase와 남은 시간, 애니메이션 상태, 표시 포즈, 프레임 상태가 함께 출력된다. 공격 활성 경계에서 progress는 0이어야 하며 해당 Hitbox도 monitoring 상태여야 한다.

스모크는 피격 플래시 및 경직 중 오래된 공격·스킬 상태의 억제, Num4/Num5의 임시 동작 분류, 승인 contact keypose 위의 변환 단계 표기, final-down 정착, 좌우 전환의 압축 구간 mirror 변경을 점검한다. 임시 동작을 승인된 연속 애니메이션 프레임으로 표시하지 않는다.

## 승인 경계 및 증거

기존 승인 contact 원화만 기존 allowlist를 통해 표시한다. 신규 후보를 Player 씬, 애니메이션 bank 또는 allowlist에 연결하지 않았다. 임시 procedural skill/transform은 원화 승인이나 연속 프레임 승인으로 간주하지 않는다.

## 판정

- 코드 수정: 승인 pose 선택이 우선순위 resolver를 따르며 피격 상태에서 공격 포즈 재출현을 차단한다.
- 코드 smoke: 실제 Window 프레임별 상태·판정·포즈 일치를 출력하도록 추가했다.
- 새 Window 실행: Godot 4.7.2, 960×540 Window Viewport에서 실행 PASS. 측정한 활성 시작 행은 attack1=`0.105s/contact/progress 0/hitbox on`, attack2=`0.120s/contact/progress 0/hitbox on`, attack3=`0.140s/contact/progress 0/hitbox on`이다. 출력 Window sample frame은 순서대로 0, 1, 2였다.
- 새 Window 상태 검사: 피격 플래시와 경직 동안 오래된 공격/스킬 필드가 유지된 충돌 사례에서도 `hit`와 PlayerArt가 표시됐고 승인 Blender pose는 숨겨졌다. Num4/Num5 활성 경계도 각각 `0.120s`/`0.180s`, progress `0`, 해당 스킬 Hitbox on으로 기록됐다. 실제 `receive_hit` 호출로 Num5를 끊었을 때 skill id/phase와 Hitbox가 해제되고 피격 상태로 전환됐다. 좌우 mirror는 turn windup 동안 고정된 뒤 compression 경계에서 전환됐으며 실제 lethal hit 이후 KO는 final-down으로 정착했다.
- 실행 환경: smoke 검사 모두 PASS. Godot가 `user://logs` 작성과 Windows root certificate store 읽기에 대한 환경 오류를 출력했지만 Window 렌더와 검사는 완료됐다.
- 미승인 후보: 본편 연결 없음.
