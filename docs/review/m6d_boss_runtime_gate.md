# M6D 보스 런타임 검수

## 표시와 승인 경계

실제 보스의 머리 위 `HealthBar` 노드와 스크립트의 `health_bar` 참조는 호환성 및 회귀 계약을 위해 유지합니다. 씬에서 노드를 숨기고 `_ready()`에서도 숨김을 고정하며, 체력이 바뀔 때 값은 계속 갱신합니다. 플레이 중 보스 체력은 좌상단 `CombatHUD`의 보스 행으로 표시합니다.

현재 보스 시각은 `Polygon2D`로 만든 임시 placeholder입니다. 기하학적 형태와 제한된 색면만 표현하므로 최종 보스 원화 수준의 세부 묘사, 표면 질감, 애니메이션 품질을 제공하지 않습니다. 미승인 보스 PNG/WebP는 씬이나 본편 리소스에 연결하지 않았습니다. 별도 시각 검수와 승인이 있기 전까지 placeholder를 사용합니다.

## 자동 런타임 재검증

프로젝트 루트에서 실행합니다.

```powershell
godot --headless --path . --script res://tests/m6d_boss_hud_ai_smoke.gd
```

스모크는 본편 Player, 보스, CombatHUD 씬을 실제로 인스턴스화해 실행합니다. 시작 시 보스의 비활성·무충돌 상태와 숨은 바를 확인한 뒤 전투를 활성화하고, HUD 행, 플레이어 추적, slash와 slam의 AI 전조 및 실제 명중, 숨겨진 참조의 체력 동기화, KO 상태와 `boss_ko` 신호를 검사합니다.

2026-10-10 HIGH 재검수에서 기존에 보고된 `scripts/game/game_session.gd:204`의 `stone` 타입 추론 파싱 오류는 재현되지 않았습니다. 현재 `stone_colors`와 `stone`은 명시적으로 타입이 지정되어 있습니다. 비헤드리스 `tests/m6d_full_playthrough_window_smoke.gd`가 `main.tscn`으로 시작해 세 구간 이동, Raider·보스 전투, 승리, 재시작, 피격과 패배까지 PASS했습니다. 이는 자동 입력 이벤트 기반 Window 검증이며 물리 키보드 관찰을 뜻하지 않습니다. 세부 기록은 [M6D 전체 플레이 게이트](m6d_full_playthrough_gate.md)와 [2026-10-10 HIGH 대조표](m6d_high_review_2026-10-10.md)를 참조합니다.

자동 스모크는 상태 전이와 HUD 배치를 확인합니다. placeholder의 미술 품질에 대한 사람의 시각 승인을 대신하지 않습니다.
