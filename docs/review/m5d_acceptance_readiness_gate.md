# M5D 최종 인수 준비 독립 감사

## 기준

이 감사는 [초기 설계의 2026-10-09 개정 최종 완료 기준](../projecthub/initial-plan.md)의 제품 요구를 바꾸지 않는다. 전체화면·3배·Num1~9·앉기 제거·플레이어/상대 체력바·외부 GUI 편집 흐름·애니메이션 요구를 각각 증거 위치와 함께 나열한다. 증거 파일, 후보 원화, 자동 smoke 또는 로컬 빌드는 사람의 통합 인수와 같지 않다.

11개 검토 슬롯은 기존 기준에서 이름을 열거한 동작(대기, 달리기, 방향 전환, 점프, 피격, 3종 공격, 2종 스킬)을 별도로 기록하고, Num5 skill2 v1 회전 입증을 열한 번째 독립 증거 항목으로 추적한다. 이는 새 제품 요구나 승인 애니메이션을 추가하지 않는다. 현재 매트릭스의 `run/walk` 표기는 전용 run 클립을 뜻하지 않으며, 절차 변형과 원화 클립을 구분한다.

## 실행

Windows PowerShell 5.1에서 저장소 루트 기준으로 실행한다. 스크립트는 UTF-8 JSON을 표준 출력에 기록하고, 차단 상태일 때 종료 코드 `2`를 반환한다. Git index와 작업 트리는 실제 `git ls-files` 및 `git status --short` 읽기 명령으로 점검한다. 기본 설정은 문서에 기록된 Actions run `37921763731`을 `gh`로 조회한다. 네트워크/인증/도구가 없으면 Actions 상태를 `UNVERIFIED`로 둔다.

```powershell
$OutputEncoding = [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)
Get-Content -Encoding UTF8 .\docs\review\m5d_acceptance_readiness_gate.md
& .\tools\audit_m5d_acceptance.ps1
```

다른 프로젝트 루트나 Actions run을 감사할 수 있다. 오프라인 실행에서는 `-SkipActionsQuery`를 지정하며 Actions 결과는 미검증으로 남는다. 검증 경로를 시험하는 스크립트는 `tests/m5d_acceptance_audit_smoke.ps1`이다.

## 현재 인수 항목 및 증거 경로

| 인수 기준 | 증거 경로 | 현재 증거가 뜻하는 범위 |
| --- | --- | --- |
| 전체화면 | `docs/projecthub/initial-plan.md`, `docs/review/window_runtime_gate.md`, `tests/display_num_input_window_smoke.gd` | 요구 및 자동 Window 경로. 통합 사람 인수는 별도다. |
| 3배 표시 | `docs/projecthub/initial-plan.md`, `docs/review/window_runtime_gate.md`, `tests/display_num_input_window_smoke.gd` | 요구 및 표시 검사 경로. 캡처/설정 검사는 최종 시각 인수가 아니다. |
| Num1~9 | `docs/projecthub/initial-plan.md`, `docs/review/manual_input_acceptance_gate.md`, `tests/display_num_input_window_smoke.gd` | 자동 입력 검사와 실제 물리 키 입력 검수는 분리한다. |
| 앉기 제거 | `docs/projecthub/initial-plan.md`, `scripts/player/player_controller.gd`, `tests/player_animation_state_matrix_smoke.gd` | 적용 기준은 개정 기준의 제거 요구다. 초기 역사 기록의 앉기 기준은 되살리지 않는다. |
| 양측 체력바 | `docs/projecthub/initial-plan.md`, `docs/review/combat_skill_hud_gate.md`, `tests/combat_hud_smoke.gd`, `tests/raider_healthbar_window_smoke.gd` | 플레이어와 적 HUD의 구현/자동 검사 자료. 통합 화면 검수는 별도다. |
| 독립 편집기 | `dist/BeltScrollEditor.exe`, `docs/review/editor_acceptance_gate.md`, `tests/editor_executable_smoke.ps1` | EXE/self-test 증거와 GUI 수동 확인을 구별한다. `.qa_logs/qa_editor_exe_acceptance_20261009.json`은 GUI 인수가 `blocked`였음을 기록한다. |
| 원격 릴리스 ZIP | `.github/workflows/editor-package.yml`, `docs/review/editor_release_package_gate.md`, `docs/review/editor_remote_artifact_gate.md`, `tools/verify_actions_editor_artifact.ps1` | 워크플로 정의는 성공한 원격 run·artifact 다운로드·ZIP 검증 증거를 대신하지 않는다. 실패 conclusion은 차단으로 기록한다. |

### 애니메이션 11개 검토 슬롯

| # | 클립/검토 슬롯 | 근거 경로 | 준비 상태의 제한 |
| ---: | --- | --- | --- |
| 1 | idle | `data/art/animation_manifest.json`, `assets/art/player/elven_fighter_reference_v8_clean_candidate_1254x1254.png` | 승인 idle 1장과 호흡 변형. 정지 원화는 프레임 시퀀스가 아니다. |
| 2 | run | `docs/review/m5_animation_acceptance_matrix.md`, `docs/review/player_run_cycle_gate.md`, `assets/art/player/elven_fighter_run_stride_v1_candidate_1254x1254.png` | v1~v4 동일 보폭 판정은 미수용이다. v4 반대 보폭 게이트: `docs/review/player_run_v4_opposition_gate.md`. |
| 3 | turn | `docs/review/m5_animation_acceptance_matrix.md`, `docs/review/player_turn_motion_gate.md`, `assets/art/review/player_turn_motion_strip.png` | 기존 화면 매트릭스는 좌우 flip과 별도 turn clip을 구분한다. |
| 4 | jump | `docs/review/m5_animation_acceptance_matrix.md`, `docs/review/player_jump_motion_gate.md`, `docs/review/player_jump_rise_safe_gate.md`, `assets/art/review/player_jump_motion_strip.png` | 현재 rise/fall은 절차 변형. 후보 jump 원화는 미승인이다. |
| 5 | hit | `docs/review/m5_animation_acceptance_matrix.md`, `tests/player_animation_state_matrix_smoke.gd` | 현재는 knockback/flash 절차 변형이며 전용 hit 원화 프레임 증거가 아니다. |
| 6 | attack1 | `docs/review/m5_animation_acceptance_matrix.md`, `docs/review/player_attack1_startup_safe_gate.md`, `assets/art/player/elven_fighter_attack1_startup_v1_candidate_1254x1254.png` | 승인 contact 한 장과 미승인 startup/recovery를 분리한다. |
| 7 | attack2 | `docs/review/m5_animation_acceptance_matrix.md`, `docs/review/player_attack2_contact_v6_gate.md`, `assets/art/player/elven_fighter_attack2_contact_v6_safe_candidate_1254x1254.png` | 승인 contact 한 장과 미승인 접촉/중간 후보를 분리한다. |
| 8 | attack3 | `docs/review/m5_animation_acceptance_matrix.md`, `docs/review/player_attack3_startup_gate.md`, `assets/art/player/elven_fighter_attack3_startup_v1_safe_candidate_1254x1254.png` | 승인 contact 한 장과 미승인 startup/recovery를 분리한다. |
| 9 | skill1 startup/contact | `docs/review/m5_animation_acceptance_matrix.md`, `docs/review/player_skill1_contact_motion_gate.md`, `assets/art/player/elven_fighter_skill1_rush_contact_v1_candidate_1254x1254.png` | 게임 상태/절차 변형과 승인 전용 원화가 다르다. 후보 원화는 미승인이다. |
| 10 | skill2 startup/contact | `docs/review/m5_animation_acceptance_matrix.md`, `docs/review/player_skill_motion_gate.md`, `assets/art/player/elven_fighter_skill2_spin_contact_v1_candidate_1254x1254.png` | Num5 v1 몸통 회전의 본편 시각 입증이 없다. |
| 11 | Num5 skill2 v1 회전 입증 | `docs/projecthub/initial-plan.md`, `docs/review/player_skill_motion_gate.md`, `docs/review/player_skill1_contact_motion_gate.md` | skill2 애니메이션의 회전 동작 증거를 별도로 추적한다. 현재 본편 회전은 입증되지 않았다. 별도 승인 clip 요구를 추가하지 않는다. |

애니메이션 기준 원문은 `docs/projecthub/initial-plan.md` 및 현황 분해표 `docs/review/m5_animation_acceptance_matrix.md`다. 감사 표의 후보 파일 존재는 승인 기록이 아니다. 사람 승인 상태는 manifest 및 [프레임 레지스트리 게이트](animation_frame_registry_gate.md)를 따른다.

## 현재 차단 항목

- run v1~v4 동일 보폭은 미수용이다. 증거: `docs/review/player_run_v4_opposition_gate.md`, `docs/review/player_run_v3_antiphase_gate.md`.
- Num5 v1 회전은 본편 동작으로 입증되지 않았다. 증거: `docs/review/player_skill1_contact_motion_gate.md`, `docs/review/player_skill_motion_gate.md`.
- startup, jump, skill 원화 후보는 승인되지 않았다. 증거: `docs/review/m5_art_visual_decision_gate.md`, `docs/review/player_jump_rise_safe_gate.md`, `docs/review/player_skill1_rush_safe_gate.md`.
- 신규 승인 원화는 0건이다. 후보·safe 산출·자동 smoke는 승인 상태를 만들지 않는다. 증거: `data/art/animation_manifest.json`, `docs/review/animation_frame_registry_gate.md`.
- 실제 물리 키보드/마우스 입력 인수는 미완료다. 이벤트 로그만으로 장치 출처를 증명할 수 없다. 증거: `docs/review/manual_input_acceptance_gate.md`.
- 사람이 확인하는 통합 GUI 인수는 미완료다. GUI 승인 결과 JSON도 현재 `blocked`다. 증거: `docs/review/editor_acceptance_gate.md`, `.qa_logs/qa_editor_exe_acceptance_20261009.json`.
- Actions run이 실패하거나 `completed/success`가 아니면 차단이다. 상태 조회 불가도 성공으로 간주하지 않는다. 원격 artifact와 release ZIP은 `tools/verify_actions_editor_artifact.ps1`로 실제 다운로드/해시/self-test/GUI 결과를 확인해야 한다. 이 감사는 ZIP을 직접 받거나 검증 보고서를 만들지 않는다.
- `.qa_logs/editor-publish-current/BeltScrollEditor.exe`는 현재 인덱스에 추적된 산출물이다. 감사 스크립트는 파일 존재뿐 아니라 `git ls-files --error-unmatch`와 해당 경로의 `git status --short`를 확인한다. 현재 문서 기록에서도 Worker finalize가 인덱스 제거를 수행해야 하는 상태다. 이 작업은 Git 변경 명령을 실행하지 않는다.

## 판정 정책

감사 출력은 증거 존재와 누락, 원격 Actions 상태, 실제 Git 추적 상태 및 차단 사유를 보여준다. 결과 `BLOCKED`와 종료 코드 `2`는 현재 인수 준비가 완료되지 않았다는 뜻이다. 이 스크립트에는 자동 `PASS` 경로가 없다. 설계 기준을 수정하지 않고 모든 차단 해소와 별도 사람 인수 후에만 기존 M5D 최종 완료 기준으로 최종 판정한다.
