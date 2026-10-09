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

$expectedActions = @('idle', 'run', 'turn', 'jump', 'hit', 'attack1', 'attack2', 'attack3', 'skill1', 'skill2')
if ($report.RequiredProductAnimationCount -ne 10) { throw "Expected 10 required product actions; got $($report.RequiredProductAnimationCount)." }
if (@($report.RequiredProductActions).Count -ne 10 -or ($report.RequiredProductActions -join ',') -ne ($expectedActions -join ',')) { throw 'Required product action set/order is incorrect.' }
if (@($report.RequiredAnimationClipReviewSlots).Count -ne 10) { throw "Expected 10 required animation review slots; got $(@($report.RequiredAnimationClipReviewSlots).Count)." }
if ($report.EditorJsonClipCount -ne 11 -or @($report.EditorJsonClips).Count -ne 11) { throw 'Editor JSON must report 11 clips, including split jump rise/fall.' }
if (@($report.RequiredAnimationClipReviewSlots[3].EditorClips).Count -ne 2 -or ($report.RequiredAnimationClipReviewSlots[3].EditorClips -join ',') -ne 'jump_rise,jump_fall') { throw 'Jump must map to the two editor JSON clips jump_rise and jump_fall.' }
if ($report.Skill2Num5RotationAcceptance.Required -ne $true -or $report.Skill2Num5RotationAcceptance.CountsAsProductAnimation -ne $false) { throw 'Num5 rotation proof must be a separate skill2 acceptance condition.' }

if ($report.LatestMain.Status -ne 'UNVERIFIED' -or $report.Actions.Status -ne 'UNVERIFIED') { throw 'SkipActionsQuery must leave current main and Actions independently unverified.' }
if ($report.Actions.RunId) { throw 'Auditor must not inject an old default Actions run ID.' }
if ($report.Artifact.Status -ne 'UNVERIFIED') { throw 'Artifact state must remain separate and unverified when Actions querying is skipped.' }
if ($report.RemoteZipVerification.Status -eq 'PASS') { throw 'No verification report must never imply a remote ZIP PASS.' }
if ($report.ArtReadiness.Skill2V2OriginalArt.Status -ne 'SECURED_UNAPPROVED') { throw 'Present Num5 skill2 v2 original art must be reported as secured but unapproved.' }
if ($report.ArtReadiness.RunV1ToV4SameStride.Status -ne 'SAME_STRIDE_NOT_ACCEPTED') { throw 'Run v1-v4 same-stride state must be reported.' }
if ($report.ArtReadiness.NewHumanApprovedArtCount -ne 0) { throw 'New human-approved art count must remain zero.' }
if ($report.ManualGuiAcceptance.Status -ne 'NOT_VERIFIED' -or $report.PhysicalInputAcceptance.Status -ne 'NOT_VERIFIED') { throw 'Manual GUI and physical input must remain explicitly unverified.' }

foreach ($requiredText in @('동일 보폭', '신규 승인 원화 0건', '물리 키 입력', '수동 GUI', '원격 ZIP')) {
    if (-not ($report.Blockers -join "`n").Contains($requiredText)) { throw "Missing required blocker text: $requiredText" }
}
if (-not $report.GitChecks.GitEvidence -or ($report.GitChecks.GitEvidence -join ' ') -notmatch 'ls-files.*git status') {
    throw 'Auditor must inspect the real Git index and worktree status for the QA EXE.'
}

# A file that merely claims PASS is not proof of a downloaded and checked remote ZIP.
$presenceOnlyPath = Join-Path ([IO.Path]::GetTempPath()) ('m5d-presence-only-' + [Guid]::NewGuid().ToString('N') + '.json')
try {
    $presenceOnly = [pscustomobject]@{ source = 'github-actions-artifact'; status = 'PASS' }
    [IO.File]::WriteAllText($presenceOnlyPath, ($presenceOnly | ConvertTo-Json), $utf8)
    $rawWithPresenceOnly = @(& (Join-Path $PSHOME 'powershell.exe') -NoProfile -ExecutionPolicy Bypass -File $audit -ProjectRoot $root -SkipActionsQuery -RemoteZipVerificationReport $presenceOnlyPath 2>&1)
    $presenceOnlyExitCode = $LASTEXITCODE
    try { $reportWithPresenceOnly = ($rawWithPresenceOnly -join "`n") | ConvertFrom-Json } catch {
        throw "Auditor did not emit JSON when given a presence-only report. Exit=$presenceOnlyExitCode Output=$($rawWithPresenceOnly -join "`n")"
    }
    if ($presenceOnlyExitCode -ne 2 -or $reportWithPresenceOnly.RemoteZipVerification.Status -eq 'PASS' -or $reportWithPresenceOnly.FinalPassAllowed -ne $false) {
        throw 'A present report containing only a PASS claim must not pass remote ZIP verification or final readiness.'
    }
} finally {
    Remove-Item -LiteralPath $presenceOnlyPath -Force -ErrorAction SilentlyContinue
}

Write-Output 'M5D acceptance audit smoke passed.'
