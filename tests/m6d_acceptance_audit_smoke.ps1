[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$utf8 = New-Object System.Text.UTF8Encoding($false)
[Console]::OutputEncoding = $utf8
$OutputEncoding = $utf8
$root = Split-Path -Parent $PSScriptRoot
$audit = Join-Path $root 'tools/audit_m6d_acceptance.ps1'
$powershell = Join-Path $PSHOME 'powershell.exe'
$head = (& git -C $root rev-parse --verify 'HEAD^{commit}').Trim().ToLowerInvariant()
if ($LASTEXITCODE -ne 0) { throw 'Could not resolve the local inspection commit for fixtures.' }
$now = [DateTime]::UtcNow.ToString('o')
$tempRoot = Join-Path ([IO.Path]::GetTempPath()) ('m6d-audit-smoke-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tempRoot | Out-Null

function Write-JsonUtf8 {
    param([string]$Path, [object]$Value)
    [IO.File]::WriteAllText($Path, (ConvertTo-Json -InputObject $Value -Depth 12), $utf8)
}

function Invoke-Audit {
    param([string]$GodotPath, [string]$WindowPath, [string]$ManualPath)
    $args = @('-NoProfile','-ExecutionPolicy','Bypass','-File',$audit,'-ProjectRoot',$root,'-SkipRemoteQuery')
    if ($GodotPath) { $args += @('-GodotReport',$GodotPath) }
    if ($WindowPath) { $args += @('-WindowReport',$WindowPath) }
    if ($ManualPath) { $args += @('-ManualReviewReport',$ManualPath) }
    $raw = @(& $powershell @args 2>&1)
    $code = $LASTEXITCODE
    try { $report = ($raw -join "`n") | ConvertFrom-Json }
    catch { throw "Auditor did not emit JSON. Exit=$code Output=$($raw -join "`n")" }
    if ($code -ne 2) { throw "Audit must return blocked/pending exit code 2; got $code." }
    return $report
}

try {
    $empty = Invoke-Audit '' '' ''
    if ($empty.Verdict -ne 'BLOCKED' -or $empty.FinalPassAllowed -ne $false) { throw 'Missing evidence must remain blocked and final PASS must always be disabled.' }
    if ($empty.InspectedCommitSha -ne $head) { throw 'The report must name the exact inspected local HEAD.' }
    $expected = @('원격 main SHA와 검사 HEAD','Godot 자동 검증','실제 Window 플레이','물리 키보드 Num1~9','전체화면·3배 표시','편집기 GUI 왕복','원화 승인·연속 프레임','보스전과 종료','필수 검수 서류','Git 위생')
    if (@($empty.Requirements).Count -ne $expected.Count) { throw 'Expected ten independent acceptance requirements.' }
    foreach ($name in $expected) { if (-not ($empty.Requirements | Where-Object { $_.Name -eq $name })) { throw "Missing independent requirement: $name" } }
    if ($empty.RemoteMain.Status -ne 'UNVERIFIED' -or $empty.RemoteMain.MatchesInspectedCommit) { throw 'Offline audit must not infer remote SHA agreement.' }
    if ($empty.EvidencePolicy.SyntheticInputAccepted -ne $false -or $empty.EvidencePolicy.ZeroNewHumanApprovedArtBlocks -ne $true) { throw 'Evidence separation policy is missing.' }
    if ($empty.ArtApprovalAndContinuousFrames.NewHumanApprovedArtCount -ne 0 -or $empty.ArtApprovalAndContinuousFrames.Status -notlike '*ZERO*' -and $empty.ArtApprovalAndContinuousFrames.Status -ne 'NOT_VERIFIED') { throw 'Zero new art approvals must block.' }

    # Fresh timestamps and a hash over a three-byte pretend capture are insufficient evidence.
    $fakeCapture = Join-Path $tempRoot 'pretend.png'
    [IO.File]::WriteAllBytes($fakeCapture, [byte[]](1,2,3))
    $fakeLog = Join-Path $tempRoot 'pretend.log'
    [IO.File]::WriteAllText($fakeLog, 'PASS', $utf8)
    $fakePngHash = (Get-FileHash -LiteralPath $fakeCapture -Algorithm SHA256).Hash.ToLowerInvariant()
    $fakeLogHash = (Get-FileHash -LiteralPath $fakeLog -Algorithm SHA256).Hash.ToLowerInvariant()

    $staleGodot = Join-Path $tempRoot 'stale-godot.json'
    Write-JsonUtf8 $staleGodot @{ result='PASS'; exitCode=0; targetCommitSha=$head; generatedAtUtc='2020-01-01T00:00:00Z'; evidence=@($fakeLog); evidenceHashes=@(@{path=$fakeLog;sha256=$fakeLogHash}); checks=@(@{name='test';status='PASS'}) }
    $fakeWindow = Join-Path $tempRoot 'fake-window.json'
    $outcomes = @('boss-encounter','boss-defeated','player-defeat','restart' | ForEach-Object { @{ name=$_; status='PASS'; evidence=@($fakeCapture,$fakeLog) } })
    $common = @{ targetCommitSha=$head; generatedAtUtc=$now; evidence=@($fakeCapture,$fakeLog); evidenceHashes=@(@{path=$fakeCapture;sha256=$fakePngHash},@{path=$fakeLog;sha256=$fakeLogHash}) }
    $windowFixture = $common.Clone()
    $windowFixture.result='PASS'; $windowFixture.headless=$false; $windowFixture.windowTitle='BeltScroll'; $windowFixture.inputMode='synthetic'; $windowFixture.directStateMutation=$false; $windowFixture.internalOutcomeCalls=$false; $windowFixture.outcomes=$outcomes
    Write-JsonUtf8 $fakeWindow $windowFixture

    $fakeManual = Join-Path $tempRoot 'fake-manual.json'
    $artFrames = @(
        @{index=0;humanApproved=$true;evidence=@($fakeCapture)},
        @{index=1;humanApproved=$true;evidence=@($fakeCapture)}
    )
    Write-JsonUtf8 $fakeManual (@{
        targetCommitSha=$head; generatedAtUtc=$now; evidence=@($fakeCapture); evidenceHashes=@(@{path=$fakeCapture;sha256=$fakePngHash})
        physicalKeyboard=@{status='PASS';method='physical-keyboard';reviewer='fixture';observedAt=$now;checks=@(@('Num1','Num2','Num3','Num4','Num5','Num6','Num7','Num8','Num9' | ForEach-Object { @{name=$_;status='PASS';evidence=@($fakeCapture)} }))}
        display=@{status='PASS';method='human-observed';reviewer='fixture';observedAt=$now;checks=@(@('fullscreen','three-times-scale' | ForEach-Object { @{name=$_;status='PASS';evidence=@($fakeCapture)} }))}
        editorGuiRoundtrip=@{status='PASS';method='human-gui';reviewer='fixture';observedAt=$now;checks=@(@('create','edit','save-close','reopen-verify','apply-to-game' | ForEach-Object { @{name=$_;status='PASS';evidence=@($fakeCapture)} }))}
        artReview=@{method='human-visual-review';reviewer='fixture';reviewedAt=$now;sequences=@(@{id='fake';decision='approved';newApproval=$true;approvedAt=$now;frames=$artFrames})}
    })

    $forged = Invoke-Audit $staleGodot $fakeWindow $fakeManual
    if ($forged.GodotAutomatedValidation.Status -eq 'PASS') { throw 'A stale report with a claimed PASS must fail.' }
    if ($forged.ActualWindow.Status -like 'PASS*' -or $forged.BossBattleAndEnding.Status -like 'PASS*') { throw 'Synthetic input and a malformed fake PNG must never pass Window evidence.' }
    if ($forged.PhysicalKeyboardNum1To9.Status -like 'PASS*' -or $forged.FullscreenAndThreeTimesScale.Status -like 'PASS*' -or $forged.EditorGuiRoundtrip.Status -like 'PASS*') { throw 'Malformed evidence files must not satisfy human checklist claims.' }
    if ($forged.ArtApprovalAndContinuousFrames.NewHumanApprovedArtCount -ne 0 -or $forged.ArtApprovalAndContinuousFrames.Status -like 'PASS*') { throw 'Fake image bytes cannot create new art approvals.' }
    if ($forged.Verdict -ne 'BLOCKED' -or $forged.FinalPassAllowed -ne $false) { throw 'Forged reports must leave the integrated audit blocked.' }

    # A recent, hash-matched automated report still cannot fill any human-only acceptance row.
    $freshGodot = Join-Path $tempRoot 'fresh-godot.json'
    Write-JsonUtf8 $freshGodot @{ result='PASS'; exitCode=0; targetCommitSha=$head; generatedAtUtc=$now; evidence=@($fakeLog); evidenceHashes=@(@{path=$fakeLog;sha256=$fakeLogHash}); checks=@(@{name='headless';status='PASS'}) }
    $fresh = Invoke-Audit $freshGodot '' ''
    if ($fresh.GodotAutomatedValidation.Status -ne 'PASS_AUTOMATED') { throw 'A current, commit-bound, hash-matched Godot report should independently pass its automation row.' }
    if ($fresh.PhysicalKeyboardNum1To9.Status -like 'PASS*' -or $fresh.FullscreenAndThreeTimesScale.Status -like 'PASS*' -or $fresh.EditorGuiRoundtrip.Status -like 'PASS*' -or $fresh.ArtApprovalAndContinuousFrames.Status -like 'PASS*') { throw 'Automation must not satisfy human input, display, GUI, or art acceptance.' }
    if ($fresh.FinalPassAllowed -ne $false -or $fresh.Verdict -eq 'PASS') { throw 'No combination of automated evidence can issue product PASS.' }
} finally { Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue }

Write-Output 'M6D acceptance audit smoke passed.'
