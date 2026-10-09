# 전투 스킬 HUD 검수

## 구현

- 기존 플레이어 체력/지연 피해 바, 콤보, Raider 수 및 Raider별 머리 위 체력 바를 유지했다.
- 화면 상단 중앙 `(650, 34)`, `620×112` 영역에 Num4 돌진과 Num5 회전 슬롯을 추가했다. 기존 체력 패널, Raider 수 패널, 콤보 패널과 서로 겹치지 않는 영역이다.
- 슬롯은 Player의 `skill_phase`, `skill_id`, `skill_phase_remaining`, `skill_cooldowns`를 읽는다. 준비 동작·사용 중·회복·재사용 대기·사용 가능 상태에 서로 다른 문구와 색/진행 바를 표시한다.
- 스킬 쿨다운 진행 바의 기준은 게임 세션에 이미 설정된 스킬 쿨다운을 읽으며, 해당 설정이 없을 때만 Player 기본값을 기준으로 삼는다. 전투 판정과 쿨다운 설정은 변경하지 않았다.
- Raider 머리 위 체력 바 배치에서 새 스킬 패널을 고정 HUD 장애물로 취급해 패널 위를 침범하지 않게 했다. Raider 바는 기존처럼 카메라 변환, 줌, 회전 및 실루엣 회피 계산을 따른다.
- 일시정지 중 HUD는 일시정지 직전 상태를 유지하고, 재개 후 실시간 Player 상태를 다시 읽는다. KO는 기존 체력 UI에 반영되며, 재시작 시 새 HUD와 두 준비 상태로 초기화된다.

## 검증

- `godot --headless --path . --script res://tests/combat_hud_smoke.gd` 통과. 두 슬롯 이름, 준비/사용/회복/쿨다운 상태, 남은 시간, 상태별 독립성, pause 유지, 체력 피격·회복·KO, Raider 체력 바 및 카메라 이동, 재시작 복원을 확인했다.
- `godot --path . --script res://tools/capture_combat_skill_hud.gd` 실제 OpenGL 전체화면 Window 렌더러에서 실행했다. 모니터의 실제 Window frame을 캡처하고, 16:9 프레임일 때 검수 PNG를 1920×1080으로 맞췄다.
- 캡처: [combat_skill_hud_window.png](../../assets/art/review/combat_skill_hud_window.png). 게임 배경, 플레이어와 Raider 실루엣, 양측 HUD, 세 Raider의 머리 위 체력 바가 함께 보이는지 확인했다.

## 검수 한계

캡처 스크립트는 Window에서 HUD 레이아웃을 확인하도록 실시간 Player 스킬 필드만 검수용 상태로 지정하고 Player 물리 처리를 잠시 중지한다. 일반 게임 플레이에서는 Player 스킬 상태와 쿨다운이 원래 전투 로직에서 갱신된다.
