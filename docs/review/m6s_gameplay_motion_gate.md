# M6S 본편 게임플레이 모션 검수 게이트

## 변경 범위

- 본편 보행은 이동 거리와 속도에 연동되는 4구간 stride를 보행 중에만 진행한다. HIGH 보완에서는 기존 승인 idle 원화를 국소 메시로 표시하여 지지 발은 월드 접지점에 유지하고, 반대쪽 무릎·발을 들어 passing 동작을 만든다. 골반과 어깨는 별도로 상승한다. 단일 원화 전체의 회전·확대만으로 보행을 만들지 않는다. 공격·피격·점프·스킬 상태에는 보행 위상이 섞이지 않는다.
- 공격 1~3은 각각 등록된 기존 접촉 원화를 준비, 타격, 콤보 유지, 복귀 동안 계속 사용한다. 준비·타격·복귀에서 국소 팔 변형으로 J1의 주먹 뻗기, J2의 가로 궤적, J3의 올려치기를 구별한다. 앞발을 루트 중심에 붙여 몸 전체가 뒤로 밀리던 배치를 stance 중심으로 수정했다. `combo_hold`는 해당 타격 원화를 유지하며 IDLE이나 별도 전신을 중첩하지 않는다. 복귀 끝에서 유지 자세로 갑자기 다시 뻗는 이동도 제거했다.
- Num4는 준비에서 팔을 앞으로 뻗고 전방 이동으로 연결한다. Num5는 팔꿈치를 중심으로 전완을 돌리는 궤적과 몸의 되감기로 구별한다. 별도 VFX를 제외하고도 팔과 몸의 동작이 다르다.
- 실제 기본 타격에 사용하는 접촉 원화는 기존 승인 등록 세 장이다. 보행 후보 PNG는 종전대로 DEBUG 격리 preview 전용이며 manifest/allowlist 승격은 없다.
- `get_fist_contact_global()`과 공격/스킬 컨트롤러의 startup, active 판정창, recovery 타이밍은 변경하지 않았다. 공격 원화 교체만으로 판정 시간이 늘어나지 않는다.

## Window 연속 프레임 검토

`tests/m6s_gameplay_motion_window_smoke.gd`를 창 렌더러로 실행한다. 테스트는 실제 gameplay Player에서 공격 준비→활성 타격→`combo_hold`→복귀를 순서대로 구동하고 매 Window 프레임의 표시 원화 경로, 전신 global 위치·회전·크기와 PlayerArt 위치를 직전 샘플과 비교한다. 최소 세 구간에서 위치 또는 자세 변화가 있어야 통과한다. 각 프레임에 전신 Sprite가 정확히 하나인지, combo hold에서 IDLE이 아닌 단계별 고유 접촉 원화가 표시되는지도 확인한다. Num4/Num5 각 동작도 startup/active/recovery 연속 샘플을 비교한다.

```powershell
& 'C:\Project\Godot\godot.exe' --path . --script res://tests/m6s_gameplay_motion_window_smoke.gd
```

4위상 후보 PNG는 `tests/m6o_walk_four_phase_window_smoke.gd`의 명시적 DEBUG preview에서만 선택한다. 일반 gameplay에서는 후보 PNG를 선택하지 않는다. m6s 테스트의 수동 진행 중 자동 `_process`가 추가로 진행되던 문제도 수정했다. 본편의 실제 발 교대·접지·골반 상승은 `tests/m6t_gameplay_body_window_smoke.gd`에서 물리 이동 입력으로 별도 확인한다. 최종 실제 메시 삼각형 기준 접지 오차는 0.1240px, 골반 높이 변화는 13.08px였다. 후보 PNG를 manifest/allowlist에 추가하지 않았다.

Window에서 렌더링한 이전 기준 8e8148e와 수정 상태의 30개 순차 프레임은 [이전](../../temp/high_body_before.png), [수정 후](../../temp/high_body_after.png)에서 비교한다. 행은 보행, J1, J2, J3, Num4, Num5이고 공격 열은 준비→초기 타격→후기 타격→유지/초기 복귀→복귀다. 코드와 Window 프레임 검토는 수행했으며, 사람의 최종 육안 승인은 별도 PENDING이다. 자세한 판정은 [M6T 검토 기록](m6t_high_review.md)을 참조한다.

## 판정 기준

정지 프레임의 회전/크기 차만으로 PASS를 선언하지 않는다. Window 실행 결과의 연속 프레임 변화, 직전 상태와 다음 상태의 연결, 전신 단일 표시, 타격별 원화 고유성, 기존 물리 타이밍 유지, 미승인 보행 후보의 격리를 모두 검토한다. Smoke가 PASS해도 시각적 승인 자체는 별도 수동 검수다.
