$ErrorActionPreference = 'Stop'
$utf8 = New-Object System.Text.UTF8Encoding($false)
[Console]::OutputEncoding = $utf8
$OutputEncoding = $utf8
$root = Split-Path -Parent $PSScriptRoot
$suitePath = Join-Path $root 'tools\smoke_suite.cmd'
$suite = [IO.File]::ReadAllLines($suitePath, [Text.Encoding]::UTF8)
$joined = $suite -join "`n"
$failures = New-Object 'System.Collections.Generic.List[string]'

function Assert-ReviewPolicy([bool]$condition, [string]$description) {
    if ($condition) {
        Write-Output "PASS: $description"
    } else {
        $script:failures.Add($description)
    }
}

$registered = @(
    'call :run_smoke attack2_candidate_motion_review_smoke',
    'call :run_smoke player_attack3_startup_review_smoke',
    'call :run_smoke player_animation_state_matrix_smoke',
    'call :run_window_smoke player_skill_interruption_smoke 360',
    'call :run_smoke player_skill2_spin_art_smoke'
)
foreach ($line in $registered) {
    Assert-ReviewPolicy (@($suite | Where-Object { $_.Trim() -ceq $line }).Count -eq 1) "registered review smoke appears exactly once: $line"
}

foreach ($name in @('player_skill1_visual_telegraph_smoke', 'player_skill2_visual_telegraph_smoke', 'player_skill_interruption_smoke')) {
    $line = @($suite | Where-Object { $_ -match ('^call :run_window_smoke ' + [regex]::Escape($name) + ' 360(?:\s|$)') })
    Assert-ReviewPolicy ($line.Count -eq 1 -and $line[0] -notmatch '--headless') "$name is routed through the real Window smoke helper with a 360 second timeout"
}
$spinLine = @($suite | Where-Object { $_.Trim() -ceq 'call :run_smoke player_skill2_spin_art_smoke' })
Assert-ReviewPolicy ($spinLine.Count -eq 1) 'player_skill2_spin_art_smoke runs once through the headless helper'
Assert-ReviewPolicy ($joined.Contains('player_skill2_spin_art_smoke: mechanical checks passed; no production registration without human approval')) 'spin-art mechanical results do not claim human art approval'

$liveStart = [Array]::IndexOf($suite, ':rebuild_live_review_captures')
$liveEnd = [Array]::IndexOf($suite, ':failed_capture')
Assert-ReviewPolicy ($liveStart -ge 0 -and $liveEnd -gt $liveStart) 'explicit capture mode has a bounded, separate command section'
$liveLines = @()
if ($liveStart -ge 0 -and $liveEnd -gt $liveStart) {
    $liveLines = @($suite[($liveStart + 1)..($liveEnd - 1)])
}
$liveText = $liveLines -join "`n"
$baseText = $joined.Substring(0, [Math]::Max(0, $joined.IndexOf(':rebuild_live_review_captures')))

foreach ($capture in @('capture_attack2_candidate_motion_review', 'capture_player_animation_state_matrix')) {
    $invocation = @($liveLines | Where-Object { $_ -match ('res://tools/' + [regex]::Escape($capture) + '\.gd') })
    Assert-ReviewPolicy ($invocation.Count -eq 1) "explicit capture mode invokes $capture exactly once"
    if ($invocation.Count -eq 1) {
        Assert-ReviewPolicy ($invocation[0] -notmatch '--headless') "$capture uses the real Window renderer"
    }
    Assert-ReviewPolicy ($baseText -notmatch ('res://tools/' + [regex]::Escape($capture) + '\.gd')) "$capture is excluded from the regular regression suite"
}

Assert-ReviewPolicy ($joined.Contains('if /I "%~1"=="--rebuild-live-review-captures" goto live_review_captures')) 'capture regeneration requires the explicit mode argument'
Assert-ReviewPolicy ($liveText.Contains('execution_type=window_capture,visual_approval=not_granted')) 'capture mode logs Window execution without claiming visual approval'
Assert-ReviewPolicy ($liveText.Contains('human visual approval remains pending')) 'capture completion keeps human visual review pending'
Assert-ReviewPolicy ($liveText -notmatch '(?i)visual_approval=(approved|accepted)|visual review passed') 'capture mode contains no automatic visual approval claim'

$attack2Capture = Join-Path $root 'tools\capture_attack2_candidate_motion_review.gd'
$matrixCapture = Join-Path $root 'tools\capture_player_animation_state_matrix.gd'
$startupBuilder = Join-Path $root 'tools\build_player_attack3_startup_review.gd'
foreach ($path in @($attack2Capture, $matrixCapture, $startupBuilder)) {
    Assert-ReviewPolicy (Test-Path -LiteralPath $path -PathType Leaf) "registered live review tool exists: $([IO.Path]::GetFileName($path))"
}

if ($failures.Count -gt 0) {
    foreach ($failure in $failures) {
        [Console]::Error.WriteLine("animation_live_review_suite_smoke: FAIL: $failure")
    }
    exit 1
}

Write-Output 'animation_live_review_suite_smoke: all checks passed'
exit 0
