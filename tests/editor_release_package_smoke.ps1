param(
    [Parameter(Mandatory = $true)]
    [string]$PackagePath,
    [switch]$AllowGuiUnverified,
    [int]$TimeoutSeconds = 120
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$OutputEncoding = [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)
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
    $actualHash = (Get-FileHash -LiteralPath $script:editorPath -Algorithm SHA256).Hash.ToLowerInvariant()
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
        if (-not $animationReport.passed -or $animationReport.clipCount -ne 4 -or $animationReport.frameCount -ne 4 -or -not (Test-Path -LiteralPath ([string]$animationReport.exportedPath) -PathType Leaf) -or -not (Test-Path -LiteralPath (Join-Path $animationDir 'animation-gui.png') -PathType Leaf)) { throw 'Animation workspace report, exported JSON, or capture is missing/failed.' }
        $guiDetails.Add('animation workspace edit, JSON/texture export, and reload passed')
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
