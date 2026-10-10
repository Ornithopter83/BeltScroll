param(
    [string]$EditorPath,
    [int]$TimeoutSeconds = 120
)
$ErrorActionPreference = 'Stop'
$OutputEncoding = [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)
$root = Split-Path -Parent $PSScriptRoot
$allowlistPath = Join-Path $root 'data\editor\overrides.json'
$allowlistHashBefore = if (Test-Path -LiteralPath $allowlistPath) { (Get-FileHash -LiteralPath $allowlistPath -Algorithm SHA256).Hash } else { $null }
& (Join-Path $root 'editor\build_editor.ps1') -SelfTest
if ($LASTEXITCODE -ne 0) { throw "Editor build/self-test failed: $LASTEXITCODE" }
if ([string]::IsNullOrWhiteSpace($EditorPath)) { $EditorPath = Join-Path $root 'dist\BeltScrollEditor.exe' }
$EditorPath = (Resolve-Path -LiteralPath $EditorPath).Path
$work = Join-Path ([IO.Path]::GetTempPath()) ('BeltScrollM6kTransition_' + [Guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($work)
$process = Start-Process -FilePath $EditorPath -ArgumentList @('--animation-gui-acceptance', $work) -WorkingDirectory $work -PassThru
if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
    try { $process.Kill() } catch { }
    throw "Animation transition GUI acceptance timed out. Artifacts: $work"
}
$reportPath = Join-Path $work 'animation-gui-acceptance.json'
if (-not (Test-Path -LiteralPath $reportPath)) { throw "GUI acceptance report missing (exit=$($process.ExitCode)). Artifacts: $work" }
$report = Get-Content -Encoding UTF8 -Raw -LiteralPath $reportPath | ConvertFrom-Json
if ($process.ExitCode -ne 0 -or -not $report.passed) { throw "Animation transition GUI acceptance failed. Artifacts: $work`n$($report.error)" }
$arrow = [char]0x2192
$expectedEvents = @(
    "isolated run${arrow}attack1/2/3 sequences",
    'skill1/skill2 startup-contact-recovery sequences',
    'ordered frame, duration and foot anchor display',
    'previous/current frame ghost and sampled pixel difference',
    'single still image distinguished from frame sequence',
    'unapproved PNG playback confined to isolated workspace',
    'automatic preview does not approve art',
    'multi-clip JSON export',
    'JSON reload'
)
foreach ($event in $expectedEvents) {
    if ($report.guiControlEvents -notcontains $event) { throw "GUI event verification missing '$event'. Artifacts: $work" }
}
$expectedCounts = [ordered]@{ "run $arrow attack1" = 7; "run $arrow attack2" = 4; "run $arrow attack3" = 4; skill1 = 3; skill2 = 3 }
foreach ($route in $expectedCounts.Keys) {
    if ($report.transitionCounts.PSObject.Properties[$route].Value -ne $expectedCounts[$route]) { throw "Wrong frame count for '$route'. Artifacts: $work" }
}
if (-not (Test-Path -LiteralPath (Join-Path $work 'animation-gui.png')) -or -not (Test-Path -LiteralPath $report.exportedPath)) { throw "GUI capture or exported JSON is missing. Artifacts: $work" }
$tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
$isolatedWorkspace = [IO.Path]::GetFullPath([string]$report.workspacePath)
if (-not $isolatedWorkspace.StartsWith($tempRoot, [StringComparison]::OrdinalIgnoreCase)) { throw "Reopened preview assets did not stay in the OS temporary isolation folder. Artifacts: $work" }
if ($report.approvalDecisionCreated -or $report.gameAllowlistChanged -or $report.approvalState -ne 'review') { throw "Automated transition preview must not approve art or change the game allowlist. Artifacts: $work" }
$exportedDocument = Get-Content -Encoding UTF8 -Raw -LiteralPath $report.exportedPath | ConvertFrom-Json
$runFrames = @($exportedDocument.clips | Where-Object { $_.id -eq 'run' } | ForEach-Object { $_.frames })
if ($runFrames.Count -ne 3 -or @($runFrames | Where-Object { $_.phase -ne 'stride' -or $_.approval_state -ne 'review' }).Count -ne 0) { throw "Run stride candidates did not remain isolated review frames. Artifacts: $work" }
foreach ($id in @('attack1','skill1','skill2')) {
    $clip = $exportedDocument.clips | Where-Object { $_.id -eq $id }
    if (@($clip.frames | ForEach-Object { $_.phase }) -notcontains 'contact' -or @($clip.frames | ForEach-Object { $_.phase }) -notcontains 'recovery') { throw "$id startup/contact/recovery frames did not roundtrip. Artifacts: $work" }
    if (@($clip.frames | Where-Object { $_.approval_state -ne 'review' }).Count -ne 0) { throw "$id frame approval state changed during preview. Artifacts: $work" }
}
$allowlistHashAfter = if (Test-Path -LiteralPath $allowlistPath) { (Get-FileHash -LiteralPath $allowlistPath -Algorithm SHA256).Hash } else { $null }
if ($allowlistHashBefore -ne $allowlistHashAfter) { throw "Transition smoke changed the game allowlist file. Artifacts: $work" }
Write-Host "M6K isolated animation transition smoke passed. Artifacts: $work"
