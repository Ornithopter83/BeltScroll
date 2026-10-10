# M6i Enemy Stagger Gate

## 판정

**통과** — Raider와 Ruins Warden의 피격 중단, 경직 잠금, 넉백 후 복귀, KO 처리를 자동 스모크로 확인했다. 플레이어 공격·보스 HUD·스테이지 전투 계약 회귀 스모크도 통과했다.

## 확인 범위

| 항목 | Forest Raider | Ruins Warden |
| --- | --- | --- |
| 선딜·공격 중·후딜 피격 | 공격 상태 즉시 초기화, 공격 감지 해제, 전조 제거 | 공격 상태 즉시 초기화, 공격 감지 해제, 베기·강타 전조 제거 |
| 경직 중 | AI 공격 재시작 차단, 넉백 감쇠, 연속 피격 시 경직·방향 갱신 | AI 공격 재시작 차단, 넉백 감쇠, 연속 피격 시 경직·방향 갱신 |
| 경직 종료 | 추적과 공격 상태 복귀 | 추적과 공격 상태 복귀 |
| KO | 신호 1회, 본체와 ReceiveArea 충돌 해제 | 신호 1회, 본체와 ReceiveArea 충돌 해제, HP 바 0 동기화 |

## 구현

피격 즉시 ReceiveArea 충돌 해제를 명시하도록 Raider KO 경로를 보완했다. 나머지 피격 처리에서 공격 취소, 전조 제거, 경직 중 AI 건너뛰기와 KO 중복 방지 계약은 기존 동작을 스모크로 고정했다.

검증 스크립트: `tests/m6i_enemy_stagger_interruption_smoke.gd`

실행 명령:

```powershell
godot.exe --headless --path . --script res://tests/m6i_enemy_stagger_interruption_smoke.gd
godot.exe --headless --path . --script res://tests/forest_raider_smoke.gd
godot.exe --headless --path . --script res://tests/m6d_boss_hud_ai_smoke.gd
```

세 스크립트 모두 모든 검사 통과 및 종료 코드 0을 반환했다. 이 Windows 환경에서 Godot가 `user://logs` 로그 파일 생성과 시스템 인증서 저장소 읽기에 실패했다는 시작 경고를 출력했지만, 씬 로드와 스모크 검증에는 영향이 없었다.
