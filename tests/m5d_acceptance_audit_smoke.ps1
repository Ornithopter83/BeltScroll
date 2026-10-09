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
if (($report.EditorJsonClips -join ',') -ne 'idle,run,turn,jump_rise,jump_fall,hit,attack1,attack2,attack3,skill1,skill2') { throw 'Editor JSON clip inventory is incorrect.' }
if (@($report.RequiredAnimationClipReviewSlots[3].EditorClips).Count -ne 2 -or ($report.RequiredAnimationClipReviewSlots[3].EditorClips -join ',') -ne 'jump_rise,jump_fall') { throw 'Jump must map to the two editor JSON clips jump_rise and jump_fall.' }
if ($report.Skill2Num5RotationAcceptance.Required -ne $true -or $report.Skill2Num5RotationAcceptance.CountsAsProductAnimation -ne $false) { throw 'Num5 rotation proof must be a separate skill2 acceptance condition.' }
if ($report.AnimationAcceptanceFacts.RequiredProductActionsCount -ne 10 -or $report.AnimationAcceptanceFacts.EditorJsonClipCount -ne 11) { throw 'Product action count and editor JSON clip count must remain separate.' }
if ($report.AnimationAcceptanceFacts.ExistingApprovedFramesCount -ne 4 -or @($report.AnimationAcceptanceFacts.ExistingApprovedFrames).Count -ne 4) { throw 'Expected exactly the existing v8 idle and three approved attack contact frames.' }
$expectedApprovedFrames = @('idle:idle', 'attack1:contact', 'attack2:contact', 'attack3:contact')
$actualApprovedFrames = @($report.AnimationAcceptanceFacts.ExistingApprovedFrames | ForEach-Object { '{0}:{1}' -f $_.Clip, $_.Phase })
if (($actualApprovedFrames -join ',') -ne ($expectedApprovedFrames -join ',')) { throw 'Existing approved frame inventory must be v8 idle plus attack1-3 contact only.' }
if ($report.AnimationAcceptanceFacts.NewHumanApprovedArtCount -ne 0 -or $report.ArtReadiness.NewHumanApprovedArtCount -ne 0) { throw 'The audit must not claim any newly approved art.' }
if ($report.AnimationAcceptanceFacts.TurnProceduralDurationSeconds -ne 0.13 -or $report.ArtReadiness.TurnStatus -ne 'PROCEDURAL_IMPLEMENTED_DRAWING_UNAPPROVED') { throw 'Turn must be represented as a 0.13-second procedural action without approved dedicated art.' }
if ($report.ArtReadiness.TurnCandidateArt.Status -ne 'SECURED_UNAPPROVED_KEYPOSE_DEFERRED' -or -not $report.ArtReadiness.TurnCandidateArt.OriginalPresent -or -not $report.ArtReadiness.TurnCandidateArt.SafeCandidatePresent) { throw 'The secured turn source and safe derivative must be reported as present but unapproved.' }
if ($report.ArtReadiness.TurnCandidateArt.Approved -ne $false -or $report.ArtReadiness.TurnCandidateArt.PromotedToRuntime -ne $false) { throw 'Turn art audit must never promote an unapproved candidate.' }
if ($report.ArtReadiness.TurnCandidateArt.OriginalSha256 -ne '43ae0c54ee26ece7121ec60a265d507877b2cfea8408026f8bccd0ff3779da72' -or $report.ArtReadiness.TurnCandidateArt.OriginalBytes -ne 1032791) { throw 'Turn original SHA-256 and byte count must be preserved in audit output.' }
if ($report.ArtReadiness.TurnCandidateArt.Meaning -notmatch '0\.13초 절차 동작이 본편에서 사용') { throw 'Turn must identify the in-game 0.13-second procedural action.' }
if ($report.ArtReadiness.TurnV2CandidateArt.VisualAcceptance -ne 'NOT_ACCEPTED' -or $report.ArtReadiness.TurnV2CandidateArt.Approved -ne $false -or $report.ArtReadiness.TurnV2CandidateArt.PromotedToRuntime -ne $false) { throw 'Turn v2 presence and human visual acceptance must remain separate.' }
if (-not $report.ArtReadiness.TurnV2CandidateArt.OriginalPresent -or $report.ArtReadiness.TurnV2CandidateArt.OriginalPath -ne 'assets/art/player/elven_fighter_turn_pivot_v2_candidate_1254x1254.png' -or $report.ArtReadiness.TurnV2CandidateArt.OriginalSha256 -ne 'e4bbfe3684cb49c70604a785e6a2f4e1a1f832e971635337a9ec56dbe40525a3' -or $report.ArtReadiness.TurnV2CandidateArt.OriginalBytes -ne 788226) { throw 'The discovered turn v2 source path, SHA-256 and byte count must be audited.' }
if ($report.ArtReadiness.RunV1ToV5SameStride.Status -ne 'SAME_STRIDE_NOT_ACCEPTED') { throw 'Run v1-v5 same-stride state must remain unaccepted.' }
if ($report.AnimationAcceptanceFacts.RunV1ToV5SameStrideAccepted -ne $false) { throw 'The audit must keep the v1-v5 run set unaccepted.' }
if ($report.ArtReadiness.JumpRiseFallAndHitArt.Status -ne 'CANDIDATES_UNAPPROVED' -or $report.AnimationAcceptanceFacts.JumpRiseFallArtApproved -ne $false -or $report.AnimationAcceptanceFacts.HitArtApproved -ne $false) { throw 'Jump rise/fall and hit candidates must remain explicitly unapproved.' }
if ($report.ArtReadiness.JumpRiseFallAndHitArt.JumpSizeAndAnchorValidation -ne 'NOT_VERIFIED' -or $report.AnimationAcceptanceFacts.JumpSizeAndAnchorValidation -ne 'NOT_VERIFIED') { throw 'Jump artwork size and anchor validation must remain an explicit blocker.' }
if ($report.ArtReadiness.JumpRiseFallAndHitArt.HitOutfitMismatchRisk -ne 'POSSIBLE_NOT_RESOLVED' -or $report.AnimationAcceptanceFacts.HitOutfitMismatchRisk -ne 'POSSIBLE_NOT_RESOLVED') { throw 'Possible hit outfit mismatch must remain a separate blocker.' }
if (@($report.ArtReadiness.JumpRiseFallAndHitArt.CandidateFilesPresent).Count -lt 3) { throw 'Expected secured jump rise/fall and hit candidate files to be distinguished from approval.' }
if ($report.ArtReadiness.Num4Num5DedicatedArt.Status -ne 'CANDIDATES_UNAPPROVED' -or $report.ArtReadiness.Num4Num5DedicatedArt.DedicatedArtApproved -ne $false -or $report.AnimationAcceptanceFacts.Num4Num5DedicatedArtApproved -ne $false) { throw 'Num4/Num5 dedicated skill art must remain explicitly unapproved.' }
if ($report.ArtReadiness.Num4Num5DedicatedArt.Num4FistExtension -ne 'NOT_IMPLEMENTED' -or $report.AnimationAcceptanceFacts.Num4FistExtension -ne 'NOT_IMPLEMENTED') { throw 'Num4 fist extension must remain explicitly unimplemented.' }
if ($report.ArtReadiness.Num4Num5DedicatedArt.Num5BackfistVisualAcceptance -ne 'NOT_PROVEN' -or $report.AnimationAcceptanceFacts.Num5BackfistVisualAcceptance -ne 'NOT_PROVEN') { throw 'Num5 backfist must remain explicitly unproven.' }

if ($report.LatestMain.Status -ne 'UNVERIFIED' -or $report.Actions.Status -ne 'UNVERIFIED') { throw 'SkipActionsQuery must leave current main and Actions independently unverified.' }
if ($report.Actions.RunId) { throw 'Auditor must not inject an old default Actions run ID.' }
if ($report.Artifact.Status -ne 'UNVERIFIED') { throw 'Artifact state must remain separate and unverified when Actions querying is skipped.' }
if ($report.RemoteZipVerification.Status -eq 'PASS') { throw 'No verification report must never imply a remote ZIP PASS.' }
if ($report.ArtReadiness.Skill2V2OriginalArt.Status -ne 'SECURED_UNAPPROVED' -or -not $report.ArtReadiness.Skill2V2OriginalArt.FilePresent -or $report.ArtReadiness.Skill2V2OriginalArt.VisualAcceptance -ne 'NOT_ACCEPTED') { throw 'Num5 skill2 v2 file presence and visual acceptance must be separate states.' }
if (-not $report.Skill2Num5RotationAcceptance.V2FilePresent -or $report.Skill2Num5RotationAcceptance.V2VisualAcceptance -ne 'NOT_ACCEPTED') { throw 'Num5 v2 file presence must not imply visual acceptance.' }
if ($report.ArtReadiness.RunV1ToV5SameStride.Status -ne 'SAME_STRIDE_NOT_ACCEPTED') { throw 'Run v1-v5 same-stride state must be reported.' }
if ($report.ArtReadiness.NewHumanApprovedArtCount -ne 0) { throw 'New human-approved art count must remain zero.' }
if ($report.ManualGuiAcceptance.Status -ne 'NOT_VERIFIED' -or $report.PhysicalInputAcceptance.Status -ne 'NOT_VERIFIED') { throw 'Manual GUI and physical input must remain explicitly unverified.' }
if (-not $report.GitHygieneAcceptance.Status -or -not $report.GitHygieneAcceptance.Evidence) { throw 'Git hygiene must have its own independent status and evidence field.' }
foreach ($field in @('LatestMain','Actions','Artifact','RemoteZipVerification','GitHygieneAcceptance','PhysicalInputAcceptance','ManualGuiAcceptance')) {
    if ($null -eq $report.$field.Status) { throw "Missing independent readiness blocker field: $field." }
}

foreach ($requiredText in @('동일 보폭', '신규 승인 원화 0건', 'jump rise/fall', 'Num4', 'Num5', '0.13초', '물리 키 입력', '수동 GUI', '원격 ZIP')) {
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
