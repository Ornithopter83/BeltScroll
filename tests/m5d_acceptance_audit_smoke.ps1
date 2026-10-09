[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$utf8 = New-Object System.Text.UTF8Encoding($false)
[Console]::OutputEncoding = $utf8
$OutputEncoding = $utf8
$root = Split-Path -Parent $PSScriptRoot
$audit = Join-Path $root 'tools/audit_m5d_acceptance.ps1'

$raw = @(& (Join-Path $PSHOME 'powershell.exe') -NoProfile -ExecutionPolicy Bypass -File $audit -ProjectRoot $root -SkipActionsQuery 2>&1)
$auditExitCode = $LASTEXITCODE
$jsonText = $raw -join "`n"
try { $report = $jsonText | ConvertFrom-Json } catch {
    throw "Auditor did not emit valid JSON. Exit=$auditExitCode Output=$jsonText"
}

if ($auditExitCode -ne 2) { throw "Auditor must use exit code 2 for blocked readiness; got $auditExitCode." }
if ($report.Verdict -ne 'BLOCKED' -or $report.FinalPassAllowed -ne $false) { throw 'Auditor must never issue final PASS.' }
$expectedCriteria = @('전체화면', '3배 표시', 'Num1~9', '앉기 제거', '양측 체력바', '독립 편집기', '원격 릴리스 ZIP')
foreach ($name in $expectedCriteria) {
    if (-not ($report.Criteria | Where-Object { $_.Criterion -eq $name })) { throw "Missing M5D criterion: $name" }
}
if ($report.RequiredAnimationClipReviewSlots.Count -ne 11) { throw "Expected 11 animation review slots; got $($report.RequiredAnimationClipReviewSlots.Count)." }
foreach ($requiredText in @('run v1~v4', 'Num5', '0건', '물리 키', 'GUI 인수')) {
    if (-not ($report.Blockers -join "`n").Contains($requiredText)) { throw "Missing required blocker: $requiredText" }
}
if (-not $report.GitChecks.GitEvidence -or ($report.GitChecks.GitEvidence -join ' ') -notmatch 'ls-files.*git status') {
    throw 'Auditor must inspect the real Git index and worktree status for the QA EXE.'
}
if ($report.Actions.Status -ne 'UNVERIFIED') { throw 'SkipActionsQuery must leave remote Actions evidence explicitly unverified.' }

Write-Output 'M5D acceptance audit smoke passed.'
