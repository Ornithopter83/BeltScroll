[CmdletBinding()]
param(
    [ValidateSet('Headless','Window','Both')]
    [string]$Mode = 'Both',
    [string]$ProjectRoot = '',
    [string]$GodotPath = '',
    [int]$ImportTimeoutSeconds = 300,
    [int]$HeadlessTimeoutSeconds = 45,
    [int]$WindowTimeoutSeconds = 60,
    [ValidateRange(2,10)]
    [int]$Repeats = 2,
    [string]$OutputDirectory = ''
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$utf8 = New-Object System.Text.UTF8Encoding($false)
[Console]::OutputEncoding = $utf8
$OutputEncoding = $utf8

if ([string]::IsNullOrWhiteSpace($ProjectRoot)) { $ProjectRoot = Split-Path -Parent $PSScriptRoot }
$ProjectRoot = [IO.Path]::GetFullPath($ProjectRoot)
if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
    $OutputDirectory = Join-Path ([IO.Path]::GetTempPath()) ('BeltScroll_M6M_' + (Get-Date -Format 'yyyyMMdd_HHmmss_fff'))
}
$OutputDirectory = [IO.Path]::GetFullPath($OutputDirectory)
[void][IO.Directory]::CreateDirectory($OutputDirectory)

if ([string]::IsNullOrWhiteSpace($GodotPath)) {
    $godotCommand = Get-Command godot -ErrorAction SilentlyContinue
    if ($null -eq $godotCommand) { $godotCommand = Get-Command godot4 -ErrorAction SilentlyContinue }
    if ($null -eq $godotCommand) { throw 'Godot executable was not found. Pass -GodotPath.' }
    $GodotPath = $godotCommand.Source
}
$GodotPath = [IO.Path]::GetFullPath($GodotPath)
if (-not (Test-Path -LiteralPath $GodotPath -PathType Leaf)) { throw "Godot executable does not exist: $GodotPath" }
$smokePath = Join-Path $ProjectRoot 'tests\m6l_walk_cycle_preview_smoke.gd'
if (-not (Test-Path -LiteralPath $smokePath -PathType Leaf)) { throw "Preview smoke test does not exist: $smokePath" }

function Quote-Argument([string]$Value) {
    '"' + $Value.Replace('"','\"') + '"'
}

function Stop-ProcessTree([int]$ProcessId) {
    # Godot normally runs as one process; /T also cleans any descendants on timeout.
    $taskkill = Join-Path $env:SystemRoot 'System32\taskkill.exe'
    if (Test-Path -LiteralPath $taskkill -PathType Leaf) {
        $null = & $taskkill /PID $ProcessId /T /F 2>&1
    }
    try {
        $left = Get-Process -Id $ProcessId -ErrorAction SilentlyContinue
        if ($null -ne $left) { Stop-Process -Id $ProcessId -Force -ErrorAction SilentlyContinue }
    } catch { }
}

function Invoke-BoundedGodot([string]$Name, [string[]]$GodotArgs, [int]$TimeoutSeconds) {
    $stdout = Join-Path $OutputDirectory ($Name + '.stdout.log')
    $stderr = Join-Path $OutputDirectory ($Name + '.stderr.log')
    Remove-Item -LiteralPath $stdout,$stderr -Force -ErrorAction SilentlyContinue
    $quoted = @($GodotArgs | ForEach-Object { Quote-Argument ([string]$_) }) -join ' '
    $startedUtc = [DateTime]::UtcNow
    $watch = [Diagnostics.Stopwatch]::StartNew()
    $process = Start-Process -FilePath $GodotPath -ArgumentList $quoted -WorkingDirectory $ProjectRoot -PassThru -RedirectStandardOutput $stdout -RedirectStandardError $stderr
    $finished = $process.WaitForExit($TimeoutSeconds * 1000)
    $timedOut = -not $finished
    if ($timedOut) {
        Stop-ProcessTree -ProcessId $process.Id
        $process.WaitForExit()
    }
    $process.Refresh()
    $watch.Stop()
    $exitCode = $null
    if (-not $timedOut) { $exitCode = [int]$process.ExitCode }
    $stillRunning = $null -ne (Get-Process -Id $process.Id -ErrorAction SilentlyContinue)
    $record = [pscustomobject]@{
        name = $Name; startedUtc = $startedUtc.ToString('o'); timeoutSeconds = $TimeoutSeconds
        elapsedSeconds = [Math]::Round($watch.Elapsed.TotalSeconds,3); timedOut = $timedOut
        exitCode = $exitCode; processId = $process.Id; processStillRunning = $stillRunning
        stdoutLog = $stdout; stderrLog = $stderr; arguments = $GodotArgs
    }
    $status = if ($timedOut) { 'TIMEOUT' } elseif ($exitCode -eq 0) { 'PASS' } else { 'FAIL' }
    Write-Host ("[{0}] {1} elapsed={2}s timeout={3}s exit={4} pid={5} cleaned={6}" -f $Name,$status,$record.elapsedSeconds,$TimeoutSeconds,$exitCode,$process.Id,(-not $stillRunning))
    Write-Host ("[{0}] stdout={1}" -f $Name,$stdout)
    Write-Host ("[{0}] stderr={1}" -f $Name,$stderr)
    return $record
}

$modes = if ($Mode -eq 'Both') { @('Headless','Window') } else { @($Mode) }
$allRecords = @()
$overall = 'PASS'
Write-Output "Project: $ProjectRoot"
Write-Output "Godot: $GodotPath"
Write-Output "Bounded logs: $OutputDirectory"

$importArgs = @('--headless','--editor','--path',$ProjectRoot,'--import','--quit')
Write-Output "=== Initial import phase (separate process, timeout ${ImportTimeoutSeconds}s) ==="
$import = Invoke-BoundedGodot -Name 'initial_import' -GodotArgs $importArgs -TimeoutSeconds $ImportTimeoutSeconds
$allRecords += $import
$importAttempts = @($import)
if ($import.timedOut -or $import.exitCode -ne 0) {
    Write-Output 'Initial import did not exit 0; rerun once in a fresh process. Validation will still run against the existing project cache so import and smoke outcomes remain separately observable.'
    $retry = Invoke-BoundedGodot -Name 'initial_import_retry' -GodotArgs $importArgs -TimeoutSeconds $ImportTimeoutSeconds
    $allRecords += $retry
    $importAttempts += $retry
}
$importReady = @($importAttempts | Where-Object { -not $_.timedOut -and $_.exitCode -eq 0 }).Count -gt 0
if (-not $importReady) { $overall = 'BLOCKED_IMPORT' }

foreach ($runMode in $modes) {

    $timeout = if ($runMode -eq 'Headless') { $HeadlessTimeoutSeconds } else { $WindowTimeoutSeconds }
    $results = @()
    Write-Output "=== ${runMode}: validation phase ($Repeats runs, each timeout ${timeout}s) ==="
    for ($i = 1; $i -le $Repeats; $i++) {
        $args = @()
        if ($runMode -eq 'Headless') { $args += '--headless' }
        $args += @('--path',$ProjectRoot,'--script',$smokePath)
        $record = Invoke-BoundedGodot -Name ($runMode.ToLowerInvariant() + '_validation_' + $i) -GodotArgs $args -TimeoutSeconds $timeout
        $results += $record
        $allRecords += $record
    }
    $timeouts = @($results | Where-Object { $_.timedOut }).Count
    $passes = @($results | Where-Object { -not $_.timedOut -and $_.exitCode -eq 0 }).Count
    if ($timeouts -ge 2) {
        if ($overall -eq 'PASS' -or $overall -eq 'BLOCKED_IMPORT') { $overall = 'BLOCKED_REPRODUCIBLE_TIMEOUT' }
        Write-Output "[$runMode] Decision=BLOCKED: validation timeout reproduced $timeouts times; inspect per-run logs and process cleanup state."
    } elseif ($timeouts -eq 1) {
        if ($overall -eq 'PASS' -or $overall -eq 'BLOCKED_IMPORT') { $overall = 'BLOCKED_INTERMITTENT_TIMEOUT' }
        Write-Output "[$runMode] Decision=BLOCKED: one validation timeout occurred; the other bounded run did not reproduce it. Repeat after capturing machine load, import state, and the timeout logs."
    } elseif ($passes -eq $Repeats) {
        Write-Output "[$runMode] Decision=PASS for bounded automated smoke only; this does not invalidate a prior 120s QA timeout or replace physical-key/manual visual acceptance."
    } else {
        if ($overall -eq 'PASS') { $overall = 'BLOCKED_VALIDATION_FAILURE' }
        Write-Output "[$runMode] Decision=BLOCKED: validation exited nonzero in $($Repeats - $passes) run(s); inspect stdout/stderr and fix the reported check before rerun."
    }
}

$summary = [ordered]@{
    status = $overall; generatedAtUtc = [DateTime]::UtcNow.ToString('o'); mode = $Mode
    godotPath = $GodotPath; projectRoot = $ProjectRoot; outputDirectory = $OutputDirectory
    requiredRepeatCount = $Repeats; records = $allRecords
    priorQa120SecondTimeoutInvalidated = $false
    nextAction = if ($overall -eq 'PASS') { 'Compare these runs with the earlier QA timeout logs; retain BLOCKED if that timeout remains unexplained.' } else { 'Resolve or explain the recorded import/validation timeout or failure, then rerun both modes at least twice.' }
}
$summaryPath = Join-Path $OutputDirectory 'run-summary.json'
[IO.File]::WriteAllText($summaryPath,(ConvertTo-Json -InputObject $summary -Depth 8),$utf8)
Write-Output "Overall: $overall"
Write-Output "Summary: $summaryPath"
if ($overall -ne 'PASS') { exit 2 }
exit 0
