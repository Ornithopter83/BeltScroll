param(
    [string]$EditorPath,
    [int]$TimeoutSeconds = 120
)
$ErrorActionPreference = 'Stop'
$OutputEncoding = [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)
$root = Split-Path -Parent $PSScriptRoot
$allowlistPath = Join-Path $root 'data\editor\overrides.json'
$allowlistHashBefore = if (Test-Path -LiteralPath $allowlistPath) { (Get-FileHash -LiteralPath $allowlistPath -Algorithm SHA256).Hash } else { $null }
$work = Join-Path ([IO.Path]::GetTempPath()) ('BeltScrollTimelinePlayback_' + [Guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($work)
if ([string]::IsNullOrWhiteSpace($EditorPath)) {
    $buildRoot = Join-Path $work 'build'
    [void][IO.Directory]::CreateDirectory($buildRoot)
    & dotnet publish (Join-Path $root 'editor\BeltScrollEditor.csproj') -c Release -r win-x64 --self-contained true `
        -p:PublishSingleFile=true -p:IncludeNativeLibrariesForSelfExtract=true -p:EnableCompressionInSingleFile=true `
        -p:RuntimeFrameworkVersion=8.0.30 -p:NuGetAudit=false -p:RestoreIgnoreFailedSources=true `
        -p:DebugType=None -p:DebugSymbols=false -p:BaseIntermediateOutputPath="$buildRoot\obj\" `
        -p:BaseOutputPath="$buildRoot\bin\" -o "$buildRoot\publish"
    if ($LASTEXITCODE -ne 0) { throw "Editor build failed: $LASTEXITCODE. Artifacts: $work" }
    $EditorPath = Join-Path $buildRoot 'publish\BeltScrollEditor.exe'
    & $EditorPath --self-test
    if ($LASTEXITCODE -ne 0) { throw "Editor self-test failed: $LASTEXITCODE. Artifacts: $work" }
}
$EditorPath = (Resolve-Path -LiteralPath $EditorPath).Path
$process = Start-Process -FilePath $EditorPath -ArgumentList @('--animation-gui-acceptance', $work) -WorkingDirectory $work -PassThru
if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
    try { $process.Kill() } catch { }
    throw "Timeline playback GUI acceptance timed out. Artifacts: $work"
}
$reportPath = Join-Path $work 'animation-gui-acceptance.json'
if (-not (Test-Path -LiteralPath $reportPath)) { throw "GUI acceptance report missing (exit=$($process.ExitCode)). Artifacts: $work" }
$report = Get-Content -Encoding UTF8 -Raw -LiteralPath $reportPath | ConvertFrom-Json
if ($process.ExitCode -ne 0 -or -not $report.passed) { throw "GUI acceptance failed. Artifacts: $work`n$($report.error)" }
$expectedEvents = @(
    'frame reorder with duration identity',
    '35ms/50ms/105ms/200ms cumulative playback',
    'loop boundary',
    'pause and resume position',
    'slow tick catch-up',
    '10ms UI refresh trigger',
    'measured WinForms timer precision',
    '576px default review size',
    'side-by-side full-body and foot anchor',
    'overlay full-body and foot anchor',
    'actual frame duration',
    'multi-clip JSON export',
    'JSON reload'
)
foreach ($event in $expectedEvents) {
    if ($report.guiControlEvents -notcontains $event) { throw "GUI event verification missing '$event'. Artifacts: $work" }
}
$precision = $report.timerPrecision
if ($precision.requestedIntervalMs -ne 10 -or $precision.sampleCount -lt 10 -or $precision.minMs -le 0 -or $precision.maxMs -lt $precision.minMs) {
    throw "Measured timer precision report is invalid. Artifacts: $work"
}
if (-not (Test-Path -LiteralPath (Join-Path $work 'animation-gui.png')) -or -not (Test-Path -LiteralPath $report.exportedPath)) {
    throw "GUI capture or exported JSON is missing. Artifacts: $work"
}
foreach ($capture in @('comparison-side-by-side.png', 'comparison-overlay.png', 'comparison-zoom.png', 'comparison-pan.png')) {
    $capturePath = Join-Path $work $capture
    if (-not (Test-Path -LiteralPath $capturePath -PathType Leaf) -or (Get-Item -LiteralPath $capturePath).Length -lt 2048) {
        throw "GUI comparison capture missing or empty '$capture'. Artifacts: $work"
    }
}
if ($report.approvalDecisionCreated -or $report.gameAllowlistChanged -or $report.approvalState -ne 'review') {
    throw "Automated playback smoke must preserve review-only state and approval blocking. Artifacts: $work"
}
$exportedDocument = Get-Content -Encoding UTF8 -Raw -LiteralPath $report.exportedPath | ConvertFrom-Json
$frames = @($exportedDocument.clips | Where-Object { $_.id -eq 'attack1' } | ForEach-Object { $_.frames })
$durations = @($frames | ForEach-Object { [Math]::Round([double]$_.duration, 3) })
if (($durations -join ',') -ne '0.035,0.05,0.105,0.2') { throw "JSON roundtrip did not preserve frame sequence/durations: $($durations -join ','). Artifacts: $work" }
$allowlistHashAfter = if (Test-Path -LiteralPath $allowlistPath) { (Get-FileHash -LiteralPath $allowlistPath -Algorithm SHA256).Hash } else { $null }
if ($allowlistHashBefore -ne $allowlistHashAfter) { throw "GUI smoke changed the game allowlist file. Artifacts: $work" }
Write-Host ("Timeline playback GUI smoke passed. WinForms Timer requested=10ms, observed min/median/mean/max={0}/{1}/{2}/{3}ms over {4} intervals. Artifacts: {5}" -f $precision.minMs, $precision.medianMs, $precision.meanMs, $precision.maxMs, $precision.sampleCount, $work)
