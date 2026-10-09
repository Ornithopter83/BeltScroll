# schema v1 확장 클립 GUI 검수 게이트

독립 WinForms 편집기는 기존 `idle`, `attack1`, `attack2`, `attack3` ID와 schema v1 JSON 구조를 유지하면서 아래 클립을 추가로 편집한다.

| 클립 | 허용 phase |
| --- | --- |
| `idle` | `idle` |
| `attack1`–`attack3` | `startup`, `inbetween`, `contact`, `recovery` |
| `run` | `stride` (여러 프레임 허용) |
| `turn` | `turn` |
| `jump_rise` | `rise` |
| `jump_fall` | `fall` |
| `hit` | `reaction` |
| `skill1`, `skill2` | `startup`, `contact`, `recovery` |

모든 클립에서 Duration은 0 초과 10초 이하, foot anchor는 정규화된 0~1 이미지 좌표, 프레임 순서는 목록 순서, 텍스처는 문서 폴더 아래의 안전한 상대 PNG 경로로 검증한다. 가져온 프레임의 초기 `approval_state`는 `review`다. 편집기 의견이나 승인 상태는 게임 allowlist에 반영되지 않는다.

Windows PowerShell 5.1에서 독립 실행 파일을 빌드하고 실제 EXE의 WinForms 메시지 루프에서 GUI 수용 절차를 실행한다.

```powershell
$OutputEncoding = [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)
& .\tests\editor_animation_workspace_smoke.ps1
& .\tests\editor_timeline_playback_smoke.ps1
```

두 스크립트는 화면 캡처와 JSON 산출물을 임시 디렉터리에 저장하고, 11개 클립의 내보내기/재열기, 기존 공격 4개 클립, 여러 `run/stride` 프레임, phase별 허용 범위, review 기본값, Stopwatch 기반 재생, 실측 WinForms Timer, 576px 비교 캔버스를 확인한다. `data/editor/overrides.json`의 SHA-256을 실행 전후 비교하여 GUI 편집이 게임 allowlist를 변경하지 않는지 검사한다. 자동 GUI 절차는 사람의 시각 승인이나 검수 의견을 만들지 않는다.
