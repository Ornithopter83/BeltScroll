param(
    [string]$EditorPath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'dist\BeltScrollEditor.exe'),
    [string]$GodotPath = 'C:\Project\Godot\godot.exe',
    [int]$TimeoutSeconds = 120
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
[Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)
$projectRoot = Split-Path -Parent $PSScriptRoot
$resolvedEditor = [IO.Path]::GetFullPath($EditorPath)
$resolvedGodot = [IO.Path]::GetFullPath($GodotPath)
$artifactDir = Join-Path ([IO.Path]::GetTempPath()) ('BeltScrollAnimationBankRoundtrip_' + [Guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($artifactDir)

function Quote-Argument([string]$Value) {
    return '"' + $Value.Replace('"', '\"') + '"'
}

function Invoke-Captured([string]$FilePath, [string]$Arguments, [string]$WorkingDirectory, [string]$Name) {
    $info = New-Object System.Diagnostics.ProcessStartInfo
    $info.FileName = $FilePath
    $info.Arguments = $Arguments
    $info.WorkingDirectory = $WorkingDirectory
    $info.UseShellExecute = $false
    $info.CreateNoWindow = $true
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    $info.StandardOutputEncoding = New-Object System.Text.UTF8Encoding($false)
    $info.StandardErrorEncoding = New-Object System.Text.UTF8Encoding($false)
    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $info
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
    [IO.File]::WriteAllText((Join-Path $artifactDir ($Name + '.stdout.txt')), $stdout, (New-Object System.Text.UTF8Encoding($false)))
    [IO.File]::WriteAllText((Join-Path $artifactDir ($Name + '.stderr.txt')), $stderr, (New-Object System.Text.UTF8Encoding($false)))
    $process.Refresh()
    $result = [pscustomobject]@{ TimedOut = $timedOut; ExitCode = $(if ($timedOut) { $null } else { [int]$process.ExitCode }) }
    $process.Dispose()
    return $result
}

try {
    if (-not (Test-Path -LiteralPath $resolvedEditor -PathType Leaf)) { throw "Editor EXE not found: $resolvedEditor" }
    if (-not (Test-Path -LiteralPath $resolvedGodot -PathType Leaf)) { throw "Godot executable not found: $resolvedGodot" }

    $editorArgs = '--animation-gui-acceptance ' + (Quote-Argument $artifactDir)
    $editorResult = Invoke-Captured $resolvedEditor $editorArgs $artifactDir 'editor'
    if ($editorResult.TimedOut -or $editorResult.ExitCode -ne 0) { throw "Animation editor EXE failed (exit=$($editorResult.ExitCode))." }
    $reportPath = Join-Path $artifactDir 'animation-gui-acceptance.json'
    if (-not (Test-Path -LiteralPath $reportPath -PathType Leaf)) { throw 'Animation editor EXE did not produce its acceptance report.' }
    $report = Get-Content -Encoding UTF8 -Raw -LiteralPath $reportPath | ConvertFrom-Json
    if (-not $report.passed -or -not (Test-Path -LiteralPath $report.exportedPath -PathType Leaf)) { throw 'Animation editor EXE did not export its JSON fixture.' }
    $exportPath = [IO.Path]::GetFullPath([string]$report.exportedPath)
    $exportRoot = [IO.Path]::GetDirectoryName($exportPath)
    if (-not $exportPath.StartsWith($artifactDir, [StringComparison]::OrdinalIgnoreCase)) { throw 'Editor export unexpectedly escaped the temporary test folder.' }

    # This uses the JSON and relative texture file emitted by the real EXE.
    # The Godot script parses schema v1, then verifies that its generated approved
    # image is rejected by the runtime byte allowlist.
    $godotArgs = '--headless --path ' + (Quote-Argument $projectRoot) + ' --script res://tests/player_animation_bank_smoke.gd -- --exported-manifest ' + (Quote-Argument $exportPath)
    $godotResult = Invoke-Captured $resolvedGodot $godotArgs $projectRoot 'godot'
    if ($godotResult.TimedOut -or $godotResult.ExitCode -ne 0) { throw "Godot rejected or mishandled the actual editor export (exit=$($godotResult.ExitCode))." }

    Write-Output 'Editor EXE to Godot animation schema v1 roundtrip passed.'
    Write-Output ("Exported manifest: {0}" -f $exportPath)
    Write-Output ("Temporary artifacts: {0}" -f $artifactDir)
} catch {
    Write-Error ("Animation bank roundtrip failed: {0}`nArtifacts: {1}" -f $_.Exception.Message, $artifactDir)
    exit 1
}
