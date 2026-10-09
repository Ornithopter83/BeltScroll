[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$utf8 = New-Object System.Text.UTF8Encoding($false)
[Console]::OutputEncoding = $utf8
$OutputEncoding = $utf8
$root = Split-Path -Parent $PSScriptRoot
$audit = Join-Path $root 'tools/audit_m6d_acceptance.ps1'
$raw = @(& (Join-Path $PSHOME 'powershell.exe') -NoProfile -ExecutionPolicy Bypass -File $audit -ProjectRoot $root -SkipRemoteQuery 2>&1)
$exitCode = $LASTEXITCODE
try { $report = ($raw -join "`n") | ConvertFrom-Json } catch { throw "Auditor did not emit valid JSON. Exit=$exitCode Output=$($raw -join "`n")" }

if ($exitCode -ne 2) { throw "Missing evidence must produce blocked exit code 2; got $exitCode." }
if ($report.Verdict -ne 'BLOCKED' -or $report.FinalPassAllowed -ne $false) { throw 'The audit must never issue final PASS.' }
$expected = @('원격 main SHA','Godot 자동 검증','실제 Window 플레이','물리 키보드 Num1~9','전체화면·3배 표시','편집기 GUI 왕복','원화 승인·연속 프레임','보스전과 종료','Git 위생')
if (@($report.Requirements).Count -ne $expected.Count) { throw 'Expected nine independent acceptance requirement rows.' }
foreach ($name in $expected) { if (-not ($report.Requirements | Where-Object { $_.Name -eq $name })) { throw "Missing independent requirement: $name" } }
if ($report.RemoteMain.Status -ne 'UNVERIFIED' -or $report.RemoteMain.Sha) { throw 'SkipRemoteQuery must leave the remote SHA unverified.' }
if ($report.GodotAutomatedValidation.Status -notin @('NOT_VERIFIED','UNVERIFIED')) { throw 'Missing Godot report must remain unverified.' }
if ($report.ActualWindow.Status -notin @('NOT_VERIFIED','UNVERIFIED')) { throw 'Missing Window report must remain unverified.' }
if ($report.PhysicalKeyboardNum1To9.Status -ne 'NOT_VERIFIED') { throw 'No physical keyboard report must remain unverified.' }
if ($report.FullscreenAndThreeTimesScale.Status -ne 'NOT_VERIFIED') { throw 'Display acceptance must be a separate human-observed record.' }
if ($report.EditorGuiRoundtrip.Status -ne 'NOT_VERIFIED') { throw 'GUI roundtrip must remain a separate human acceptance record.' }
if ($report.ArtApprovalAndContinuousFrames.Status -ne 'NOT_VERIFIED' -or $report.ArtApprovalAndContinuousFrames.NewHumanApprovedArtCount -ne 0) { throw 'No art approval evidence must report zero new approved art.' }
if ($report.BossBattleAndEnding.Status -ne 'NOT_VERIFIED') { throw 'No playthrough report must leave boss and ending unverified.' }
if (-not $report.GitHygiene.Status) { throw 'Git hygiene must have its own independent status.' }
if ($report.EvidenceRules.AutomatedInputIsPhysicalInput -ne $false -or $report.EvidenceRules.CaptureIsHumanApproval -ne $false -or $report.EvidenceRules.ZeroNewHumanApprovedArtBlocks -ne $true) { throw 'Manual evidence separation policy is missing.' }
if (@($report.Blockers).Count -lt 8) { throw 'Missing or unverified evidence must be listed as blockers.' }

# Even a passing automated report cannot fill human-only acceptance fields.
$tempRoot = Join-Path ([IO.Path]::GetTempPath()) ('m6d-audit-smoke-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tempRoot | Out-Null
try {
    $autoPath = Join-Path $tempRoot 'godot.json'
    $autoLog = Join-Path $tempRoot 'godot.log'
    [IO.File]::WriteAllText($autoLog, 'GODOT AUTOMATED PASS', $utf8)
    [IO.File]::WriteAllText($autoPath, (@{ result='PASS'; exitCode=0; evidence=@($autoLog); checks=@(@{name='headless';status='PASS'}) } | ConvertTo-Json -Depth 5), $utf8)
    $windowImage = Join-Path $tempRoot 'capture.png'
    [IO.File]::WriteAllBytes($windowImage, [byte[]](1,2,3))
    $windowPath = Join-Path $tempRoot 'window.json'
    $outcomes = @('boss-encounter','boss-defeated','player-defeat','restart' | ForEach-Object { @{ name=$_; status='PASS'; evidence=@($windowImage) } })
    [IO.File]::WriteAllText($windowPath, (@{ result='PASS'; headless=$false; windowTitle='BeltScroll'; evidence=@($windowImage); inputMode='gameplay-events'; directStateMutation=$false; internalOutcomeCalls=$false; outcomes=$outcomes } | ConvertTo-Json -Depth 6), $utf8)
    $rawAuto = @(& (Join-Path $PSHOME 'powershell.exe') -NoProfile -ExecutionPolicy Bypass -File $audit -ProjectRoot $root -SkipRemoteQuery -GodotReport $autoPath -WindowReport $windowPath -ManualReviewReport (Join-Path $tempRoot 'no-manual.json') 2>&1)
    $autoExit = $LASTEXITCODE
    try { $autoReport = ($rawAuto -join "`n") | ConvertFrom-Json } catch { throw "Auditor did not emit JSON with evidence fixtures. Exit=$autoExit Output=$($rawAuto -join "`n")" }
    if ($autoExit -ne 2 -or $autoReport.GodotAutomatedValidation.Status -ne 'PASS') { throw 'A valid automated report should independently pass Godot automatic validation.' }
    if ($autoReport.ActualWindow.Status -ne 'PASS_AUTOMATED_WINDOW' -or $autoReport.BossBattleAndEnding.Status -ne 'PASS_AUTOMATED_PLAYTHROUGH') { throw 'A valid non-headless event-driven playthrough fixture should pass its automated-only rows.' }
    if ($autoReport.PhysicalKeyboardNum1To9.Status -eq 'PASS' -or $autoReport.FullscreenAndThreeTimesScale.Status -eq 'PASS' -or $autoReport.ArtApprovalAndContinuousFrames.Status -like 'PASS*') { throw 'Automated reports/captures must not pass physical, display, or art-human acceptance.' }
    if ($autoReport.Verdict -ne 'BLOCKED' -or $autoReport.FinalPassAllowed -ne $false) { throw 'Automated evidence must never create final PASS.' }
} finally { Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue }

Write-Output 'M6D acceptance audit smoke passed.'
