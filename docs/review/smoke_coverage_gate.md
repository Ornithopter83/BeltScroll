# 전체 스모크 회귀 및 후보 격리 게이트

## suite 계약

기존 Godot 호출 68개는 순서와 실행 경로를 그대로 유지한다. 그 뒤에 스킬 검증 네 개를 붙여 전체 인벤토리는 72개가 된다. 추가 항목은 실제 Window 검증 세 개와 headless 원화 파일 기계 검사 한 개다. 세 Window 검사는 각각 360초, spin-art headless 검사는 120초 제한을 사용한다. 기존 recorder 14건(headless 12건, Windows PowerShell 2건)은 그대로 유지한다. 새 네 smoke는 인벤토리·종료 코드·성공 표식으로 관리하며 원장 수에 중복 집계하지 않는다.

| 신규 추가 검사 | 유형 | 제한 시간 | 성공 표식 |
| --- | --- | ---: | --- |
| `player_run_stride_v2_safe_smoke` | Godot headless SceneTree 기계 검사 | 120초 | `player_run_stride_v2_safe_smoke: mechanical checks passed; human visual approval remains required and main-game registration is prohibited` |
| `player_run_v3_antiphase_smoke` | Godot headless 검수 경로와 증거 파일 검사 | 120초 | `player_run_v3_antiphase_smoke: v3 capture path available; #70 finding retained; no approval or integration` |
| `player_jump_rise_safe_smoke` | Godot headless SceneTree 기계 검사 | 120초 | `player_jump_rise_safe_smoke: mechanical checks passed; airborne feet and identity require human review` |
| `player_skill1_rush_safe_smoke` | Godot headless SceneTree 기계 검사 | 120초 | `player_skill1_rush_safe_smoke: mechanical checks passed; face/clothing identity, drive-leg readability, and Num5 rotational distinction remain human review gates` |
| `player_skill1_visual_telegraph_smoke` | 실제 Window 렌더링, 양방향 12 phase 프레임과 접촉/상태 확인 | 360초 | `SKILL1_WINDOW_SMOKE_PASS` |
| `player_skill2_visual_telegraph_smoke` | 실제 Window 렌더링, 양방향 12 phase/contact/cleanup 확인 | 360초 | `SKILL2_WINDOW_SMOKE_PASS` |
| `player_skill_interruption_smoke` | 본편 실제 Window에서 Raider 타격 중단 통합 검사 | 360초 | `player_skill_interruption_smoke: all checks passed` |
| `player_skill2_spin_art_smoke` | Godot headless 원화/보드 형식 기계 검사 | 120초 | `player_skill2_spin_art_smoke: mechanical checks passed; no production registration without human approval` |

기존 `player_animation_bank_smoke`가 승인 프레임 격리 검사를 이미 정확히 한 번 실행한다. 여기서는 빈 allowlist, 위조 승인 거부, 동일 승인 identity 재사용 거부 및 승인 외 이미지 차단 계약을 독립 PowerShell coverage gate로 확인한다. 이를 별도 중복 Godot 검사로 다시 호출하지 않는다.

## 이미지 증거와 실제 재생 검수

후보 smoke는 PNG 바이트, 크기, 알파 경계, 격리 규칙 및 캡처 도구가 남긴 이미지 파일 같은 기계 증거를 검사한다. `player_skill2_spin_art_smoke`가 원화 이미지나 비교 보드를 열고 형식을 확인하는 것은 파일 존재·디코딩·크기 확인이며, Num5 원화의 동작이나 시각 품질을 검증하지 않는다. 캡처 이미지가 존재하거나 smoke가 통과해도 사람의 시각 판단이나 실제 애니메이션 재생 검수는 완료되지 않는다. run v3 캡처 도구는 실제 Window의 post-draw 프레임을 저장하고 후보가 없는 경우 `NOT ACQUIRED` 카드를 지원한다. 선택적 v4 입력 파일이 아직 없으면 후보 coverage는 `NOT ACQUIRED` 상태로 통과하며, 발견되더라도 미승인 입력으로만 취급한다.

스킬 Window smoke는 이미지 파일 존재만으로 통과하지 않는다. Skill1/2 검사는 실제 Window renderer, phase 타이밍, Hitbox/contact signal, 중단/KO/cleanup 상태와 실제 post-draw frame 크기 및 비교를 확인한다. interruption smoke는 본편 Raider의 공격 경로로 Player 피격과 단계 취소를 검사한다. 이들은 자동 동작 회귀 증거이며, 캡처된 이미지의 원화 시각 승인으로 승격하지 않는다.

실제 재생 및 시각 검수는 별도의 Window 캡처와 사람 검토를 필요로 한다. 캡처 재생성 성공은 사람 승인으로 승격하지 않으며 검토 전 후보를 Player, manifest, reviewed-frame allowlist에 등록하지 않는다.

## 누락·중복·비정상 종료 판정

`tests/smoke_suite_coverage_smoke.ps1`는 기존 68개 호출의 순서 보존과 뒤에 추가된 네 skill 호출, 총 72개 인벤토리, 중복, 필요한 `.gd` 파일, 실행 route, 시간제한, 성공 표식 및 실패 로그 보존을 확인한다. 기존 추가 검사 14개(headless 12건, PowerShell 2건)의 이름·순서를 예상 목록과 대조해 빠진 호출, 중복 호출, 불일치를 거부한다. headless recorder 12개는 대상 Godot 호출 바로 다음 줄에서 실제 종료 코드를 writer에 넘긴다. 각 recorder는 이름, 실행 유형, 프로세스 종료 코드와 누적 번호를 콘솔 및 UTF-8 임시 원장에 기록한다. 원장 delimiter는 세미콜론이다. 성공 표시 직전 원장의 행 수, 순서, 고유 이름, 실행 유형, 종료 코드와 기대 개수 14를 검증한다. 최종 요약은 한 번만 출력하며, 요약의 `additional_checks`는 검증된 recorder 행 수와 같다. 검증이 실패하면 성공 표시 없이 실패 경로로 간다. skill 네 호출도 bounded runner의 종료 코드와 probe의 성공 표식을 통과해야 전체 회귀가 성공한다.

2026-10-10 재실행에서는 72개 인벤토리/route 검증, 세 실제 Window skill 검사, spin-art headless 검사와 두 PowerShell gate가 종료 코드 0 및 성공 표식으로 확인됐다. 전체 suite는 추가 recorder 원장 검증에서 기대 14행과 실제 12행이 일치하지 않아 실패했다. 따라서 이번 재실행은 회귀 PASS가 아니다. Window capture smoke의 GUI 자동 검사는 사람의 GUI 인수나 물리 입력 검증으로 승격하지 않는다.

`tests/smoke_additional_accounting_smoke.ps1`는 Windows `cmd.exe`에서 실제 batch subroutine과 bounded runner를 호출해 정상 종료, 일반 실패, timeout, PowerShell 실패를 재현한다. 각 결과의 종료 코드와 누적 번호, 유일 이름, 실행 유형을 확인하고 요약이 한 번만 출력되며 총계가 4인지 검사한다. 전체 suite에서도 이 fixture를 45초 제한으로 실행한다. fixture 기록은 suite의 14개 실제 추가 검사 원장에 포함되지 않는다.

`tests/animation_candidate_coverage_smoke.ps1`는 신규 후보 호출 네 개의 유일성, 선택적 v4 미확보 상태, 그리고 기존 승인 프레임 격리 검사를 검사한다. 이 검사는 45초 제한이며 전체 추가 검사 집계에 PowerShell 검사로 포함된다. `tests/editor_executable_parse_smoke.ps1`도 45초 제한 PowerShell 검사로 집계한다.

`tests/animation_live_review_suite_smoke.ps1`는 명시적 캡처 재생성 경로가 일반 회귀와 분리됐는지, 캡처가 실제 Window 렌더러를 요청하는지, 성공 시에도 승인 대기 상태를 유지하는지 확인한다. `tests/smoke_runner_probe.cmd`는 종료 코드가 0이 아니거나 성공 표식이 없거나 스크립트/파서/런타임 오류가 있으면 실패시킨다. timeout 및 runner 실패 로그는 검사별로 보존한다.

## 실제 Window 캡처 재생성

프로젝트 루트에서 명시적으로 실행한다.

```cmd
tools\smoke_suite.cmd --rebuild-live-review-captures
```

이 경로는 실제 Godot Window에서 attack2 timed motion strip과 플레이어 상태 행렬을 캡처하고, attack3 startup 비교판은 별도 생성 도구로 만든다. 실제 Window 캡처, headless 생성 보드, 사람이 확인한 재생 검수는 서로 다른 증거 유형이다. 어느 자동 단계도 사람의 시각 승인을 대신하지 않는다.

전체 suite 실행은 다음과 같다.

```cmd
tools\smoke_suite.cmd
```

최종 성공 표식은 `[smoke] All independent smoke checks passed.`이며 suite 요약에서 `process_exit=0`, `additional_checks=14` 및 recorder 각 항목별 `process_exit=0`을 확인한다. 전체 Godot smoke 인벤토리는 72개이며, 네 skill 추가 호출은 일반 성공 로그에서 각각의 종료 코드와 최종 표식을 확인한다.
