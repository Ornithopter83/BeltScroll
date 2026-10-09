[CmdletBinding()]
param(
    [string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot),
    [string]$ActionsRunId = '37921763731',
    [switch]$SkipActionsQuery
)

$ErrorActionPreference = 'Stop'
$ProjectRoot = [IO.Path]::GetFullPath($ProjectRoot)
$utf8 = New-Object System.Text.UTF8Encoding($false)
[Console]::OutputEncoding = $utf8
$OutputEncoding = $utf8

function Get-RelativeEvidenceState {
    param([string[]]$Paths)
    $found = @()
    $missing = @()
    foreach ($relative in $Paths) {
        $full = Join-Path $ProjectRoot ($relative -replace '/', '\')
        if (Test-Path -LiteralPath $full) { $found += $relative } else { $missing += $relative }
    }
    return [pscustomobject]@{ Found = $found; Missing = $missing }
}

function Get-GitOutput {
    param([string[]]$Arguments)
    $result = @(& git -C $ProjectRoot @Arguments 2>&1)
    if ($LASTEXITCODE -ne 0) {
        throw "git $($Arguments -join ' ') failed: $($result -join ' ')"
    }
    return $result
}

$criteria = @(
    [pscustomobject]@{ Name = '전체화면'; Evidence = @('docs/projecthub/initial-plan.md', 'docs/review/window_runtime_gate.md', 'tests/display_num_input_window_smoke.gd'); Note = '요구 기준 출처와 Window smoke는 존재한다. 이 감사 증거만으로 사람의 통합 화면 인수를 완료하지 않는다.' },
    [pscustomobject]@{ Name = '3배 표시'; Evidence = @('docs/projecthub/initial-plan.md', 'docs/review/window_runtime_gate.md', 'tests/display_num_input_window_smoke.gd'); Note = '기준·검사 경로 존재. 실제 통합 화면 인수는 미완료다.' },
    [pscustomobject]@{ Name = 'Num1~9'; Evidence = @('docs/projecthub/initial-plan.md', 'docs/review/manual_input_acceptance_gate.md', 'tests/display_num_input_window_smoke.gd'); Note = '자동 입력 smoke와 물리 키보드 인수는 별도다.' },
    [pscustomobject]@{ Name = '앉기 제거'; Evidence = @('docs/projecthub/initial-plan.md', 'scripts/player/player_controller.gd', 'tests/player_animation_state_matrix_smoke.gd'); Note = '개정 기준은 앉기 제거다. 초기 설계의 과거 앉기 문구는 기준으로 되살리지 않는다.' },
    [pscustomobject]@{ Name = '양측 체력바'; Evidence = @('docs/projecthub/initial-plan.md', 'docs/review/combat_skill_hud_gate.md', 'tests/combat_hud_smoke.gd', 'tests/raider_healthbar_window_smoke.gd'); Note = '플레이어·상대 체력바 검증 자료 경로.' },
    [pscustomobject]@{ Name = '독립 편집기'; Evidence = @('docs/review/editor_acceptance_gate.md', 'tests/editor_executable_smoke.ps1', 'dist/BeltScrollEditor.exe'); Note = '자동 self-test 기록은 존재하나 GUI 사람 확인은 미완료다.' },
    [pscustomobject]@{ Name = '원격 릴리스 ZIP'; Evidence = @('.github/workflows/editor-package.yml', 'docs/review/editor_release_package_gate.md', 'docs/review/editor_remote_artifact_gate.md', 'tools/verify_actions_editor_artifact.ps1'); Note = '워크플로 정의/검증기는 원격 run 성공 및 ZIP 실재 증거가 아니다.' }
)

$clipRows = @(
    [pscustomobject]@{ Clip = 'idle'; Evidence = @('data/art/animation_manifest.json', 'assets/art/player/elven_fighter_reference_v8_clean_candidate_1254x1254.png') },
    [pscustomobject]@{ Clip = 'run'; Evidence = @('docs/review/m5_animation_acceptance_matrix.md', 'docs/review/player_run_cycle_gate.md', 'assets/art/player/elven_fighter_run_stride_v1_candidate_1254x1254.png') },
    [pscustomobject]@{ Clip = 'turn'; Evidence = @('docs/review/m5_animation_acceptance_matrix.md', 'docs/review/player_turn_motion_gate.md', 'assets/art/review/player_turn_motion_strip.png') },
    [pscustomobject]@{ Clip = 'jump'; Evidence = @('docs/review/m5_animation_acceptance_matrix.md', 'docs/review/player_jump_motion_gate.md', 'assets/art/review/player_jump_motion_strip.png') },
    [pscustomobject]@{ Clip = 'hit'; Evidence = @('docs/review/m5_animation_acceptance_matrix.md', 'tests/player_animation_state_matrix_smoke.gd') },
    [pscustomobject]@{ Clip = 'attack1'; Evidence = @('docs/review/m5_animation_acceptance_matrix.md', 'docs/review/player_attack1_startup_safe_gate.md', 'assets/art/player/elven_fighter_attack1_startup_v1_candidate_1254x1254.png') },
    [pscustomobject]@{ Clip = 'attack2'; Evidence = @('docs/review/m5_animation_acceptance_matrix.md', 'docs/review/player_attack2_contact_v6_gate.md', 'assets/art/player/elven_fighter_attack2_contact_v6_safe_candidate_1254x1254.png') },
    [pscustomobject]@{ Clip = 'attack3'; Evidence = @('docs/review/m5_animation_acceptance_matrix.md', 'docs/review/player_attack3_startup_gate.md', 'assets/art/player/elven_fighter_attack3_startup_v1_safe_candidate_1254x1254.png') },
    [pscustomobject]@{ Clip = 'skill1 startup/contact'; Evidence = @('docs/review/m5_animation_acceptance_matrix.md', 'docs/review/player_skill1_contact_motion_gate.md', 'assets/art/player/elven_fighter_skill1_rush_contact_v1_candidate_1254x1254.png') },
    [pscustomobject]@{ Clip = 'skill2 startup/contact'; Evidence = @('docs/review/m5_animation_acceptance_matrix.md', 'docs/review/player_skill_motion_gate.md', 'assets/art/player/elven_fighter_skill2_spin_contact_v1_candidate_1254x1254.png') },
    [pscustomobject]@{ Clip = 'Num5 skill2 v1 rotation proof'; Evidence = @('docs/projecthub/initial-plan.md', 'docs/review/player_skill_motion_gate.md', 'docs/review/player_skill1_contact_motion_gate.md') }
)

$criterionReport = foreach ($criterion in $criteria) {
    $state = Get-RelativeEvidenceState -Paths $criterion.Evidence
    [pscustomobject]@{
        Criterion = $criterion.Name
        EvidenceFound = $state.Found
        EvidenceMissing = $state.Missing
        Status = if ($state.Missing.Count -eq 0) { 'EVIDENCE_PRESENT_REVIEW_REQUIRED' } else { 'EVIDENCE_INCOMPLETE' }
        Note = $criterion.Note
    }
}

$clipReport = foreach ($row in $clipRows) {
    $state = Get-RelativeEvidenceState -Paths $row.Evidence
    [pscustomobject]@{
        Clip = $row.Clip
        EvidenceFound = $state.Found
        EvidenceMissing = $state.Missing
        Status = if ($state.Missing.Count -eq 0) { 'EVIDENCE_ONLY_NOT_CLIP_ACCEPTANCE' } else { 'MISSING_OR_INCOMPLETE_EVIDENCE' }
    }
}

$trackedExe = '.qa_logs/editor-publish-current/BeltScrollEditor.exe'
$trackedExeCheck = @(& git -C $ProjectRoot ls-files --error-unmatch -- $trackedExe 2>$null)
$isExeTracked = ($LASTEXITCODE -eq 0 -and $trackedExeCheck.Count -gt 0)
$exeStatus = @(Get-GitOutput -Arguments @('status', '--short', '--', $trackedExe))
$exeExists = Test-Path -LiteralPath (Join-Path $ProjectRoot ($trackedExe -replace '/', '\'))

$actions = [pscustomobject]@{
    RunId = $ActionsRunId
    WorkflowPath = '.github/workflows/editor-package.yml'
    Status = 'UNVERIFIED'
    Conclusion = $null
    Url = $null
    Evidence = @('docs/review/editor_remote_artifact_gate.md', 'tools/verify_actions_editor_artifact.ps1')
    Detail = '원격 Actions run 상태를 읽지 못했거나 확인할 수 없다. 워크플로 파일과 로컬 smoke만으로 성공/실패를 추정하지 않는다.'
}
$gh = Get-Command gh -ErrorAction SilentlyContinue
if ($gh -and -not $SkipActionsQuery) {
    try {
        $ghOutput = @(& gh run view $ActionsRunId --repo 'Ornithopter83/BeltScroll' --json status,conclusion,url 2>&1)
        if ($LASTEXITCODE -eq 0) {
            $run = ($ghOutput -join "`n") | ConvertFrom-Json
            $actions.Status = [string]$run.status
            $actions.Conclusion = [string]$run.conclusion
            $actions.Url = [string]$run.url
            $actions.Detail = if ($run.conclusion -eq 'failure') { '원격 Actions run 실패가 확인됐다.' } elseif ($run.conclusion -eq 'success') { '원격 Actions run 성공은 확인됐으나 최종 제품 인수가 아니다.' } else { '원격 run이 완료되지 않았거나 결론이 없다.' }
        } else {
            $actions.Detail = "gh run view 실패; 원격 Actions 판정 미검증: $($ghOutput -join ' ')"
        }
    } catch {
        $actions.Detail = "원격 Actions 조회 예외; 미검증: $($_.Exception.Message)"
    }
}

$blockers = @(
    'run v1~v4가 동일 보폭으로 기록되어 반대 보폭 인수 미수용: docs/review/player_run_v4_opposition_gate.md 및 docs/review/player_run_v3_antiphase_gate.md.',
    'Num5 v1 회전은 본편 동작으로 입증되지 않음: docs/review/player_skill1_contact_motion_gate.md 및 docs/review/player_skill_motion_gate.md.',
    'startup/jump/skill 원화 후보는 사람 승인되지 않음: docs/review/m5_art_visual_decision_gate.md, docs/review/player_jump_rise_safe_gate.md, docs/review/player_skill1_rush_safe_gate.md.',
    '신규 사람 승인 원화 0건; 후보 파일 존재, safe 게이트, 캡처 또는 smoke는 승인으로 승격하지 않음: data/art/animation_manifest.json 및 docs/review/animation_frame_registry_gate.md.',
    '실제 물리 키 입력 인수 미완료: docs/review/manual_input_acceptance_gate.md. 자동 이벤트 기록은 장치 출처를 증명하지 않음.',
    '사람이 수행하는 통합 GUI 인수 미완료: docs/review/editor_acceptance_gate.md 및 .qa_logs/qa_editor_exe_acceptance_20261009.json.',
    '최종 인수 PASS는 이 감사기가 생성하지 않는다. 자동 smoke 결과와 후보/증거 파일은 제품 인수의 대체물이 아니다.'
)
if ($actions.Conclusion -eq 'failure') { $blockers += "GitHub Actions run $ActionsRunId conclusion=failure: $($actions.Url)" }
elseif ($actions.Status -ne 'completed' -or $actions.Conclusion -ne 'success') { $blockers += "GitHub Actions run $ActionsRunId 가 검증된 completed/success가 아님: $($actions.Detail)" }
$blockers += '원격 ZIP artifact의 실제 다운로드·해시·추출 검증 보고서는 이 감사에서 생성하지 않는다. 증거 절차: tools/verify_actions_editor_artifact.ps1 및 docs/review/editor_remote_artifact_gate.md.'
if ($isExeTracked) { $blockers += "$trackedExe 가 git ls-files에 실제 추적 파일로 존재한다. 현재 git status: $(if ($exeStatus.Count) { $exeStatus -join '; ' } else { 'clean (추적 중이며 작업 트리 변경 없음)' }). Worker finalize에서 제거해야 한다." }
if (-not $isExeTracked -and $exeExists) { $blockers += "$trackedExe 는 현재 Git에 추적되지 않지만 로컬 파일은 존재한다." }

$report = [pscustomobject]@{
    Audit = 'M5D independent acceptance readiness audit'
    GeneratedAtUtc = [DateTime]::UtcNow.ToString('o')
    ProjectRoot = $ProjectRoot
    Verdict = 'BLOCKED'
    FinalPassAllowed = $false
    DesignSource = 'docs/projecthub/initial-plan.md#개정-최종-완료-기준'
    Criteria = $criterionReport
    RequiredAnimationClipReviewSlots = $clipReport
    GitChecks = [pscustomobject]@{
        TrackedQaEditorExe = $isExeTracked
        QaEditorExeExists = $exeExists
        QaEditorExeStatusPorcelain = $exeStatus
        GitEvidence = @("git ls-files --error-unmatch -- $trackedExe", "git status --short -- $trackedExe")
    }
    Actions = $actions
    Blockers = $blockers
}

$report | ConvertTo-Json -Depth 8
exit 2
