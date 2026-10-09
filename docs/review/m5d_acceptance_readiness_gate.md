# M5D 최종 인수 준비 독립 감사

## 기준과 개수

제품 필수 동작은 **10종**이다: `idle`, `run`, `turn`, `jump`, `hit`, `attack1`, `attack2`, `attack3`, `skill1`, `skill2`. 편집기 JSON의 클립은 **11개**이며 `jump`가 `jump_rise`와 `jump_fall`로 나뉜다. Num5 회전 증명은 필수 동작 수를 늘리는 별도 clip이 아니라 `skill2`의 별도 수용 조건이다.

감사기는 최종 PASS를 생성하지 않는다. 증거 파일 경로의 존재는 검토 자료가 있다는 뜻만 나타내며 원화 승인, 동작 수용 또는 제품 최종 인수를 의미하지 않는다. 기준 출처는 [개정 최종 완료 기준](../projecthub/initial-plan.md#개정-최종-완료-기준)과 [애니메이션 현황 분해표](m5_animation_acceptance_matrix.md)다.

## 실행

Windows PowerShell 5.1에서 저장소 루트 기준으로 실행한다. JSON 출력은 UTF-8이며 차단 상태 종료 코드는 `2`다.

```powershell
$OutputEncoding = [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)
Get-Content -Encoding UTF8 .\docs\review\m5d_acceptance_readiness_gate.md
& .\tools\audit_m5d_acceptance.ps1
```

기본 실행은 고정 Actions run 번호를 사용하지 않는다. GitHub CLI가 인증된 경우 GitHub의 현재 `main` SHA를 조회하고, 그 SHA를 대상으로 한 `editor-package.yml` 실행 중 최신 run을 찾는다. `LatestMain`, `Actions`, `Artifact`, `RemoteZipVerification`은 서로 독립 필드다. `-ActionsRunId`를 지정하면 해당 run을 직접 조사하지만, head SHA가 최신 main SHA와 다르면 `MatchesLatestMain`은 `false`다. `-SkipActionsQuery`는 원격 SHA와 run을 조회하지 않고 각각 미검증으로 남긴다.

원격 ZIP 검증을 별도로 마친 뒤 검증기의 `verification-report.json` 경로를 전달할 수 있다.

```powershell
& .\tools\verify_actions_editor_artifact.ps1 -OutputDirectory "$env:TEMP\BeltScrollRemoteArtifact"
& .\tools\audit_m5d_acceptance.ps1 -RemoteZipVerificationReport "$env:TEMP\BeltScrollRemoteArtifact\verification-report.json"
```

감사기는 보고서가 `github-actions-artifact` source, `PASS`, 64자리 ZIP SHA-256, run 성공·artifact 존재·다운로드·압축 해제·EXE 해시·패키지 smoke의 필수 검사를 모두 `PASS`로 기록하고 조사한 최신 run ID 및 artifact 이름과 일치할 때만 원격 ZIP을 `PASS`로 표시한다. 보고서가 가리키는 다운로드 ZIP 파일도 현재 존재하는지 확인하고 SHA-256을 다시 계산한다. 파일이 있거나 내부 status 문자열만 `PASS`인 것으로는 충분하지 않다. 보고서가 없으면 `NOT_VERIFIED`, 지정 경로가 없으면 `REPORT_MISSING`, 조건을 만족하지 못하면 `UNVERIFIED`다.

## 독립 상태 필드

| 필드 | 확인 내용 | 성공으로 인정되는 상태 |
| --- | --- | --- |
| `LatestMain` | GitHub `main` branch의 현재 commit SHA | `VERIFIED` 및 SHA 기록 |
| `Actions` | 해당 최신 SHA의 editor-package run, status/conclusion | run head SHA 일치와 `completed`/`success` 모두 충족 |
| `Artifact` | 선택된 run의 GitHub artifact metadata와 만료 여부 | `PRESENT`, 만료 안 됨 |
| `RemoteZipVerification` | 원격 artifact를 실제 내려받은 뒤 배포 ZIP의 SHA/self-test/GUI 검증 보고서 | 보고서 전체 일치, ZIP 파일 재확인 후 `PASS` |
| `GitHygieneAcceptance` | QA 편집기 EXE의 Git 추적 여부와 Git 위생 증거 | 추적 EXE 차단 해소 및 별도 위생 게이트 결과 확인 |
| `PhysicalInputAcceptance` | 실제 키보드·마우스 조작 및 검사자의 화면 관찰 기록 | 수동 절차가 `MANUAL_REVIEW_RECORDED`로 완료 |
| `ManualGuiAcceptance` | 독립 편집기 실제 GUI 인수 기록 | 사람의 GUI 인수 기록 완료 |

위 일곱 상태는 서로 대체되지 않으며 감사 JSON의 독립 필드다. SHA 일치 Actions 성공은 artifact 존재를 뜻하지 않고, artifact metadata 존재도 ZIP 다운로드·압축 해제·검증 완료를 뜻하지 않는다. 증거 PNG와 자동 smoke는 수동 물리 입력 또는 사람의 GUI 인수를 통과시키지 않는다. 모든 증거가 있어도 이 도구는 최종 `PASS`를 생성하지 않는다. GitHub 접근이 안 되거나 원격 확인을 건너뛰면 해당 필드만 `UNVERIFIED`로 남긴다.

## 제품 기준 및 현재 알려진 상태

| 항목 | 상태 | 근거와 제한 |
| --- | --- | --- |
| 전체화면 | 사람의 통합 인수 미완료 | `docs/review/window_runtime_gate.md`, `tests/display_num_input_window_smoke.gd` |
| 3배 표시 | 사람의 통합 인수 미완료 | `docs/review/window_runtime_gate.md`; 자동 표시 자료와 화면 인수는 구분 |
| Num1~9 | 실제 물리 키 입력 미검증 | `docs/review/manual_input_acceptance_gate.md` |
| 앉기 제거 | 개정 기준 적용 | `scripts/player/player_controller.gd`; 초기 문서의 과거 앉기 요구는 사용하지 않음 |
| 양측 체력바 | 구현 및 자동 검사 자료 있음 | `docs/review/combat_skill_hud_gate.md`; 통합 사람 인수는 별도 |
| 독립 편집기 | 수동 GUI 인수 미검증 | `docs/review/editor_acceptance_gate.md`, `.qa_logs/qa_editor_exe_acceptance_20261009.json` |
| Num5 skill2 v2 원화 | 원본 파일 확보, 사람 승인 및 본편 등록 전 | `assets/art/player/elven_fighter_skill2_spin_backfist_v2_candidate_1254x1254.png`; 기존 v1은 회전을 입증하지 못함 |
| 신규 승인 원화 | 0건 | 후보 파일 및 safe 산출물은 승인 기록이 아님. `data/art/animation_manifest.json`, `docs/review/animation_frame_registry_gate.md` |
| 기존 승인 프레임 | 4장: v8 idle 1장과 attack1/2/3 contact 각 1장 | manifest 및 `docs/review/animation_frame_registry_gate.md`; 신규 승인 수는 별도 0건 |
| run v1~v5 | 모두 동일 보폭 판정, 반대 보폭 및 run cycle 미수용 | `docs/review/player_run_v3_antiphase_gate.md`, `docs/review/player_run_v4_opposition_gate.md`, `docs/review/player_run_v5_antiphase_gate.md` |
| jump rise/fall 원화 | 후보 및 safe 자료 확보, 사람 승인/본편 등록 미완료 | `docs/review/player_jump_rise_safe_gate.md`, `docs/review/player_jump_fall_safe_gate.md` |
| hit 원화 | 후보 및 safe 자료 확보, 사람 승인/본편 등록 미완료 | `docs/review/player_hit_reaction_safe_gate.md`, `docs/review/player_hit_reaction_motion_gate.md` |
| Num4/Num5 스킬 원화 | 전용 원화 후보가 있어도 사람 승인/본편 등록 미완료 | `docs/review/player_skill1_contact_motion_gate.md`, `docs/review/player_skill2_spin_art_gate.md`; gameplay/절차 포즈 구현과 별개 |
| turn | idle/walk 기반 0.13초 절차 동작 구현, 전용 원화 없음 | `docs/review/player_turn_motion_gate.md`; 전용 시간 없음이라는 과거 설명은 폐기 |
| QA 편집기 EXE | Git 추적 위반 상태 | `.qa_logs/editor-publish-current/BeltScrollEditor.exe`; 감사기는 `git ls-files`와 해당 경로의 `git status --short`를 직접 확인 |
| 최신 main/Actions/artifact/원격 ZIP | 실행 시점에 각각 조회·보고 | 감사 출력의 `LatestMain`, `Actions`, `Artifact`, `RemoteZipVerification`을 따로 확인 |

## 필수 동작 10개 검토 슬롯

| # | 제품 동작 | 편집기 JSON 클립 | 검토 경로 | 제한 |
| ---: | --- | --- | --- | --- |
| 1 | idle | `idle` | `data/art/animation_manifest.json`, `assets/art/player/elven_fighter_reference_v8_clean_candidate_1254x1254.png` | 정지 원화는 프레임 시퀀스가 아니다. |
| 2 | run | `run` | `docs/review/m5_animation_acceptance_matrix.md`, `docs/review/player_run_cycle_gate.md` | v1~v5가 같은 보폭이며 사이클 인수 미완료다. |
| 3 | turn | `turn` | `docs/review/m5_animation_acceptance_matrix.md`, `docs/review/player_turn_motion_gate.md` | 좌우 flip과 별도 turn clip을 구분한다. |
| 4 | jump | `jump_rise`, `jump_fall` | `docs/review/m5_animation_acceptance_matrix.md`, `docs/review/player_jump_motion_gate.md` | 두 JSON 클립은 제품 동작 하나에 속한다. 원화 후보는 미승인이다. |
| 5 | hit | `hit` | `docs/review/m5_animation_acceptance_matrix.md`, `tests/player_animation_state_matrix_smoke.gd` | 현재 절차 변형 자료는 전용 승인 원화가 아니다. |
| 6 | attack1 | `attack1` | `docs/review/player_attack1_startup_safe_gate.md` | contact와 미승인 startup/recovery를 분리한다. |
| 7 | attack2 | `attack2` | `docs/review/player_attack2_contact_v6_gate.md` | 접촉 및 중간 후보의 승인을 별도로 본다. |
| 8 | attack3 | `attack3` | `docs/review/player_attack3_startup_gate.md` | startup/recovery 후보는 미승인이다. |
| 9 | skill1 | `skill1` | `docs/review/player_skill1_contact_motion_gate.md` | 절차 변형과 승인 전용 원화를 구분한다. |
| 10 | skill2 | `skill2` | `docs/review/player_skill_motion_gate.md`, `docs/review/player_skill2_spin_art_gate.md` | v2 원화는 확보됐으나 미승인이다. Num5 회전 증명은 이 동작의 별도 조건이다. |

### skill2의 별도 Num5 회전 조건

Num5 v1 접촉 원화와 본편 시각 입증은 회전을 입증하지 못했다. v2 원본은 확보했지만 회전축 발, 후방 회전 몸통, 백피스트, 교차 팔, 좌우 방향에서의 식별 가능성을 사람 검토 및 승인해야 한다. 이 항목은 위 10개 슬롯 수에 추가되지 않는다.

## 차단 및 판정 정책

- 신규 승인 원화는 0건이다. 후보와 비교 자료는 사람 승인을 대신하지 않는다.
- 현재 승인 원화 프레임은 v8 idle과 attack1~3 contact, 총 4장이다. 그 외 신규 승인 원화는 0건이다.
- run v1~v5는 같은 보폭 상태로 기록되어 반대 보폭 및 cycle 기준을 충족하지 못했다.
- jump rise/fall·hit·Num4/Num5 스킬 원화 후보는 존재하지만 사람 승인 및 본편 등록 전이다. turn은 0.13초 절차 동작이며 전용 turn 원화는 없다.
- 물리 입력과 수동 GUI 인수는 미검증이다.
- `.qa_logs/editor-publish-current/BeltScrollEditor.exe`가 Git 추적 중이므로 저장소 위생 위반이 남아 있다.
- 최신 main SHA, 같은 SHA의 Actions 성공, artifact 존재, 실제 원격 ZIP 다운로드 검증, Git 위생, 물리 입력 및 GUI 사람 인수를 각각 독립 필드에서 확인한다. 어느 하나의 증거도 다른 상태를 자동 PASS로 만들지 않는다.
- 감사 출력은 항상 `Verdict: BLOCKED`, `FinalPassAllowed: false`다. 자료가 전부 존재해도 이 도구가 최종 인수를 판정하지 않는다.

## HIGH 재검증 기록 (2026-10-10)

- 당시 기록은 v1~v4 비교까지다. 최신 상세 게이트에서 v5도 확인했으며 v1~v5 동일 보폭으로 미수용 상태다. 제품 10종과 JSON 11클립은 구분하고, Num5 회전은 별도 조건으로 유지한다. 기존 승인 4장 외 신규 승인 원화는 0건이다. 수동 GUI 및 물리 입력 미검증, Git 추적 EXE 상태를 유지한다.
- 저장된 원격 Actions ZIP 검증 보고서의 외부/내부 ZIP 및 EXE 해시를 재확인하고 실제 내부 배포 ZIP의 self-test와 GUI acceptance 재실행을 통과했다. 감사기의 원격 ZIP 검증 상태는 `PASS`로 독립 표시되며, 최신 원격 main SHA/Actions/artifact API 상태는 새 인증 실패로 `UNVERIFIED`다.
- 전체 smoke에서 skill Window 세 항목, spin-art headless, suite 구성 검사와 PowerShell gate들은 종료 코드와 성공 표식을 통과했다. 전체 suite는 14개 추가 recorder 행 중 실제 12개만 발견해 실패했으며 PASS를 만들지 않았다.
- `.qa_logs/editor-publish-current/BeltScrollEditor.exe`는 계속 Git 추적 중이다. 최신 원격 API 확인, 사람의 GUI 및 원화 승인, 물리 입력 인수가 끝나기 전 M5D는 `BLOCKED`다.
