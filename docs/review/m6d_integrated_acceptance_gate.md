# M6D 통합 인수 게이트 (2026-10-10)

이 표는 M6D 요구 6개 항목을 실행·사람 검토·저장소 상태까지 통합해 감사한다. 행의 상태는 서로 독립이다. 자동 입력, Window 캡처, Godot smoke 또는 편집기 self-test는 물리 키 입력, 화면의 사람 확인, GUI 왕복 또는 원화 승인을 대신하지 않는다. 신규 원화 사람 승인 수가 0장이거나 필수 증거가 빠지면 최종 결과는 `BLOCKED`다. 감사기는 어떤 증거가 있더라도 최종 `PASS`를 만들지 않는다.

## 실행

Windows PowerShell 5.1에서 UTF-8 출력으로 실행한다. 차단 결과는 JSON과 종료 코드 `2`로 보고한다.

```powershell
$OutputEncoding = [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)
Get-Content -Encoding UTF8 .\docs\review\m6d_integrated_acceptance_gate.md
& .\tools\audit_m6d_acceptance.ps1
```

기본 경로는 `.qa_logs/m6d_godot_automated.json`, `.qa_logs/m6d_window_playthrough.json`, `.qa_logs/m6d_manual_acceptance.json`이다. 경로는 실행 인자로 바꿀 수 있다. `-SkipRemoteQuery`는 스모크/오프라인 실행용으로 원격 SHA를 `UNVERIFIED`에 둔다. 원격 확인은 `git ls-remote origin refs/heads/main` 읽기 전용 조회이며 fetch/pull은 하지 않는다. Git 위생은 기존 `tools/check_repository_hygiene.ps1`를 `origin/main` 기준으로 호출한다.

## 독립 인수표

| 항목 | 증거와 통과 조건 | 자동으로 대체할 수 없는 항목 |
|---|---|---|
| 원격 main SHA | `RemoteMain.Status=VERIFIED`, 40~64자리 SHA. `git ls-remote` 결과 | 로컬 HEAD 또는 오래된 문서의 SHA로 원격 상태를 추정하지 않는다. |
| Godot 자동 검증 | Godot JSON 보고서의 `result=PASS`, `exitCode=0`, PASS 검사 1개 이상 및 존재하는 `evidence` 로그 파일 | 자동 통과는 사람 인수에 영향을 주지 않는다. |
| 실제 Window | Window 보고서 `headless=false`, `windowTitle`, PASS 및 존재하는 `evidence` 파일 | 캡처 파일 자체는 화면·입력 수동 승인이 아니다. |
| 물리 키보드 Num1~9 | 사람 보고서의 `physicalKeyboard`: `method=physical-keyboard`, 검사자, 시각, Num1~Num9 각 PASS 및 각 증거 파일 | 입력 주입·가상 키 이벤트·자동 Window 테스트는 통과가 아니다. |
| 전체화면·3배 표시 | `display`: `method=human-observed`, 두 체크 `fullscreen`, `three-times-scale` PASS, 검사자/시각/파일 | 자동 해상도 수치나 캡처만으로 사람 확인을 통과시키지 않는다. |
| 편집기 GUI 왕복 | `editorGuiRoundtrip`: `method=human-gui`, create/edit/save-close/reopen-verify/apply-to-game 모두 PASS 및 증거 | self-test, 자동 GUI 조작, 편집기 캡처만으로 게임 재적용 확인을 대체하지 않는다. |
| 원화 승인·연속 프레임 | `artReview.method=human-visual-review`, 검사자/시각, 승인된 시퀀스의 연속 인덱스 2장 이상, 각 프레임 `humanApproved=true`와 실제 파일 | 후보 파일, 자동 비교, 프레임 캡처는 사람 승인 수로 세지 않는다. 승인 프레임이 0장이면 무조건 BLOCKED다. |
| 보스전과 종료 | Window 플레이 보고서에서 `inputMode=gameplay-events`, 상태 직접 변경·내부 결과 함수 호출 false, boss encounter/defeated/player defeat/restart PASS | 이벤트 주입 플레이는 자동 게임플레이 증거일 뿐 물리 키보드 증거는 아니다. |
| Git 위생 | 위생 검사기 종료 코드 0 및 정확한 PASS 마커 | 파일이 로컬에 없거나 작업 트리가 깨끗한 사실만으로는 baseline/index 위생을 통과하지 않는다. |

M6D 업무의 6개 사용자 요구는 아래처럼 인수 항목에 대응한다. ① 표시/창: 실제 Window, 전체화면·3배, ② 조작: 물리 Num1~9, ③ 별도 편집기: GUI 왕복, ④ 원화: 사람 승인·연속 프레임, ⑤ 플레이: 보스전·승리/패배·재시작, ⑥ 배포/저장소: 원격 SHA·Godot 자동 검증·Git 위생. 이 대응은 인수표의 독립 열을 합치지 않는다.

자동 증거 보고서는 UTF-8 JSON이다. Godot 보고서는 `{ "result":"PASS", "exitCode":0, "checks":[{"name":"...","status":"PASS"}], "evidence":[".qa_logs/m6d/godot.log"] }` 형식이다. Window 보고서는 `{ "result":"PASS", "headless":false, "windowTitle":"BeltScroll", "evidence":[".qa_logs/m6d/window.png"], "inputMode":"gameplay-events", "directStateMutation":false, "internalOutcomeCalls":false, "outcomes":[...] }` 형식이다. `outcomes`는 `boss-encounter`, `boss-defeated`, `player-defeat`, `restart` 각각의 `status=PASS`와 존재하는 `evidence` 파일을 요구한다. 이는 자동 실행 결과이며 물리 입력이나 사람의 화면/원화 승인 기록을 채우지 않는다.

## 수동 보고서 계약

UTF-8 JSON으로 보관한다. 검사자가 직접 관찰한 경우에만 `status=PASS`를 쓴다. 각 체크의 `evidence`는 실제 파일 경로 배열이며, 모든 파일이 존재해야 해당 행을 PASS로 계산한다. 자동 입력은 `method=physical-keyboard`에 적합하지 않다.

```json
{
  "physicalKeyboard": {
    "status": "PASS", "method": "physical-keyboard",
    "reviewer": "검사자", "observedAt": "2026-10-10T14:30:00+09:00",
    "checks": [ { "name": "Num1", "status": "PASS", "evidence": [".qa_logs/manual/num1.png"] } ]
  },
  "display": {
    "status": "PASS", "method": "human-observed", "reviewer": "검사자", "observedAt": "...",
    "checks": [
      { "name": "fullscreen", "status": "PASS", "evidence": [".qa_logs/manual/display.png"] },
      { "name": "three-times-scale", "status": "PASS", "evidence": [".qa_logs/manual/display.png"] }
    ]
  },
  "editorGuiRoundtrip": {
    "status": "PASS", "method": "human-gui", "reviewer": "검사자", "observedAt": "...",
    "checks": [
      { "name": "create", "status": "PASS", "evidence": [".qa_logs/manual/editor.png"] },
      { "name": "edit", "status": "PASS", "evidence": [".qa_logs/manual/editor.png"] },
      { "name": "save-close", "status": "PASS", "evidence": [".qa_logs/manual/editor.png"] },
      { "name": "reopen-verify", "status": "PASS", "evidence": [".qa_logs/manual/editor.png"] },
      { "name": "apply-to-game", "status": "PASS", "evidence": [".qa_logs/manual/editor-game.png"] }
    ]
  },
  "artReview": {
    "method": "human-visual-review", "reviewer": "검사자", "reviewedAt": "...",
    "sequences": [ { "id": "attack1-new", "decision": "approved", "frames": [
      { "index": 0, "humanApproved": true, "evidence": ["assets/art/review/frame0.png"] },
      { "index": 1, "humanApproved": true, "evidence": ["assets/art/review/frame1.png"] }
    ] } ]
  }
}
```

## 현재 판정

2026-10-10 HIGH 재검수 보고서는 `.qa_logs/m6d_acceptance_high_recheck.json`에 저장했다. 최신 판정은 원격 main SHA `UNVERIFIED`(GitHub 연결 실패), Godot 자동 검증 `PASS`, 실제 Window `PASS_AUTOMATED_WINDOW`, 보스전·종료 `PASS_AUTOMATED_PLAYTHROUGH`, 물리 키보드·전체화면/3배·편집기 GUI·원화 사람 승인 `NOT_VERIFIED`, Git 위생 `FAIL`이다. 신규 사람 승인 원화는 0장이며 최종 결과는 `BLOCKED`다. Window 플레이스루 로그와 캡처는 자동 입력 이벤트 증거다. 수동 입력, GUI 왕복, 사람의 시각 승인 상태는 채우지 않았다. 기존 승인 프레임 manifest는 이번 요구의 신규 승인 수에 포함하지 않는다.

보고서가 없으면 해당 행은 `NOT_VERIFIED` 또는 `UNVERIFIED`로 계산한다. Git 위생 결과는 프로젝트 상태에 따라 `FAIL`, `UNVERIFIED`, `PASS`를 독립 계산한다.

스모크 검증:

```powershell
& .\tests\m6d_acceptance_audit_smoke.ps1
```
