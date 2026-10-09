param(
    [Parameter(Mandatory = $true)]
    [string]$PackagePath,
    [switch]$AllowGuiUnverified,
    [int]$TimeoutSeconds = 120
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$OutputEncoding = [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)
try { Add-Type -AssemblyName System.Drawing.Common -ErrorAction Stop }
catch { Add-Type -AssemblyName System.Drawing -ErrorAction Stop }
$packageFullPath = [IO.Path]::GetFullPath($PackagePath)
if (-not (Test-Path -LiteralPath $packageFullPath -PathType Leaf)) { throw "Package not found: $packageFullPath" }
$projectRoot = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$testRoot = Join-Path ([IO.Path]::GetTempPath()) ('BeltScrollEditorReleaseSmoke_' + [Guid]::NewGuid().ToString('N'))
if ($testRoot.StartsWith($projectRoot, [StringComparison]::OrdinalIgnoreCase)) { throw "Smoke folder must be outside the project: $testRoot" }
[void][IO.Directory]::CreateDirectory($testRoot)
$reportPath = Join-Path $testRoot 'release-smoke-report.json'
$checks = New-Object System.Collections.Generic.List[object]

function Add-Check([string]$Name, [string]$Status, [string]$Details) {
    $checks.Add([pscustomobject]@{ name = $Name; status = $Status; details = $Details })
    Write-Output ("[{0}] {1}: {2}" -f $Status, $Name, $Details)
}

function Assert-PathInside([string]$Path, [string]$Root, [string]$Description) {
    $fullPath = [IO.Path]::GetFullPath($Path)
    $fullRoot = [IO.Path]::GetFullPath($Root).TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
    if (-not $fullPath.StartsWith($fullRoot, [StringComparison]::OrdinalIgnoreCase)) {
        throw "$Description escaped the extracted package folder: $fullPath"
    }
    return $fullPath
}

function Assert-ValidPng([string]$Path, [string]$Description, [int]$MinimumWidth = 1, [int]$MinimumHeight = 1) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "$Description is missing: $Path" }
    $bytes = [IO.File]::ReadAllBytes($Path)
    $signature = [byte[]](137, 80, 78, 71, 13, 10, 26, 10)
    if ($bytes.Length -lt 64) { throw "$Description is empty or too small to be a valid PNG: $Path" }
    for ($i = 0; $i -lt $signature.Length; $i++) {
        if ($bytes[$i] -ne $signature[$i]) { throw "$Description is not a PNG file: $Path" }
    }
    $image = [System.Drawing.Image]::FromFile($Path)
    try {
        if ($image.Width -lt $MinimumWidth -or $image.Height -lt $MinimumHeight) { throw "$Description has implausible dimensions ($($image.Width)x$($image.Height)): $Path" }
    } finally { $image.Dispose() }
}

function Get-Sha256([string]$Path) {
    $sha256 = [Security.Cryptography.SHA256]::Create()
    $stream = [IO.File]::OpenRead($Path)
    try { return ([BitConverter]::ToString($sha256.ComputeHash($stream))).Replace('-', '').ToLowerInvariant() }
    finally { $stream.Dispose(); $sha256.Dispose() }
}

function Invoke-Editor([string[]]$Arguments, [string]$WorkingDirectory, [string]$Name) {
    $stdout = Join-Path $testRoot ($Name + '.stdout.txt')
    $stderr = Join-Path $testRoot ($Name + '.stderr.txt')
    $argumentLine = ($Arguments | ForEach-Object { '"' + $_.Replace('"', '\"') + '"' }) -join ' '
    $startInfo = New-Object System.Diagnostics.ProcessStartInfo
    $startInfo.FileName = $script:editorPath
    $startInfo.Arguments = $argumentLine
    $startInfo.WorkingDirectory = $WorkingDirectory
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $startInfo.StandardOutputEncoding = New-Object System.Text.UTF8Encoding($false)
    $startInfo.StandardErrorEncoding = New-Object System.Text.UTF8Encoding($false)
    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $startInfo
    try { [void]$process.Start() }
    catch { return [pscustomobject]@{ timedOut = $false; exitCode = $null; stdout = ''; stderr = ''; launchError = $_.Exception.Message } }
    $stdoutTask = $process.StandardOutput.ReadToEndAsync()
    $stderrTask = $process.StandardError.ReadToEndAsync()
    if (-not $process.WaitForExit($script:TimeoutSeconds * 1000)) {
        try { $process.Kill() } catch { }
        return [pscustomobject]@{ timedOut = $true; exitCode = $null; stdout = ''; stderr = ''; launchError = $null }
    }
    $process.WaitForExit()
    [IO.File]::WriteAllText($stdout, $stdoutTask.Result, (New-Object System.Text.UTF8Encoding($false)))
    [IO.File]::WriteAllText($stderr, $stderrTask.Result, (New-Object System.Text.UTF8Encoding($false)))
    return [pscustomobject]@{
        timedOut = $false
        exitCode = $process.ExitCode
        stdout = $stdoutTask.Result
        stderr = $stderrTask.Result
        launchError = $null
    }
}

try {
    Expand-Archive -LiteralPath $packageFullPath -DestinationPath $testRoot -Force
    $script:editorPath = Join-Path $testRoot 'BeltScrollEditor.exe'
    if (-not (Test-Path -LiteralPath $script:editorPath -PathType Leaf)) { throw 'ZIP does not contain BeltScrollEditor.exe at its root.' }
    $readmePath = Join-Path $testRoot 'README.txt'
    $sumsPath = Join-Path $testRoot 'SHA256SUMS.txt'
    if (-not (Test-Path -LiteralPath $readmePath) -or -not (Test-Path -LiteralPath $sumsPath)) { throw 'ZIP is missing README.txt or SHA256SUMS.txt.' }
    $actualHash = Get-Sha256 $script:editorPath
    $expectedHash = ((Get-Content -Encoding UTF8 -Raw -LiteralPath $sumsPath) -split '\s+')[0].ToLowerInvariant()
    if ($actualHash -ne $expectedHash) { throw 'Packaged executable SHA-256 does not match SHA256SUMS.txt.' }
    Add-Check 'ZIP extraction and SHA-256' 'PASS' ("Extracted outside project to $testRoot; hash=$actualHash")

    $self = Invoke-Editor @('--self-test') $testRoot 'self-test'
    if ($self.timedOut -or $self.exitCode -ne 0) { throw "Extracted EXE --self-test failed (timedOut=$($self.timedOut), exit=$($self.exitCode)); $($self.stderr)" }
    Add-Check '--self-test' 'PASS' ($self.stdout.Trim())

    $guiStatus = 'PASS'
    $guiDetails = New-Object System.Collections.Generic.List[string]
    try {
        $numeric = Invoke-Editor @('--gui-acceptance', $testRoot) $testRoot 'numeric-editor-acceptance'
        $numericReportPath = Join-Path $testRoot 'gui-acceptance.json'
        if ($numeric.launchError) { throw "GUI_UNAVAILABLE: numeric acceptance process could not start: $($numeric.launchError)" }
        if ($numeric.timedOut -or $numeric.exitCode -ne 0 -or -not (Test-Path -LiteralPath $numericReportPath)) { throw "Numeric editor acceptance failed (timedOut=$($numeric.timedOut), exit=$($numeric.exitCode)): $($numeric.stderr)" }
        $numericReport = Get-Content -Encoding UTF8 -Raw -LiteralPath $numericReportPath | ConvertFrom-Json
        if (-not $numericReport.passed -or -not (Test-Path -LiteralPath ([string]$numericReport.output) -PathType Leaf)) { throw 'Numeric editor acceptance report or saved data is missing/failed.' }
        $guiDetails.Add('numeric edit, save, reopen, and file output passed')

        $animationDir = Join-Path $testRoot 'animation-acceptance'
        [void][IO.Directory]::CreateDirectory($animationDir)
        $animation = Invoke-Editor @('--animation-gui-acceptance', $animationDir) $testRoot 'animation-workspace-acceptance'
        $animationReportPath = Join-Path $animationDir 'animation-gui-acceptance.json'
        if ($animation.launchError) { throw "GUI_UNAVAILABLE: animation acceptance process could not start: $($animation.launchError)" }
        if ($animation.timedOut -or $animation.exitCode -ne 0 -or -not (Test-Path -LiteralPath $animationReportPath)) { throw "Animation workspace acceptance failed (timedOut=$($animation.timedOut), exit=$($animation.exitCode)): $($animation.stderr)" }
        $animationReport = Get-Content -Encoding UTF8 -Raw -LiteralPath $animationReportPath | ConvertFrom-Json
        if (-not $animationReport.passed) { throw "Animation workspace acceptance report marked failure: $($animationReport.error)" }
        if ($animationReport.schemaVersion -ne 1 -or $animationReport.clipCount -ne 11 -or $animationReport.frameCount -ne 4) { throw "Animation workspace did not report schema v1 with 11 clips and four attack frames (schema=$($animationReport.schemaVersion), clips=$($animationReport.clipCount), attack frames=$($animationReport.frameCount))." }
        $exportPath = Assert-PathInside ([string]$animationReport.exportedPath) $animationDir 'Animation JSON export'
        if (-not (Test-Path -LiteralPath $exportPath -PathType Leaf)) { throw "Animation JSON export is missing: $exportPath" }
        $exported = Get-Content -Encoding UTF8 -Raw -LiteralPath $exportPath | ConvertFrom-Json
        if ($exported.schema_version -ne 1) { throw "Animation JSON schema_version is $($exported.schema_version), expected 1." }
        $expectedClipIds = @('idle', 'attack1', 'attack2', 'attack3', 'run', 'turn', 'jump_rise', 'jump_fall', 'hit', 'skill1', 'skill2')
        $actualClipIds = @($exported.clips | ForEach-Object { [string]$_.id } | Sort-Object)
        if ($actualClipIds.Count -ne 11 -or (($actualClipIds -join ',') -ne (($expectedClipIds | Sort-Object) -join ','))) { throw "Animation JSON clip IDs do not match schema v1: $($actualClipIds -join ',')." }
        foreach ($clip in $exported.clips) {
            if (@($clip.frames).Count -lt 1) { throw "Animation JSON clip '$($clip.id)' has no frames." }
            foreach ($frame in $clip.frames) {
                if ([string]::IsNullOrWhiteSpace([string]$frame.texture)) { throw "Animation JSON clip '$($clip.id)' contains a frame without a texture path." }
                $texturePath = [IO.Path]::GetFullPath((Join-Path (Split-Path -Parent $exportPath) ([string]$frame.texture)))
                [void](Assert-PathInside $texturePath $animationDir 'Animation texture')
                if (-not (Test-Path -LiteralPath $texturePath -PathType Leaf)) { throw "Animation JSON texture is missing: $texturePath" }
                Assert-ValidPng $texturePath "Animation texture for '$($clip.id)'"
            }
        }
        $attack = @($exported.clips | Where-Object { $_.id -eq 'attack1' })[0]
        $expectedAttackPhases = @('startup', 'inbetween', 'contact', 'recovery')
        $actualAttackPhases = @($attack.frames | ForEach-Object { [string]$_.phase })
        if ($attack.frames.Count -ne 4 -or (($actualAttackPhases -join ',') -ne ($expectedAttackPhases -join ','))) { throw "attack1 JSON frames must be startup/inbetween/contact/recovery in order; found: $($actualAttackPhases -join ',')." }
        foreach ($capture in @('animation-gui.png', 'comparison-side-by-side.png', 'comparison-overlay.png', 'comparison-zoom.png', 'comparison-pan.png')) {
            Assert-ValidPng (Join-Path $animationDir $capture) "Actual GUI PNG capture '$capture'" 320 240
        }
        $guiDetails.Add('schema v1 11-clip export, four attack phases, texture PNGs, and decoded actual GUI captures passed')
    } catch {
        if (-not $AllowGuiUnverified -or $_.Exception.Message -notlike 'GUI_UNAVAILABLE:*') { throw }
        $guiStatus = 'UNVERIFIED'
        $guiDetails.Clear()
        $guiDetails.Add(('GUI-dependent acceptance unavailable in this CI environment: ' + $_.Exception.Message))
    }
    Add-Check 'numeric editor and animation workspace' $guiStatus ($guiDetails -join '; ')

    $summary = [pscustomobject]@{
        package = $packageFullPath
        extractedExecutable = $script:editorPath
        extractedOutsideProject = $true
        executableSha256 = $actualHash
        checks = $checks.ToArray()
        passed = (@($checks.ToArray() | Where-Object { $_.status -eq 'FAIL' }).Count -eq 0)
    } | ConvertTo-Json -Depth 6
    [IO.File]::WriteAllText($reportPath, $summary, (New-Object System.Text.UTF8Encoding($false)))
    Write-Host "Smoke report: $reportPath"
} catch {
    Add-Check 'release package smoke' 'FAIL' $_.Exception.Message
    $summary = [pscustomobject]@{ package = $packageFullPath; checks = $checks.ToArray(); passed = $false } | ConvertTo-Json -Depth 6
    [IO.File]::WriteAllText($reportPath, $summary, (New-Object System.Text.UTF8Encoding($false)))
    throw
}
