[CmdletBinding()]
param(
    [string]$ProjectRoot = '',
    [string]$ActionsRunId = '',
    [string]$RemoteZipVerificationReport = '',
    [switch]$SkipActionsQuery
)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($ProjectRoot)) { $ProjectRoot = Split-Path -Parent $PSScriptRoot }
$ProjectRoot = [IO.Path]::GetFullPath($ProjectRoot)
$utf8 = New-Object System.Text.UTF8Encoding($false)
[Console]::OutputEncoding = $utf8
$OutputEncoding = $utf8
$repository = 'Ornithopter83/BeltScroll'
$workflow = 'editor-package.yml'
$artifactPrefix = 'BeltScrollEditor-win-x64-'

function Get-RelativeEvidenceState {
    param([string[]]$Paths)
    $found = @()
    $missing = @()
    foreach ($relative in $Paths) {
        $full = Join-Path $ProjectRoot ($relative -replace '/', '\')
        if (Test-Path -LiteralPath $full) { $found += $relative } else { $missing += $relative }
    }
    [pscustomobject]@{ Found = $found; Missing = $missing }
}

function Invoke-GhJson {
    param([string[]]$Arguments)
    $output = @(& gh @Arguments 2>&1)
    if ($LASTEXITCODE -ne 0) { throw ($output -join ' ') }
    (($output -join "`n") | ConvertFrom-Json)
}

function Get-GitOutput {
    param([string[]]$Arguments)
    $result = @(& git -C $ProjectRoot @Arguments 2>&1)
    if ($LASTEXITCODE -ne 0) { throw "git $($Arguments -join ' ') failed: $($result -join ' ')" }
    $result
}

$criteria = @(
    [pscustomobject]@{ Name = '전체화면'; Evidence = @('docs/projecthub/initial-plan.md', 'docs/review/window_runtime_gate.md', 'tests/display_num_input_window_smoke.gd'); Note = '요구 기준과 자동 Window 경로가 있다. 사람의 통합 화면 인수는 별도다.' },
    [pscustomobject]@{ Name = '3배 표시'; Evidence = @('docs/projecthub/initial-plan.md', 'docs/review/window_runtime_gate.md', 'tests/display_num_input_window_smoke.gd'); Note = '기준 및 자동 검사 경로가 있다. 실제 통합 화면 인수는 미완료다.' },
    [pscustomobject]@{ Name = 'Num1~9'; Evidence = @('docs/projecthub/initial-plan.md', 'docs/review/manual_input_acceptance_gate.md', 'tests/display_num_input_window_smoke.gd'); Note = '자동 입력 smoke와 물리 키보드 인수는 별도다.' },
    [pscustomobject]@{ Name = '앉기 제거'; Evidence = @('docs/projecthub/initial-plan.md', 'scripts/player/player_controller.gd', 'tests/player_animation_state_matrix_smoke.gd'); Note = '개정 기준은 앉기 제거다. 초기 설계의 과거 앉기 문구는 기준으로 되살리지 않는다.' },
    [pscustomobject]@{ Name = '양측 체력바'; Evidence = @('docs/projecthub/initial-plan.md', 'docs/review/combat_skill_hud_gate.md', 'tests/combat_hud_smoke.gd', 'tests/raider_healthbar_window_smoke.gd'); Note = '플레이어·상대 체력바의 구현 및 자동 검사 자료 경로다.' },
    [pscustomobject]@{ Name = '독립 편집기'; Evidence = @('docs/review/editor_acceptance_gate.md', 'tests/editor_executable_smoke.ps1', 'dist/BeltScrollEditor.exe'); Note = '자동 self-test 자료는 있지만 GUI 사람 확인은 미완료다.' },
    [pscustomobject]@{ Name = '원격 릴리스 ZIP'; Evidence = @('.github/workflows/editor-package.yml', 'docs/review/editor_release_package_gate.md', 'docs/review/editor_remote_artifact_gate.md', 'tools/verify_actions_editor_artifact.ps1'); Note = '워크플로 정의는 원격 run·artifact·ZIP 검증 완료의 증거가 아니다.' }
)

# 제품 동작은 10종이다. 편집기 JSON은 jump를 rise/fall 두 클립으로 나누어 11개다.
$clipRows = @(
    [pscustomobject]@{ Clip = 'idle'; EditorClips = @('idle'); Evidence = @('data/art/animation_manifest.json', 'assets/art/player/elven_fighter_reference_v8_clean_candidate_1254x1254.png') },
    [pscustomobject]@{ Clip = 'run'; EditorClips = @('run'); Evidence = @('docs/review/m5_animation_acceptance_matrix.md', 'docs/review/player_run_cycle_gate.md', 'assets/art/player/elven_fighter_run_stride_v1_candidate_1254x1254.png') },
    [pscustomobject]@{ Clip = 'turn'; EditorClips = @('turn'); Evidence = @('docs/review/m5_animation_acceptance_matrix.md', 'docs/review/player_turn_motion_gate.md', 'assets/art/review/player_turn_motion_strip.png') },
    [pscustomobject]@{ Clip = 'jump'; EditorClips = @('jump_rise', 'jump_fall'); Evidence = @('docs/review/m5_animation_acceptance_matrix.md', 'docs/review/player_jump_motion_gate.md', 'assets/art/review/player_jump_motion_strip.png') },
    [pscustomobject]@{ Clip = 'hit'; EditorClips = @('hit'); Evidence = @('docs/review/m5_animation_acceptance_matrix.md', 'tests/player_animation_state_matrix_smoke.gd') },
    [pscustomobject]@{ Clip = 'attack1'; EditorClips = @('attack1'); Evidence = @('docs/review/m5_animation_acceptance_matrix.md', 'docs/review/player_attack1_startup_safe_gate.md', 'assets/art/player/elven_fighter_attack1_startup_v1_candidate_1254x1254.png') },
    [pscustomobject]@{ Clip = 'attack2'; EditorClips = @('attack2'); Evidence = @('docs/review/m5_animation_acceptance_matrix.md', 'docs/review/player_attack2_contact_v6_gate.md', 'assets/art/player/elven_fighter_attack2_contact_v6_safe_candidate_1254x1254.png') },
    [pscustomobject]@{ Clip = 'attack3'; EditorClips = @('attack3'); Evidence = @('docs/review/m5_animation_acceptance_matrix.md', 'docs/review/player_attack3_startup_gate.md', 'assets/art/player/elven_fighter_attack3_startup_v1_safe_candidate_1254x1254.png') },
    [pscustomobject]@{ Clip = 'skill1'; EditorClips = @('skill1'); Evidence = @('docs/review/m5_animation_acceptance_matrix.md', 'docs/review/player_skill1_contact_motion_gate.md', 'assets/art/player/elven_fighter_skill1_rush_contact_v1_candidate_1254x1254.png') },
    [pscustomobject]@{ Clip = 'skill2'; EditorClips = @('skill2'); Evidence = @('docs/review/m5_animation_acceptance_matrix.md', 'docs/review/player_skill_motion_gate.md', 'assets/art/player/elven_fighter_skill2_spin_contact_v1_candidate_1254x1254.png', 'assets/art/player/elven_fighter_skill2_spin_backfist_v2_candidate_1254x1254.png') }
)
$editorJsonClips = @('idle', 'run', 'turn', 'jump_rise', 'jump_fall', 'hit', 'attack1', 'attack2', 'attack3', 'skill1', 'skill2')

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
        EditorClips = $row.EditorClips
        EvidenceFound = $state.Found
        EvidenceMissing = $state.Missing
        Status = if ($state.Missing.Count -eq 0) { 'EVIDENCE_ONLY_NOT_CLIP_ACCEPTANCE' } else { 'MISSING_OR_INCOMPLETE_EVIDENCE' }
    }
}

$v2Path = 'assets/art/player/elven_fighter_skill2_spin_backfist_v2_candidate_1254x1254.png'
$v2Exists = Test-Path -LiteralPath (Join-Path $ProjectRoot ($v2Path -replace '/', '\')) -PathType Leaf
$runCandidatePaths = @(
    'assets/art/player/elven_fighter_run_stride_v1_candidate_1254x1254.png',
    'assets/art/player/elven_fighter_run_stride_v2_opposite_candidate_1254x1254.png',
    'assets/art/player/elven_fighter_run_stride_v3_left_lead_candidate_1254x1254.png',
    'assets/art/player/elven_fighter_run_stride_v4_opposite_contact_candidate_1254x1254.png',
    'assets/art/player/elven_fighter_run_stride_v5_far_leg_forward_candidate_1254x1254.png'
)
$jumpHitCandidatePaths = @(
    'assets/art/player/elven_fighter_jump_rise_v1_candidate_1254x1254.png',
    'assets/art/player/elven_fighter_jump_fall_v1_candidate_1254x1254.png',
    'assets/art/player/elven_fighter_hit_reaction_v1_candidate_1254x1254.png'
)
$skillCandidatePaths = @(
    'assets/art/player/elven_fighter_skill1_rush_contact_v1_candidate_1254x1254.png',
    'assets/art/player/elven_fighter_skill2_spin_contact_v1_candidate_1254x1254.png',
    'assets/art/player/elven_fighter_skill2_spin_backfist_v2_candidate_1254x1254.png'
)
$turnOriginalPath = 'assets/art/player/elven_fighter_turn_rear_mid_v1_candidate_1254x1254.png'
$turnSafePath = 'assets/art/player/elven_fighter_turn_rear_mid_v1_safe_candidate_1254x1254.png'
$turnOriginalFullPath = Join-Path $ProjectRoot ($turnOriginalPath -replace '/', '\')
$turnSafeFullPath = Join-Path $ProjectRoot ($turnSafePath -replace '/', '\')
$turnOriginalExists = Test-Path -LiteralPath $turnOriginalFullPath -PathType Leaf
$turnSafeExists = Test-Path -LiteralPath $turnSafeFullPath -PathType Leaf
$turnOriginalHash = $null
$turnOriginalBytes = $null
if ($turnOriginalExists) {
    $turnOriginalHash = (Get-FileHash -LiteralPath $turnOriginalFullPath -Algorithm SHA256).Hash.ToLowerInvariant()
    $turnOriginalBytes = (Get-Item -LiteralPath $turnOriginalFullPath).Length
}
$manifestPath = Join-Path $ProjectRoot 'data/art/animation_manifest.json'
$manifestApprovedFrames = @()
if (Test-Path -LiteralPath $manifestPath -PathType Leaf) {
    try {
        $manifest = Get-Content -Encoding UTF8 -Raw -LiteralPath $manifestPath | ConvertFrom-Json
        foreach ($clip in @($manifest.clips)) {
            foreach ($frame in @($clip.frames)) {
                if ($frame.approval_state -eq 'approved' -and -not [string]::IsNullOrWhiteSpace([string]$frame.texture)) {
                    $manifestApprovedFrames += [pscustomobject]@{ Clip = [string]$clip.id; Texture = [string]$frame.texture; Phase = [string]$frame.phase }
                }
            }
        }
    } catch { $manifestApprovedFrames = @() }
}
$artReadiness = [pscustomobject]@{
    ExistingApprovedFrames = [pscustomobject]@{
        Count = $manifestApprovedFrames.Count
        Frames = $manifestApprovedFrames
        Meaning = '현재 manifest에서 approved로 표시된 기존 프레임 목록이다. 이 감사 실행으로 새 승인을 만들지 않는다.'
    }
    Skill2V2OriginalArt = [pscustomobject]@{
        Status = if ($v2Exists) { 'SECURED_UNAPPROVED' } else { 'MISSING' }
        Path = $v2Path
        Approved = $false
        Meaning = '원화 파일 확보와 사람 승인 및 본편 등록은 서로 다른 상태다.'
    }
    RunV1ToV5SameStride = [pscustomobject]@{
        Status = 'SAME_STRIDE_NOT_ACCEPTED'
        CandidateFiles = $runCandidatePaths
        CandidateFilesPresent = @($runCandidatePaths | Where-Object { Test-Path -LiteralPath (Join-Path $ProjectRoot ($_ -replace '/', '\')) -PathType Leaf })
        Evidence = @('docs/review/player_run_v3_antiphase_gate.md', 'docs/review/player_run_v4_opposition_gate.md', 'docs/review/player_run_v5_antiphase_gate.md')
        Meaning = '검수 기록의 v1~v5는 모두 같은 보폭으로 판정되어 반대 보폭 및 run cycle로 수용되지 않았다.'
    }
    JumpRiseFallAndHitArt = [pscustomobject]@{
        Status = 'CANDIDATES_UNAPPROVED'
        CandidateFiles = $jumpHitCandidatePaths
        CandidateFilesPresent = @($jumpHitCandidatePaths | Where-Object { Test-Path -LiteralPath (Join-Path $ProjectRoot ($_ -replace '/', '\')) -PathType Leaf })
        Meaning = 'jump rise/fall 및 hit 원화 후보와 safe 자료가 있어도 승인·본편 등록 상태는 아니다.'
    }
    Num4Num5DedicatedArt = [pscustomobject]@{
        Status = 'CANDIDATES_UNAPPROVED'
        DedicatedArtApproved = $false
        CandidateFiles = $skillCandidatePaths
        CandidateFilesPresent = @($skillCandidatePaths | Where-Object { Test-Path -LiteralPath (Join-Path $ProjectRoot ($_ -replace '/', '\')) -PathType Leaf })
        Meaning = 'Num4/Num5 gameplay와 절차 포즈는 구현됐지만 전용 스킬 원화 후보는 사람 승인 및 본편 등록 전이다.'
    }
    TurnProceduralDurationSeconds = 0.13
    TurnStatus = 'PROCEDURAL_IMPLEMENTED_DRAWING_UNAPPROVED'
    TurnCandidateArt = [pscustomobject]@{
        Status = if ($turnOriginalExists) { 'SECURED_UNAPPROVED_KEYPOSE_DEFERRED' } else { 'ORIGINAL_NOT_AVAILABLE' }
        OriginalPath = $turnOriginalPath
        OriginalPresent = $turnOriginalExists
        OriginalSha256 = $turnOriginalHash
        OriginalBytes = $turnOriginalBytes
        SafeCandidatePath = $turnSafePath
        SafeCandidatePresent = $turnSafeExists
        Approved = $false
        PromotedToRuntime = $false
        Evidence = @('docs/review/player_turn_mid_art_gate.md', 'docs/review/player_turn_candidate_motion_gate.md', 'assets/art/review/player_turn_mid_comparison.png', 'assets/art/review/player_turn_candidate_window.png')
        Meaning = if ($turnOriginalExists) { '원본과 safe 후보는 존재하나 보폭이 달리기 자세로 읽혀 turn 키포즈 수용은 보류다. 사람 승인 전 본편·manifest·allowlist에 등록하지 않는다.' } else { '전용 원본이 없어 후보를 생성하거나 승인 상태로 취급하지 않는다.' }
    }
    NewHumanApprovedArtCount = 0
}

$trackedExe = '.qa_logs/editor-publish-current/BeltScrollEditor.exe'
$trackedExeCheck = @(& git -C $ProjectRoot ls-files --error-unmatch -- $trackedExe 2>$null)
$isExeTracked = ($LASTEXITCODE -eq 0 -and $trackedExeCheck.Count -gt 0)
$exeStatus = @(Get-GitOutput -Arguments @('status', '--short', '--', $trackedExe))
$exeExists = Test-Path -LiteralPath (Join-Path $ProjectRoot ($trackedExe -replace '/', '\')) -PathType Leaf

# Query the current main head and its workflow run independently. An explicitly supplied run ID
# is inspected as requested, but is never represented as the latest main run unless SHAs match.
$latestMain = [pscustomobject]@{ Status = 'UNVERIFIED'; Sha = $null; Url = $null; Detail = '원격 main SHA를 읽지 않았다.' }
$actions = [pscustomobject]@{
    RunId = $null; HeadSha = $null; MatchesLatestMain = $false
    Status = 'UNVERIFIED'; Conclusion = $null; Url = $null
    Detail = '최신 main SHA와 연결된 Actions run을 확인하지 않았다.'
}
$artifact = [pscustomobject]@{
    Status = 'UNVERIFIED'; Name = $null; Exists = $null; Expired = $null
    RunId = $null; Detail = 'Actions artifact 목록을 확인하지 않았다.'
}
$gh = Get-Command gh -ErrorAction SilentlyContinue
if ($gh -and -not $SkipActionsQuery) {
    try {
        $commit = Invoke-GhJson -Arguments @('api', "repos/$repository/commits/main")
        $latestMain.Sha = [string]$commit.sha
        $latestMain.Url = [string]$commit.html_url
        $latestMain.Status = 'VERIFIED'
        $latestMain.Detail = 'GitHub main branch의 현재 commit SHA를 조회했다.'
    } catch { $latestMain.Detail = "GitHub main SHA 조회 미검증: $($_.Exception.Message)" }

    if ($latestMain.Sha) {
        try {
            if (-not [string]::IsNullOrWhiteSpace($ActionsRunId)) {
                $run = Invoke-GhJson -Arguments @('api', "repos/$repository/actions/runs/$ActionsRunId")
            } else {
                $runs = Invoke-GhJson -Arguments @('api', "repos/$repository/actions/workflows/$workflow/runs?branch=main&head_sha=$($latestMain.Sha)&per_page=100")
                $matchingRuns = @($runs.workflow_runs | Sort-Object created_at -Descending)
                if ($matchingRuns.Count -eq 0) { throw '현재 main SHA와 일치하는 editor-package workflow run을 찾지 못했다.' }
                $run = $matchingRuns[0]
            }
            $actions.RunId = [string]$run.id
            $actions.HeadSha = [string]$run.head_sha
            $actions.MatchesLatestMain = ($actions.HeadSha -eq $latestMain.Sha)
            $actions.Status = [string]$run.status
            $actions.Conclusion = [string]$run.conclusion
            $actions.Url = [string]$run.html_url
            $actions.Detail = if ($actions.MatchesLatestMain) { 'run의 head SHA가 조회한 최신 main SHA와 일치한다.' } else { '조회 run의 head SHA가 최신 main SHA와 달라 최신 검증으로 볼 수 없다.' }
        } catch {
            $actions.Detail = "최신 main Actions 조회 미검증: $($_.Exception.Message)"
        }
        if ($actions.RunId) {
            try {
                $artifactList = Invoke-GhJson -Arguments @('api', "repos/$repository/actions/runs/$($run.id)/artifacts")
                $matchingArtifacts = @($artifactList.artifacts | Where-Object { $_.name -like "$artifactPrefix*" })
                if ($matchingArtifacts.Count -eq 1) {
                    $artifact.Status = if ($matchingArtifacts[0].expired) { 'EXPIRED' } else { 'PRESENT' }
                    $artifact.Name = [string]$matchingArtifacts[0].name
                    $artifact.Exists = $true
                    $artifact.Expired = [bool]$matchingArtifacts[0].expired
                    $artifact.RunId = [string]$run.id
                    $artifact.Detail = '해당 run의 artifact metadata에서 편집기 패키지 항목을 확인했다.'
                } elseif ($matchingArtifacts.Count -gt 1) {
                    $artifact.Status = 'AMBIGUOUS'
                    $artifact.Exists = $true
                    $artifact.RunId = [string]$run.id
                    $artifact.Detail = "편집기 패키지 artifact가 여러 개다: $($matchingArtifacts.Count)"
                } else {
                    $artifact.Status = 'MISSING'
                    $artifact.Exists = $false
                    $artifact.RunId = [string]$run.id
                    $artifact.Detail = '해당 run의 artifact metadata에 편집기 패키지가 없다.'
                }
            } catch {
                $artifact.Detail = "artifact metadata 조회 미검증: $($_.Exception.Message)"
            }
        }
    }
} elseif (-not $gh) {
    $latestMain.Detail = 'GitHub CLI(gh)가 없어 원격 main SHA를 조회하지 않았다.'
} else {
    $latestMain.Detail = 'SkipActionsQuery 지정으로 원격 main SHA를 조회하지 않았다.'
}

$remoteZip = [pscustomobject]@{
    Status = 'NOT_VERIFIED'; ReportPath = $null; Source = $null; RunId = $null
    ArtifactName = $null; PackageSha256 = $null; PackagePath = $null
    Detail = '실제 원격 artifact를 내려받아 ZIP 검증을 완료한 보고서가 제공되지 않았다.'
}
if (-not [string]::IsNullOrWhiteSpace($RemoteZipVerificationReport)) {
    $reportPath = $RemoteZipVerificationReport
    if (-not [IO.Path]::IsPathRooted($reportPath)) { $reportPath = Join-Path $ProjectRoot $reportPath }
    $remoteZip.ReportPath = $reportPath
    if (Test-Path -LiteralPath $reportPath -PathType Leaf) {
        try {
            $verification = Get-Content -Encoding UTF8 -Raw -LiteralPath $reportPath | ConvertFrom-Json
            $remoteZip.Source = [string]$verification.source
            $remoteZip.RunId = [string]$verification.runId
            $remoteZip.ArtifactName = [string]$verification.artifactName
            $remoteZip.PackageSha256 = [string]$verification.packageSha256
            $remoteZip.PackagePath = [string]$verification.packagePath
            $checks = @($verification.checks)
            $failedChecks = @($checks | Where-Object { $_.status -ne 'PASS' })
            $checkNames = @($checks | ForEach-Object { [string]$_.name })
            $requiredCheckSets = @(
                @('Workflow run completed successfully', 'Expected artifact exists and is unexpired', 'Artifact download and extraction', 'Artifact package extraction', 'Extracted EXE SHA-256', 'Package ZIP SHA-256', 'Self-test, external working directory, GUI edit/save/reopen'),
                @('Latest successful package run for current main', 'Artifact name and ID from run API', 'Outer Actions ZIP download and digest', 'Inner deployment ZIP identified', 'Extracted deployment EXE SHA-256', 'Inner deployment ZIP SHA-256', 'Extracted EXE self-test and GUI verification')
            )
            $requiredChecksPresent = $false
            foreach ($requiredSet in $requiredCheckSets) {
                if (@($requiredSet | Where-Object { $_ -notin $checkNames }).Count -eq 0) { $requiredChecksPresent = $true; break }
            }
            $verifiedRunCheck = @($checks | Where-Object { $_.name -eq 'Latest successful package run for current main' -and $_.status -eq 'PASS' }).Count -eq 1
            $verifiedArtifactCheck = @($checks | Where-Object { $_.name -eq 'Artifact name and ID from run API' -and $_.status -eq 'PASS' }).Count -eq 1
            $reportHeadMatchesCheckout = $verification.mainSha -and ((Get-GitOutput -Arguments @('rev-parse', 'HEAD') | Select-Object -First 1).Trim() -eq [string]$verification.mainSha)
            $matchesRun = ($remoteZip.RunId -and (($ActionsRunId -and $remoteZip.RunId -eq $ActionsRunId) -or ($actions.RunId -and $remoteZip.RunId -eq $actions.RunId) -or ($verifiedRunCheck -and $reportHeadMatchesCheckout)))
            $matchesArtifact = ($remoteZip.ArtifactName -and (($artifact.Name -and $remoteZip.ArtifactName -eq $artifact.Name) -or ($verifiedArtifactCheck -and [long]$verification.artifactId -gt 0)))
            $hasChecks = ($checks.Count -gt 0 -and $failedChecks.Count -eq 0 -and $requiredChecksPresent)
            $packageExists = Test-Path -LiteralPath $remoteZip.PackagePath -PathType Leaf
            $packageHashMatches = $false
            if ($packageExists -and $remoteZip.PackageSha256 -match '^[0-9a-fA-F]{64}$') {
                $actualPackageHash = (Get-FileHash -LiteralPath $remoteZip.PackagePath -Algorithm SHA256).Hash.ToLowerInvariant()
                $packageHashMatches = ($actualPackageHash -eq $remoteZip.PackageSha256.ToLowerInvariant())
            }
            if ($remoteZip.Source -eq 'github-actions-artifact' -and $verification.status -eq 'PASS' -and $packageHashMatches -and $matchesRun -and $matchesArtifact -and $hasChecks) {
                $remoteZip.Status = 'PASS'
                $remoteZip.Detail = '원격 source, 선택 run/artifact 일치, 보고서의 필수 검사와 현재 ZIP SHA-256 재대조가 모두 PASS다.'
            } else {
                $remoteZip.Status = 'UNVERIFIED'
                $remoteZip.Detail = '보고서의 원격 출처, 필수 검사, 조사 run/artifact 일치, 다운로드 ZIP 실재 및 SHA-256 재대조 조건을 충족하지 않는다.'
            }
        } catch { $remoteZip.Status = 'UNVERIFIED'; $remoteZip.Detail = "검증 보고서 JSON을 판독하지 못했다: $($_.Exception.Message)" }
    } else {
        $remoteZip.Status = 'REPORT_MISSING'
        $remoteZip.Detail = '지정한 ZIP 검증 보고서 파일이 없다.'
    }
}

$manualGui = [pscustomobject]@{ Status = 'NOT_VERIFIED'; Evidence = @('docs/review/editor_acceptance_gate.md', '.qa_logs/qa_editor_exe_acceptance_20261009.json'); Detail = '사람의 수동 GUI 인수 미검증이다.' }
$physicalInput = [pscustomobject]@{ Status = 'NOT_VERIFIED'; Evidence = @('docs/review/manual_input_acceptance_gate.md'); Detail = '실제 물리 키 입력 미검증이다.' }
$gitHygiene = [pscustomobject]@{
    Status = if ($isExeTracked) { 'BLOCKED' } else { 'NOT_VERIFIED' }
    TrackedQaEditorExe = $isExeTracked
    Path = $trackedExe
    Evidence = @("git ls-files --error-unmatch -- $trackedExe", "git status --short -- $trackedExe")
    Detail = if ($isExeTracked) { 'QA 편집기 EXE가 Git index에서 추적 중이므로 저장소 위생 차단이다.' } else { '대상 EXE 미추적은 확인했으나 전체 repository hygiene gate의 별도 PASS는 확인하지 않았다.' }
}

$blockers = @(
    '제품 필수 동작은 10종(idle, run, turn, jump, hit, attack1~3, skill1~2)이다. 편집기 JSON 11클립은 jump_rise/jump_fall 분리로 설명되며 Num5 회전 증명은 skill2 별도 수용 조건이다.',
    'run v1~v5는 모두 동일 보폭으로 기록되어 반대 보폭/run cycle 수용을 통과하지 못했다: docs/review/player_run_v3_antiphase_gate.md, docs/review/player_run_v4_opposition_gate.md, docs/review/player_run_v5_antiphase_gate.md.',
    'jump rise/fall 및 hit 원화 후보는 확보됐지만 사람 승인과 본편 등록은 미완료다: docs/review/player_jump_rise_safe_gate.md, docs/review/player_jump_fall_safe_gate.md, docs/review/player_hit_reaction_safe_gate.md.',
    'Num4/Num5 전용 스킬 원화는 미승인이다. 절차 포즈와 gameplay 구현을 원화 승인으로 보지 않는다: docs/review/player_skill1_contact_motion_gate.md, docs/review/player_skill2_spin_art_gate.md.',
    'turn 동작은 0.13초 절차 표현이다. rear-mid 원본과 safe 후보가 확보된 경우에도 보폭이 달리기 자세로 읽혀 키포즈 수용은 보류이며 사람 승인 전 본편·manifest·allowlist에 등록하지 않는다: docs/review/player_turn_mid_art_gate.md, docs/review/player_turn_candidate_motion_gate.md.',
    '신규 승인 원화 0건이다. 기존 승인 원화는 v8 idle과 attack1~3 접촉 3장이다. Num5 skill2 v2 원화 파일은 확보됐지만 사람 승인 및 본편 등록은 되지 않았다: assets/art/player/elven_fighter_skill2_spin_backfist_v2_candidate_1254x1254.png.',
    '실제 물리 키 입력 인수 미검증: docs/review/manual_input_acceptance_gate.md.',
    '사람의 수동 GUI 인수 미검증: docs/review/editor_acceptance_gate.md 및 .qa_logs/qa_editor_exe_acceptance_20261009.json.',
    '최종 인수 PASS는 이 감사기가 생성하지 않는다. 증거 파일이나 자동 smoke의 존재만으로 제품 인수를 완료하지 않는다.'
)
if ($latestMain.Status -ne 'VERIFIED') { $blockers += "최신 원격 main SHA 미검증: $($latestMain.Detail)" }
if (-not $actions.MatchesLatestMain -or $actions.Status -ne 'completed' -or $actions.Conclusion -ne 'success') { $blockers += "최신 main SHA에 대한 Actions completed/success 미확인: $($actions.Detail) (status=$($actions.Status), conclusion=$($actions.Conclusion))." }
if ($artifact.Status -ne 'PRESENT') { $blockers += "최신 main Actions artifact 존재 미확인: $($artifact.Detail) (status=$($artifact.Status))." }
if ($remoteZip.Status -ne 'PASS') { $blockers += "실제 원격 ZIP 다운로드·검증 완료 미확인: $($remoteZip.Detail)" }
if ($gitHygiene.Status -ne 'PASS') { $blockers += "독립 Git 위생 차단: $($gitHygiene.Detail) (status=$($gitHygiene.Status))." }
if ($physicalInput.Status -ne 'MANUAL_REVIEW_RECORDED') { $blockers += "독립 물리 입력 인수 차단: $($physicalInput.Detail) (status=$($physicalInput.Status))." }
if ($manualGui.Status -ne 'PASS') { $blockers += "독립 GUI 사람 인수 차단: $($manualGui.Detail) (status=$($manualGui.Status))." }
if ($isExeTracked) { $blockers += "$trackedExe 가 Git index에서 추적 중이다. 현재 git status: $(if ($exeStatus.Count) { $exeStatus -join '; ' } else { 'clean (추적 중이며 작업 트리 변경 없음)' })." }
if (-not $isExeTracked -and $exeExists) { $blockers += "$trackedExe 는 Git 미추적이지만 로컬 파일은 존재한다." }
$blockers += '독립 차단 필드: LatestMain SHA 검증, 같은 SHA의 Actions 성공, artifact 존재, 실제 다운로드 ZIP 검증, Git 위생, 실제 물리 입력, 사람 GUI 인수는 각각 별도 확인하며 서로를 대체하지 않는다.'

$report = [pscustomobject]@{
    Audit = 'M5D independent acceptance readiness audit'
    GeneratedAtUtc = [DateTime]::UtcNow.ToString('o')
    ProjectRoot = $ProjectRoot
    Verdict = 'BLOCKED'
    FinalPassAllowed = $false
    DesignSource = 'docs/projecthub/initial-plan.md#개정-최종-완료-기준'
    RequiredProductAnimationCount = 10
    RequiredProductActions = @('idle', 'run', 'turn', 'jump', 'hit', 'attack1', 'attack2', 'attack3', 'skill1', 'skill2')
    EditorJsonClipCount = 11
    EditorJsonClips = $editorJsonClips
    AnimationAcceptanceFacts = [pscustomobject]@{
        RequiredProductActionsCount = 10
        EditorJsonClipCount = 11
        ExistingApprovedFramesCount = $manifestApprovedFrames.Count
        ExistingApprovedFrames = $manifestApprovedFrames
        NewHumanApprovedArtCount = 0
        TurnProceduralDurationSeconds = 0.13
        TurnCandidateOriginalPresent = $turnOriginalExists
        TurnCandidateOriginalSha256 = $turnOriginalHash
        TurnCandidateOriginalBytes = $turnOriginalBytes
        TurnSafeCandidatePresent = $turnSafeExists
        RunV1ToV5SameStrideAccepted = $false
        JumpRiseFallArtApproved = $false
        HitArtApproved = $false
        Num4Num5DedicatedArtApproved = $false
    }
    Skill2Num5RotationAcceptance = [pscustomobject]@{ Required = $true; CountsAsProductAnimation = $false; Status = 'NOT_ACCEPTED'; Evidence = @('docs/review/player_skill_motion_gate.md', 'docs/review/player_skill2_spin_art_gate.md'); V2OriginalArtSecured = $v2Exists }
    Criteria = $criterionReport
    RequiredAnimationClipReviewSlots = $clipReport
    ArtReadiness = $artReadiness
    LatestMain = $latestMain
    Actions = $actions
    Artifact = $artifact
    RemoteZipVerification = $remoteZip
    ManualGuiAcceptance = $manualGui
    PhysicalInputAcceptance = $physicalInput
    GitHygieneAcceptance = $gitHygiene
    GitChecks = [pscustomobject]@{
        TrackedQaEditorExe = $isExeTracked
        QaEditorExeExists = $exeExists
        QaEditorExeStatusPorcelain = $exeStatus
        GitEvidence = @("git ls-files --error-unmatch -- $trackedExe", "git status --short -- $trackedExe")
    }
    Blockers = $blockers
}

$report | ConvertTo-Json -Depth 10
exit 2
