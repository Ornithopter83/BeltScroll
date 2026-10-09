param(
    [string]$EditorPath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'dist\BeltScrollEditor.exe'),
    [string]$GodotPath = 'C:\Project\Godot\godot.exe',
    [int]$TimeoutSeconds = 120
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
[Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)
$projectRoot = Split-Path -Parent $PSScriptRoot
$overridesPath = Join-Path $projectRoot 'data\editor\overrides.json'
$resolvedEditor = [IO.Path]::GetFullPath($EditorPath)
$resolvedGodot = [IO.Path]::GetFullPath($GodotPath)
$artifactDir = Join-Path ([IO.Path]::GetTempPath()) ('BeltScrollEditorGameBridge_' + [Guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($artifactDir)
$backupPath = Join-Path $artifactDir 'original-overrides.json'
$guiExitCode = $null
$gameExitCode = $null
$restoreExitCode = 1
$originalSha256 = $null
$restoredSha256 = $null
$guiPassed = $false
$gamePassed = $false
$restorePassed = $false
$failure = $null
$hadOriginal = Test-Path -LiteralPath $overridesPath -PathType Leaf

function Write-Utf8([string]$Path, [string]$Content) {
    [IO.File]::WriteAllText($Path, $Content, (New-Object System.Text.UTF8Encoding($false)))
}

function Invoke-CapturedProcess([string]$FilePath, [string]$ArgumentLine, [string]$WorkingDirectory, [string]$StdoutPath, [string]$StderrPath) {
    $startInfo = New-Object System.Diagnostics.ProcessStartInfo
    $startInfo.FileName = $FilePath
    $startInfo.Arguments = $ArgumentLine
    $startInfo.WorkingDirectory = $WorkingDirectory
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $false
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $startInfo.StandardOutputEncoding = New-Object System.Text.UTF8Encoding($false)
    $startInfo.StandardErrorEncoding = New-Object System.Text.UTF8Encoding($false)
    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $startInfo
    [void]$process.Start()
    $stdoutTask = $process.StandardOutput.ReadToEndAsync()
    $stderrTask = $process.StandardError.ReadToEndAsync()
    $timedOut = -not $process.WaitForExit($TimeoutSeconds * 1000)
    if ($timedOut) {
        try { $process.Kill() } catch { }
        try { $process.WaitForExit(10000) } catch { }
    }
    $stdout = if ($stdoutTask.IsCompleted) { $stdoutTask.Result } else { '' }
    $stderr = if ($stderrTask.IsCompleted) { $stderrTask.Result } else { '' }
    Write-Utf8 $StdoutPath $stdout
    Write-Utf8 $StderrPath $stderr
    $process.Refresh()
    $exitCode = if ($timedOut) { $null } else { [int]$process.ExitCode }
    $processId = $process.Id
    $process.Dispose()
    return [pscustomobject]@{ TimedOut = $timedOut; ExitCode = $exitCode; ProcessId = $processId }
}

try {
    if (-not $hadOriginal) { throw "Required project override file not found: $overridesPath" }
    if (-not (Test-Path -LiteralPath $resolvedEditor -PathType Leaf)) { throw "Editor EXE not found: $resolvedEditor" }
    if (-not (Test-Path -LiteralPath $resolvedGodot -PathType Leaf)) { throw "Godot executable not found: $resolvedGodot" }
    [IO.File]::Copy($overridesPath, $backupPath, $false)
    $originalSha256 = (Get-FileHash -LiteralPath $backupPath -Algorithm SHA256).Hash.ToLowerInvariant()

    $sourceFixture = Join-Path $artifactDir 'source-overrides.json'
    [IO.File]::Copy($backupPath, $sourceFixture, $false)
    $guiStdout = Join-Path $artifactDir 'gui.stdout.txt'
    $guiStderr = Join-Path $artifactDir 'gui.stderr.txt'
    $guiArguments = '--gui-acceptance "{0}" --runtime-roundtrip' -f $artifactDir
    $guiProcess = Invoke-CapturedProcess $resolvedEditor $guiArguments $artifactDir $guiStdout $guiStderr
    $guiExitCode = $guiProcess.ExitCode
    Write-Utf8 (Join-Path $artifactDir 'gui-exit-code.txt') $(if ($null -ne $guiExitCode) { [string]$guiExitCode } else { 'timeout' })
    $guiReportPath = Join-Path $artifactDir 'gui-acceptance.json'
    if (Test-Path -LiteralPath $guiReportPath -PathType Leaf) {
        $guiReport = Get-Content -Encoding UTF8 -Raw -LiteralPath $guiReportPath | ConvertFrom-Json
        $guiPassed = (-not $guiProcess.TimedOut) -and $guiExitCode -eq 0 -and $guiReport.passed -and (Test-Path -LiteralPath (Join-Path $artifactDir 'gui-capture.png') -PathType Leaf)
    }
    if (-not $guiPassed) { throw "GUI acceptance failed or did not produce its report/capture (exit=$guiExitCode)." }

    $editedOutput = Join-Path $artifactDir 'overrides.json'
    if (-not (Test-Path -LiteralPath $editedOutput -PathType Leaf)) { throw 'GUI did not save overrides.json.' }
    [IO.File]::Copy($editedOutput, $overridesPath, $true)
    $gameStdout = Join-Path $artifactDir 'game.stdout.txt'
    $gameStderr = Join-Path $artifactDir 'game.stderr.txt'
    $probePath = 'res://tools/probe_editor_live_scene.gd'
    $gameArguments = '--path "{0}" --script "{1}" -- --artifact-dir "{2}"' -f $projectRoot, $probePath, $artifactDir
    $gameProcess = Invoke-CapturedProcess $resolvedGodot $gameArguments $projectRoot $gameStdout $gameStderr
    $gameExitCode = $gameProcess.ExitCode
    Write-Utf8 (Join-Path $artifactDir 'game-exit-code.txt') $(if ($null -ne $gameExitCode) { [string]$gameExitCode } else { 'timeout' })
    $applicationReportPath = Join-Path $artifactDir 'game-application.json'
    if (Test-Path -LiteralPath $applicationReportPath -PathType Leaf) {
        $applicationReport = Get-Content -Encoding UTF8 -Raw -LiteralPath $applicationReportPath | ConvertFrom-Json
        $gamePassed = (-not $gameProcess.TimedOut) -and $gameExitCode -eq 0 -and $applicationReport.passed -and (Test-Path -LiteralPath (Join-Path $artifactDir 'game-live-scene.png') -PathType Leaf)
    }
    if (-not $gamePassed) { throw "Godot live-scene probe failed or did not produce its report/capture (exit=$gameExitCode)." }
} catch {
    $failure = $_.Exception.Message
} finally {
    try {
        if ($hadOriginal -and (Test-Path -LiteralPath $backupPath -PathType Leaf)) {
            [IO.File]::Copy($backupPath, $overridesPath, $true)
            $restoredSha256 = (Get-FileHash -LiteralPath $overridesPath -Algorithm SHA256).Hash.ToLowerInvariant()
            $restorePassed = ($restoredSha256 -eq $originalSha256)
            $restoreExitCode = if ($restorePassed) { 0 } else { 1 }
        }
    } catch {
        $failure = if ($failure) { $failure + '; restore failed: ' + $_.Exception.Message } else { 'restore failed: ' + $_.Exception.Message }
    }
    Write-Utf8 (Join-Path $artifactDir 'restore-exit-code.txt') ([string]$restoreExitCode)
    $passed = $guiPassed -and $gamePassed -and $restorePassed
    $report = [ordered]@{
        product = 'BeltScrollEditor'
        gate = 'independent GUI editor to restarted Godot combat scene roundtrip'
        passed = $passed
        failure = $failure
        projectRoot = $projectRoot
        editorPath = $resolvedEditor
        godotPath = $resolvedGodot
        actualOsMouseInput = $false
        uiAutomation = 'visible WinForms GUI message loop; form controls invoked by --gui-acceptance'
        originalOverridesPath = $overridesPath
        temporaryBackup = $backupPath
        originalSha256 = $originalSha256
        restoredSha256 = $restoredSha256
        guiAcceptance = @{ passed = $guiPassed; exitCode = $guiExitCode; report = (Join-Path $artifactDir 'gui-acceptance.json'); screenshot = (Join-Path $artifactDir 'gui-capture.png') }
        gameApplication = @{ passed = $gamePassed; exitCode = $gameExitCode; report = (Join-Path $artifactDir 'game-application.json'); screenshot = (Join-Path $artifactDir 'game-live-scene.png') }
        restoration = @{ passed = $restorePassed; exitCode = $restoreExitCode; sha256Matches = ($restoredSha256 -eq $originalSha256) }
        artifacts = $artifactDir
    }
    Write-Utf8 (Join-Path $artifactDir 'editor-game-bridge-report.json') ($report | ConvertTo-Json -Depth 8)
    Write-Utf8 (Join-Path $artifactDir 'exit-code.txt') $(if ($passed) { '0' } else { '1' })
}

Write-Output ("GUI result: {0} (exit={1})" -f $guiPassed, $guiExitCode)
Write-Output ("Game result: {0} (exit={1})" -f $gamePassed, $gameExitCode)
Write-Output ("Original overrides SHA256: {0}" -f $originalSha256)
Write-Output ("Restored overrides SHA256: {0}" -f $restoredSha256)
Write-Output ("Artifacts: {0}" -f $artifactDir)
if (-not ($guiPassed -and $gamePassed -and $restorePassed)) { exit 1 }
exit 0
