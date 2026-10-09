$ErrorActionPreference = 'Stop'
$utf8 = New-Object System.Text.UTF8Encoding($false)
[Console]::OutputEncoding = $utf8
$OutputEncoding = $utf8
$root = Split-Path -Parent $PSScriptRoot
$suite = [IO.File]::ReadAllLines((Join-Path $root 'tools\smoke_suite.cmd'), [Text.Encoding]::UTF8)
$failures = New-Object 'System.Collections.Generic.List[string]'

function Assert-Coverage([bool]$condition, [string]$description) {
    if ($condition) {
        Write-Output "PASS: $description"
    } else {
        $script:failures.Add($description)
    }
}

$candidateSmokes = @(
    'player_run_stride_v2_safe_smoke',
    'player_run_v3_antiphase_smoke',
    'player_jump_rise_safe_smoke',
    'player_skill1_rush_safe_smoke'
)
foreach ($name in $candidateSmokes) {
    $invoke = @($suite | Where-Object { $_.Trim() -ceq "call :run_smoke $name" })
    $record = @($suite | Where-Object { $_.Trim() -ceq "call :record_additional_check $name headless" })
    Assert-Coverage ($invoke.Count -eq 1 -and $record.Count -eq 1) "$name has one headless invocation and one actual-exit record"
    Assert-Coverage (Test-Path -LiteralPath (Join-Path $PSScriptRoot ($name + '.gd')) -PathType Leaf) "$name script exists"
}

$playerDir = Join-Path $root 'assets\art\player'
$v4Candidates = @()
if (Test-Path -LiteralPath $playerDir -PathType Container) {
    $v4Candidates = @(Get-ChildItem -LiteralPath $playerDir -File -Filter '*.png' | Where-Object { $_.Name -match '(?i)run_stride_v4' })
}
if ($v4Candidates.Count -eq 0) {
    Write-Output 'INFO: run v4 candidate is NOT ACQUIRED; coverage gate accepts this branch.'
    $v4State = 'not-acquired'
} else {
    Write-Output "INFO: run v4 candidate files found: $($v4Candidates.Count); they remain unapproved review inputs."
    $v4State = 'acquired-pending-review'
}

$animationBankName = 'player_animation_bank_smoke'
$bankInvocation = @($suite | Where-Object { $_.Trim() -ceq "call :run_smoke $animationBankName" })
$bankPath = Join-Path $PSScriptRoot ($animationBankName + '.gd')
Assert-Coverage ($bankInvocation.Count -eq 1) 'approved-frame isolation has one existing animation-bank smoke invocation'
Assert-Coverage (Test-Path -LiteralPath $bankPath -PathType Leaf) 'approved-frame isolation smoke script exists'
$bank = [IO.File]::ReadAllText($bankPath, [Text.Encoding]::UTF8)
foreach ($contract in @(
    'registry starts with zero new approvals',
    'extended approved art without a reviewed-frame entry is rejected',
    'a duplicate approved manifest frame cannot reuse one reviewed registry identity',
    'rejected v6 cannot replace built-in approved contact registration'
)) {
    Assert-Coverage ($bank.Contains($contract)) "approved-frame isolation contract is covered: $contract"
}

$manifestPath = Join-Path $root 'data\art\animation_manifest.json'
$registryPath = Join-Path $root 'data\art\reviewed_frame_allowlist.json'
$manifest = [IO.File]::ReadAllText($manifestPath, [Text.Encoding]::UTF8)
$registry = [IO.File]::ReadAllText($registryPath, [Text.Encoding]::UTF8) | ConvertFrom-Json
$reviewOnlyNames = @(
    'elven_fighter_run_stride_v2_safe_candidate_1254x1254.png',
    'elven_fighter_run_stride_v3_left_lead_candidate_1254x1254.png',
    'elven_fighter_jump_rise_v1_safe_candidate_1254x1254.png',
    'elven_fighter_skill1_rush_contact_v1_safe_candidate_1254x1254.png'
)
foreach ($candidate in $reviewOnlyNames) {
    Assert-Coverage (-not $manifest.Contains($candidate)) "candidate remains absent from the gameplay animation manifest: $candidate"
}
Assert-Coverage (@($registry.entries).Count -eq 0) 'reviewed-frame allowlist remains unchanged and empty'
Assert-Coverage ($manifest -notmatch '(?i)run_stride_v4') 'no optional v4 candidate is integrated into the gameplay manifest'

if ($failures.Count -gt 0) {
    foreach ($failure in $failures) { [Console]::Error.WriteLine("animation_candidate_coverage_smoke: FAIL: $failure") }
    exit 1
}

Write-Output "animation_candidate_coverage_smoke: candidate calls, optional v4 state ($v4State), and approved-frame isolation verified; smoke evidence does not grant approval"
Write-Output 'animation_candidate_coverage_smoke: all checks passed'
exit 0
