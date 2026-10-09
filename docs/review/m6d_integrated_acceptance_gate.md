# M6D 통합 인수 게이트 (2026-10-10)

이 감사는 원격 SHA, 검사 대상 HEAD, Godot 자동 검증, 실제 Window 플레이, 물리 키보드, 표시, 편집기 GUI, 신규 원화 승인, 플레이 결과, 필수 문서와 Git 위생을 각각 독립 판정한다. 조건이 하나라도 미충족이면 `BLOCKED`다. 모든 증거 조건을 충족하면 `PENDING_HUMAN_APPROVAL`로 전환하지만 제품 `PASS`는 어떤 경우에도 발급하지 않는다. 사람의 최종 제품 인수는 이 보고서 바깥에서 별도로 승인해야 한다.

자동 입력은 물리 입력이 아니며, Window 캡처는 사람의 화면 확인이나 원화 승인이 아니다. 신규 승인 원화가 0장이면 항상 `BLOCKED`다. 누락 서류, 오래된 보고서/증거, 검사 커밋 불일치, 해시 불일치, 합성 입력, 손상되었거나 작은 가짜 캡처, Git 위생 실패도 계속 `BLOCKED`다.

## 실행

Windows PowerShell 5.1에서 실행한다. 스크립트와 보고서는 UTF-8이다. 차단/승인 대기 판정은 JSON을 출력하고 종료 코드 `2`를 반환한다.

```powershell
$OutputEncoding = [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)
Get-Content -Encoding UTF8 .\docs\review\m6d_integrated_acceptance_gate.md
& .\tools\audit_m6d_acceptance.ps1
```

기본 보고서 경로는 `.qa_logs/m6d_godot_automated.json`, `.qa_logs/m6d_window_playthrough.json`, `.qa_logs/m6d_manual_acceptance.json`이다. `-GodotReport`, `-WindowReport`, `-ManualReviewReport`로 경로를 지정할 수 있다. `-MaxEvidenceAgeDays` 기본값은 7일이다. `-SkipRemoteQuery`는 오프라인 스모크 전용이며 원격 SHA를 미검증으로 둔다. 감사기는 `git ls-remote origin refs/heads/main`과 `git rev-parse HEAD`만 읽는다. 저장소를 변경하는 Git 명령은 호출하지 않는다.

보고서의 `InspectedCommitSha`는 실행 시점의 로컬 HEAD다. 원격 조회 SHA와 이 SHA가 정확히 일치해야 해당 행이 `PASS_VERIFIED_MATCH`가 된다. 자동/수동 보고서에도 `targetCommitSha`가 있어야 하며 실제 검사 HEAD와 달라지면 해당 증거를 모두 거부한다. 원격 SHA 조회를 건너뛰거나 실패해도 로컬 SHA만으로 대신하지 않는다.

## 독립 인수표

| 항목 | 통과 증거 | 통과하지 않는 경우 |
|---|---|---|
| 원격 main SHA와 검사 HEAD | `git ls-remote`의 40~64자리 SHA가 현재 `git rev-parse HEAD`와 일치 | 오프라인, 조회 실패, SHA 불일치, 이전 보고서의 SHA |
| Godot 자동 검증 | 현재 HEAD 대상·7일 이내 보고서, `result=PASS`, `exitCode=0`, 이름 있는 PASS 검사 1개 이상, 실제 파일 SHA-256 manifest | 누락된 필드, 오래된 보고서/파일, 빠진 파일, SHA 불일치 |
| 실제 Window 플레이 | 현재 HEAD 대상·신선한 보고서, `headless=false`, 창 식별자, `inputMode=gameplay-events`, 상태 직접 변경/내부 결과 호출 false, 해시 일치 증거, 디코딩 가능한 1280×720 이상 PNG | `synthetic` 입력, 빈/손상/작은 PNG, 오래된 증거, 상태 주입, commit/hash 불일치 |
| 물리 키보드 Num1~9 | 보고서의 `physicalKeyboard`: `method=physical-keyboard`, 검사자·최근 관찰 시각, 9개 키 각각 PASS, 해시가 일치하는 PNG 증거 | 가상 키/자동 Window 입력, 누락 키, 오래된 기록, 존재만 하는 파일 |
| 전체화면·3배 표시 | `display`: `method=human-observed`, `fullscreen`·`three-times-scale` 각각 PASS와 사람 증거 | 자동 해상도 값이나 캡처만으로 사람 확인 주장 |
| 편집기 GUI 왕복 | `editorGuiRoundtrip`: `method=human-gui`, create/edit/save-close/reopen-verify/apply-to-game 각각 PASS와 사람 증거 | self-test 또는 자동 GUI 성공, 누락 단계 |
| 원화 승인·연속 프레임 | 현재 보고서에서 `newApproval=true`, 최근 사람 승인, 인덱스가 연속인 2장 이상, 각 `humanApproved=true`, 유효 이미지/해시 증거 | 기존 승인 재사용, 승인 0장, 합성/손상 이미지, 불연속 프레임, 자동 판정 |
| 보스전과 종료 | Window 자동 보고서의 `boss-encounter`, `boss-defeated`, `player-defeat`, `restart` 각각 PASS 및 증거 | 네 결과 중 누락/중복, 해시 불일치, 유효하지 않은 Window 플레이 |
| 필수 검수 서류 | 통합 인수, 플레이스루, 수동 입력, 편집기, 모션 후보 게이트 문서 모두 존재 | 목록의 문서 중 하나라도 없음 |
| Git 위생 | `tools/check_repository_hygiene.ps1` 종료 코드 0 및 정확한 PASS 마커 | 위생 FAIL, baseline 확인 실패, 검사기 실행 실패 |

자동/수동 JSON은 `targetCommitSha`, `generatedAtUtc`, `evidence` 파일 배열, `evidenceHashes` 배열을 포함해야 한다. `evidenceHashes`의 각 항목은 evidence에 사용한 동일한 `path`와 파일의 실제 SHA-256 hex인 `sha256`을 포함한다. 파일은 존재하고 비어 있지 않아야 하며 최대 증거 수명보다 오래되어서는 안 된다. 이미지가 사람 또는 Window 캡처 증거로 쓰이면 실제로 디코딩되는 PNG여야 하고 최소 1280×720이어야 한다. 단순히 JSON에 `PASS`를 적거나 파일 경로를 나열하는 것으로는 통과할 수 없다.

## 수동 보고서 계약

UTF-8 JSON으로 기록한다. 아래 구조에 공통 결속 필드와 해시 매니페스트를 추가한다. 각 checklist 항목은 실제 사람 관찰로 기록한다. 보고서의 작성자 자기 선언은 제품의 최종 사람 승인으로 간주하지 않는다.

```json
{
  "targetCommitSha": "현재 검사 HEAD의 전체 SHA",
  "generatedAtUtc": "2026-10-10T14:30:00Z",
  "evidence": [".qa_logs/manual/display.png"],
  "evidenceHashes": [
    { "path": ".qa_logs/manual/display.png", "sha256": "실제 파일의 64자리 SHA-256" }
  ],
  "physicalKeyboard": {
    "status": "PASS", "method": "physical-keyboard",
    "reviewer": "검사자", "observedAt": "2026-10-10T14:30:00+09:00",
    "checks": [
      { "name": "Num1", "status": "PASS", "evidence": [".qa_logs/manual/num1.png"] }
    ]
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
    "sequences": [{
      "id": "attack1-new", "decision": "approved", "newApproval": true,
      "approvedAt": "2026-10-10T14:30:00+09:00", "frames": [
        { "index": 0, "humanApproved": true, "evidence": ["assets/art/review/frame0.png"] },
        { "index": 1, "humanApproved": true, "evidence": ["assets/art/review/frame1.png"] }
      ]
    }]
  }
}
```

## 최종 상태 의미

`BLOCKED`는 독립 요구 중 하나라도 누락·실패·미검증이거나 신규 승인 원화가 0장인 상태다. 모든 요구가 충족되고 신규 원화 승인도 확인된 경우에만 `PENDING_HUMAN_APPROVAL`을 쓴다. 이 상태는 사람의 제품 인수 서명을 기다린다는 뜻이며 제품 `PASS`가 아니다. 보고서의 `FinalPassAllowed`는 항상 `false`다.

현재 저장소의 이전 M6D 자동 보고서는 commit SHA, 생성 시각, 증거 해시 매니페스트가 없어 새 계약으로는 미검증이다. 신규 원화 사람 승인도 기록되지 않았으므로 이전의 자동 Window/Godot PASS만으로 통합 승인 대기 상태로 승격하지 않는다.

## 회귀 스모크

```powershell
& .\tests\m6d_acceptance_audit_smoke.ps1
```

스모크는 오래된 자동 보고서, 잘못된 이미지 바이트, 합성 Window 입력, 위조된 사람 체크리스트와 원화 승인 주장이 각각 차단되는지 확인한다. 현재 HEAD에 결속된 자동 PASS 보고서가 있어도 사람 전용 체크와 최종 제품 PASS를 만들 수 없는지 확인한다.
