# 전체 스모크 회귀 및 후보 격리 게이트

## suite 계약

`origin/main`의 기존 64개 Godot 검사는 순서와 실행 경로를 그대로 유지한다. 독립 headless 검사 네 개를 끝에 추가해 총 68개 Godot 호출이 된다. 추가 검사 집계는 headless 12개와 Windows PowerShell 2개, 총 14개다. 새 후보 네 검사는 모두 120초로 제한한다.

| 신규 추가 검사 | 유형 | 제한 시간 | 성공 표식 |
| --- | --- | ---: | --- |
| `player_run_stride_v2_safe_smoke` | Godot headless SceneTree 기계 검사 | 120초 | `player_run_stride_v2_safe_smoke: mechanical checks passed; human visual approval remains required and main-game registration is prohibited` |
| `player_run_v3_antiphase_smoke` | Godot headless 검수 경로와 증거 파일 검사 | 120초 | `player_run_v3_antiphase_smoke: v3 capture path available; #70 finding retained; no approval or integration` |
| `player_jump_rise_safe_smoke` | Godot headless SceneTree 기계 검사 | 120초 | `player_jump_rise_safe_smoke: mechanical checks passed; airborne feet and identity require human review` |
| `player_skill1_rush_safe_smoke` | Godot headless SceneTree 기계 검사 | 120초 | `player_skill1_rush_safe_smoke: mechanical checks passed; face/clothing identity, drive-leg readability, and Num5 rotational distinction remain human review gates` |

기존 `player_animation_bank_smoke`가 승인 프레임 격리 검사를 이미 정확히 한 번 실행한다. 여기서는 빈 allowlist, 위조 승인 거부, 동일 승인 identity 재사용 거부 및 승인 외 이미지 차단 계약을 독립 PowerShell coverage gate로 확인한다. 이를 별도 중복 Godot 검사로 다시 호출하지 않는다.

## 이미지 증거와 실제 재생 검수

후보 smoke는 PNG 바이트, 크기, 알파 경계, 격리 규칙 및 캡처 도구가 남긴 이미지 파일 같은 기계 증거를 검사한다. 캡처 이미지가 존재하거나 smoke가 통과해도 사람의 시각 판단이나 실제 애니메이션 재생 검수는 완료되지 않는다. run v3 캡처 도구는 실제 Window의 post-draw 프레임을 저장하고 후보가 없는 경우 `NOT ACQUIRED` 카드를 지원한다. 선택적 v4 입력 파일이 아직 없으면 후보 coverage는 `NOT ACQUIRED` 상태로 통과하며, 발견되더라도 미승인 입력으로만 취급한다.

실제 재생 및 시각 검수는 별도의 Window 캡처와 사람 검토를 필요로 한다. 캡처 재생성 성공은 사람 승인으로 승격하지 않으며 검토 전 후보를 Player, manifest, reviewed-frame allowlist에 등록하지 않는다.

## 누락·중복·비정상 종료 판정

`tests/smoke_suite_coverage_smoke.ps1`는 기존 호출 순서와 네 신규 호출의 마지막 위치, 전체 개수, 중복, 필요한 `.gd` 파일, 실행 route, 시간제한, 성공 표식 및 실패 로그 보존을 확인한다. 추가 검사 14개의 recorder 호출 이름을 예상 목록과 대조해 빠진 호출, 중복 호출, 불일치를 거부한다. 각 recorder는 이름, 실행 유형, 새로 실행한 프로세스의 종료 코드와 누적 번호를 콘솔과 UTF-8 임시 원장에 기록한다. runner를 부를 때 `RUN_EXIT`를 비운 뒤 결과를 다시 채워 이전 검사 종료 코드가 남지 않게 한다. 성공 표시 직전 원장의 행 수, 순서, 고유 이름, 실행 유형, 종료 코드와 기대 개수 14를 검증한다. 최종 요약은 한 번만 출력하며, 요약의 `additional_checks`는 검증된 recorder 행 수와 같다. 검증이 실패하면 성공 표시 없이 실패 경로로 간다.

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

최종 성공 표식은 `[smoke] All independent smoke checks passed.`이며 suite 요약에서 `process_exit=0`, `additional_checks=14` 및 각 추가 검사별 `process_exit=0`을 확인한다.
