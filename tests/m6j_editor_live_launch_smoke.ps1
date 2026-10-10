param(
    [string]$EditorPath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'dist\BeltScrollEditor.exe'),
    [string]$GodotPath = 'C:\Project\Godot\godot.exe',
    [int]$TimeoutSeconds = 180
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
[Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)
$projectRoot = Split-Path -Parent $PSScriptRoot
$editor = [IO.Path]::GetFullPath($EditorPath)
$godot = [IO.Path]::GetFullPath($GodotPath)
if (-not (Test-Path -LiteralPath $editor -PathType Leaf)) { throw "Editor executable not found: $editor" }
if (-not (Test-Path -LiteralPath $godot -PathType Leaf) -or [IO.Path]::GetExtension($godot) -ine '.exe' -or [IO.Path]::GetFileName($godot) -notlike 'godot*.exe') { throw "Godot executable path is invalid: $godot" }

$artifactDir = Join-Path ([IO.Path]::GetTempPath()) ('BeltScrollM6JLiveLaunch_' + [Guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($artifactDir)
$stdoutPath = Join-Path $artifactDir 'editor.stdout.txt'
$stderrPath = Join-Path $artifactDir 'editor.stderr.txt'
$reportPath = Join-Path $artifactDir 'playtest-gui-acceptance.json'
$exitPath = Join-Path $artifactDir 'exit-code.txt'
$editorProcess = $null
$failure = $null
$passed = $false
try {
    $startInfo = New-Object System.Diagnostics.ProcessStartInfo
    $startInfo.FileName = $editor
    $startInfo.Arguments = '--playtest-gui-acceptance "{0}" --godot "{1}" --project-root "{2}"' -f $artifactDir, $godot, $projectRoot
    $startInfo.WorkingDirectory = $projectRoot
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $false
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $startInfo.StandardOutputEncoding = New-Object System.Text.UTF8Encoding($false)
    $startInfo.StandardErrorEncoding = New-Object System.Text.UTF8Encoding($false)
    $editorProcess = New-Object System.Diagnostics.Process
    $editorProcess.StartInfo = $startInfo
    if (-not $editorProcess.Start()) { throw 'WinForms editor process did not start.' }
    $stdoutTask = $editorProcess.StandardOutput.ReadToEndAsync()
    $stderrTask = $editorProcess.StandardError.ReadToEndAsync()
    if (-not $editorProcess.WaitForExit($TimeoutSeconds * 1000)) {
        try { $editorProcess.Kill() } catch { }
        throw "Automated live launch acceptance timed out after $TimeoutSeconds seconds."
    }
    $stdout = if ($stdoutTask.IsCompleted) { $stdoutTask.Result } else { '' }
    $stderr = if ($stderrTask.IsCompleted) { $stderrTask.Result } else { '' }
    [IO.File]::WriteAllText($stdoutPath, $stdout, (New-Object System.Text.UTF8Encoding($false)))
    [IO.File]::WriteAllText($stderrPath, $stderr, (New-Object System.Text.UTF8Encoding($false)))
    $editorProcess.Refresh()
    if ($editorProcess.ExitCode -ne 0) { throw "Automated GUI live launch failed with editor exit code $($editorProcess.ExitCode)." }
    if (-not (Test-Path -LiteralPath $reportPath -PathType Leaf)) { throw 'Automated GUI acceptance report was not created.' }
    $report = Get-Content -Encoding UTF8 -Raw -LiteralPath $reportPath | ConvertFrom-Json
    if (-not $report.passed -or $report.verificationClass -ne 'automated_gui' -or $report.actualOsMouseInput -ne $false -or $report.humanInputReview -ne 'not_performed') { throw 'GUI acceptance report did not preserve automated/human verification separation.' }
    if ($report.savedValues.PlayerMaxHealth -ne 11 -or $report.savedValues.ForestRaiderMaxHealth -ne 23 -or $report.unsavedPlayerMaxHealth -ne 77 -or -not $report.runtimeActorValuesVerified) { throw 'Saved-versus-unsaved fixture values were not applied to the live Player/ForestRaider instances.' }
    if (-not $report.temporaryWorkspaceCleaned -or $report.processExitCode -ne 0) { throw 'A playtest process did not exit cleanly or its temporary project was not removed.' }
    if (-not (Test-Path -LiteralPath (Join-Path $artifactDir 'gui-capture.png') -PathType Leaf)) { throw 'Automated GUI capture was not created.' }
    $passed = $true
} catch {
    $failure = $_.Exception.Message
} finally {
    if ($editorProcess) {
        try {
            if (-not $editorProcess.HasExited) { $editorProcess.Kill(); [void]$editorProcess.WaitForExit(5000) }
            $editorProcess.Dispose()
        } catch { }
    }
    $summary = [ordered]@{
        gate = 'M6J WinForms button to live Godot process/window/exit verification'
        verificationClass = 'automated_gui'
        passed = $passed
        failure = $failure
        editorPath = $editor
        godotPath = $godot
        projectRoot = $projectRoot
        actualOsMouseInput = $false
        humanInputReview = 'not_performed'
        acceptanceReport = $reportPath
        artifacts = $artifactDir
    }
    [IO.File]::WriteAllText((Join-Path $artifactDir 'm6j-live-launch-summary.json'), ($summary | ConvertTo-Json -Depth 8), (New-Object System.Text.UTF8Encoding($false)))
    [IO.File]::WriteAllText($exitPath, $(if ($passed) { '0' } else { '1' }) + [Environment]::NewLine, (New-Object System.Text.UTF8Encoding($false)))
}

Write-Output ("Automated GUI launch result: {0}" -f $passed)
Write-Output ("Human mouse/keyboard review: not performed")
Write-Output ("Artifacts: {0}" -f $artifactDir)
if (-not $passed) { throw $failure }
