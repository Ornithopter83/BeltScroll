param(
    [string]$EditorPath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'dist\BeltScrollEditor.exe'),
    [int]$TimeoutSeconds = 300
)

$ErrorActionPreference = 'Stop'
$utf8 = New-Object System.Text.UTF8Encoding($false)
[Console]::OutputEncoding = $utf8
$root = Split-Path -Parent $PSScriptRoot
$smokePath = Join-Path $PSScriptRoot 'editor_executable_smoke.ps1'
$editorFullPath = [IO.Path]::GetFullPath($EditorPath)
if (-not (Test-Path -LiteralPath $editorFullPath -PathType Leaf)) { throw "Editor executable not found: $editorFullPath" }

function Quote-Argument([string]$Value) {
    return '"' + $Value.Replace('"', '\"') + '"'
}

function Invoke-SmokeMode([string]$Mode, [bool]$Automated) {
    $work = Join-Path ([IO.Path]::GetTempPath()) ('BeltScrollEditorMode_' + $Mode + '_' + [Guid]::NewGuid().ToString('N'))
    [void][IO.Directory]::CreateDirectory($work)
    $stdout = Join-Path $work 'stdout.txt'
    $stderr = Join-Path $work 'stderr.txt'
    $arguments = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $smokePath, '-EditorPath', $editorFullPath, '-SelfTestTimeoutSeconds', '120')
    if ($Automated) { $arguments += '-AutomatedOnly' }
    $info = New-Object System.Diagnostics.ProcessStartInfo
    $info.FileName = Join-Path $PSHOME 'powershell.exe'
    $info.Arguments = (@($arguments | ForEach-Object { Quote-Argument ([string]$_) }) -join ' ')
    $info.WorkingDirectory = $root
    $info.UseShellExecute = $false
    $info.CreateNoWindow = $true
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    $info.StandardOutputEncoding = $utf8
    $info.StandardErrorEncoding = $utf8
    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $info
    if (-not $process.Start()) { throw "Could not start $Mode smoke process." }
    $outTask = $process.StandardOutput.ReadToEndAsync()
    $errTask = $process.StandardError.ReadToEndAsync()
    if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
        try { $process.Kill() } catch { }
        throw "$Mode smoke timed out. Logs: $work"
    }
    [IO.File]::WriteAllText($stdout, $outTask.GetAwaiter().GetResult(), $utf8)
    [IO.File]::WriteAllText($stderr, $errTask.GetAwaiter().GetResult(), $utf8)
    $output = Get-Content -Encoding UTF8 -Raw -LiteralPath $stdout
    $match = [regex]::Match($output, '(?m)^보고서:\s*(.+?)\s*$')
    if (-not $match.Success) { throw "$Mode smoke did not report its JSON path. Exit=$($process.ExitCode); Logs: $work`n$output`n$(Get-Content -Encoding UTF8 -Raw -LiteralPath $stderr)" }
    $reportPath = $match.Groups[1].Value.Trim()
    if (-not (Test-Path -LiteralPath $reportPath -PathType Leaf)) { throw "$Mode report missing: $reportPath" }
    $report = Get-Content -Encoding UTF8 -Raw -LiteralPath $reportPath | ConvertFrom-Json
    return [pscustomobject]@{ Mode = $Mode; ExitCode = $process.ExitCode; Work = $work; Output = $output; Report = $report; ReportPath = $reportPath }
}

$automated = Invoke-SmokeMode 'automated' $true
if ($automated.ExitCode -ne 0 -or -not $automated.Report.passed -or $automated.Report.mode -ne 'AutomatedOnly' -or
    $automated.Report.automated_status -ne 'passed' -or $automated.Report.manual_status -ne 'blocked_unverified' -or
    $automated.Report.status -ne 'blocked_unverified' -or $automated.Report.editorPath -ne $editorFullPath) {
    throw "AutomatedOnly outcome/report mismatch. Exit=$($automated.ExitCode); report=$($automated.ReportPath); logs=$($automated.Work)"
}
$autoChecks = @($automated.Report.results | Where-Object { $_.category -eq 'automated' })
if (@($autoChecks | Where-Object { -not $_.passed }).Count -gt 0 -or @($autoChecks | Where-Object { $_.check -eq '--self-test 완료' }).Count -ne 1 -or
    @($autoChecks | Where-Object { $_.check -eq '--gui-acceptance 완료' }).Count -ne 1) {
    throw "Automated checks were not fully recorded as passed. Report: $($automated.ReportPath)"
}
$manualChecks = @($automated.Report.results | Where-Object { $_.category -eq 'manual' })
$invalidManualChecks = @($manualChecks | Where-Object { $_.passed -or ($_.details -notmatch '미검증') })
if ($invalidManualChecks.Count -gt 0) {
    throw "AutomatedOnly incorrectly claimed manual verification. Report: $($automated.ReportPath)"
}
$autoGuiPath = Join-Path $automated.Report.externalWorkingDirectory 'gui-acceptance.json'
$autoSavedPath = Join-Path $automated.Report.externalWorkingDirectory 'overrides.json'
$autoBackupPath = $autoSavedPath + '.bak'
if (-not (Test-Path -LiteralPath $autoGuiPath) -or -not (Test-Path -LiteralPath $autoSavedPath) -or -not (Test-Path -LiteralPath $autoBackupPath)) {
    throw "GUI JSON roundtrip/save recovery artifacts missing. Report: $($automated.ReportPath)"
}
$guiReport = Get-Content -Encoding UTF8 -Raw -LiteralPath $autoGuiPath | ConvertFrom-Json
$saved = Get-Content -Encoding UTF8 -Raw -LiteralPath $autoSavedPath | ConvertFrom-Json
$player = @($saved.characters | Where-Object { $_.id -eq 'Player' })[0]
if (-not $guiReport.passed -or $guiReport.actualOsMouseInput -ne $false -or $guiReport.workingDirectory -ne $automated.Report.externalWorkingDirectory -or
    $guiReport.output -ne $autoSavedPath -or $null -eq $player -or [int]$player.max_health -ne 6) {
    throw "GUI acceptance JSON roundtrip or truthful automation metadata invalid. Report: $autoGuiPath"
}

$manual = Invoke-SmokeMode 'manual' $false
if ($manual.ExitCode -ne 2 -or $manual.Report.mode -ne 'ManualAcceptance' -or $manual.Report.automated_status -ne 'passed' -or
    $manual.Report.manual_status -ne 'blocked_unverified' -or $manual.Report.status -ne 'blocked_unverified' -or $manual.Report.passed -or
    $manual.Report.editorPath -ne $editorFullPath) {
    throw "Manual blocked outcome/report mismatch. Exit=$($manual.ExitCode); report=$($manual.ReportPath); logs=$($manual.Work)"
}
$invalidBlockedChecks = @($manual.Report.results | Where-Object { $_.category -eq 'manual' } | Where-Object { $_.passed -or ($_.details -notmatch '차단됨') })
if ($invalidBlockedChecks.Count -gt 0) {
    throw "Manual mode reported an unverified action as approved. Report: $($manual.ReportPath)"
}
Write-Output "editor_executable_modes_smoke: PASS (PowerShell $($PSVersionTable.PSVersion)); automated exit=0/manual_status=blocked_unverified; manual exit=2/manual_status=blocked_unverified; EXE=$editorFullPath"
Write-Output "Automated report: $($automated.ReportPath)"
Write-Output "Manual report: $($manual.ReportPath)"
exit 0
