$ErrorActionPreference = 'Stop'
$utf8 = New-Object System.Text.UTF8Encoding($false)
[Console]::OutputEncoding = $utf8
$OutputEncoding = $utf8
$root = Split-Path -Parent $PSScriptRoot
$suitePath = Join-Path $root 'tools\smoke_suite.cmd'
$probePath = Join-Path $PSScriptRoot 'smoke_runner_probe.cmd'
$boundedRunner = Join-Path $root 'tools\run_smoke_bounded.ps1'
$godot = if ($env:GODOT_EXE) { $env:GODOT_EXE } else { 'godot.exe' }
$tempRoot = Join-Path ([IO.Path]::GetTempPath()) ('beltscroll_dispatch_' + [Guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($tempRoot)
$logPath = Join-Path $tempRoot 'probe.log'
$boundedLog = Join-Path $tempRoot 'spin-art.log'
$marker = 'player_skill2_spin_art_smoke: mechanical checks passed; no production registration without human approval'

function Invoke-Native([string]$Executable, [string]$Arguments, [int]$TimeoutMilliseconds = 30000) {
    $startInfo = New-Object System.Diagnostics.ProcessStartInfo
    $startInfo.FileName = $Executable
    $startInfo.Arguments = $Arguments
    $startInfo.WorkingDirectory = $root
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $startInfo
    if (-not $process.Start()) { throw "Could not start $Executable." }
    $stdoutTask = $process.StandardOutput.ReadToEndAsync()
    $stderrTask = $process.StandardError.ReadToEndAsync()
    if (-not $process.WaitForExit($TimeoutMilliseconds)) {
        & taskkill.exe /PID $process.Id /T /F 2>$null | Out-Null
        throw "$Executable exceeded the $TimeoutMilliseconds ms dispatch harness timeout."
    }
    [pscustomobject]@{
        ExitCode = $process.ExitCode
        Output = $stdoutTask.GetAwaiter().GetResult() + $stderrTask.GetAwaiter().GetResult()
    }
}

function Quote-Argument([string]$Value) {
    '"' + $Value.Replace('"', '\"') + '"'
}

function Invoke-Probe([string]$ExitCode, [string]$ExpectedMarker) {
    $arguments = '/d /c call ' + (Quote-Argument $probePath) + ' ' +
        (Quote-Argument $logPath) + ' ' + (Quote-Argument $ExitCode) + ' ' + (Quote-Argument $ExpectedMarker)
    Invoke-Native $env:ComSpec $arguments
}

try {
    $suite = [IO.File]::ReadAllText($suitePath, [Text.Encoding]::UTF8)
    if (-not $suite.Contains('if /I "%SMOKE_NAME%"=="player_skill2_spin_art_smoke" set "SUCCESS_MARKER=' + $marker + '"')) {
        throw 'The production spin-art dispatch marker differs from its Godot output.'
    }
    if (-not $suite.Contains('set "SMOKE_ARGS=--headless --path ""%PROJECT_DIR%"" --script ""res://tests/%SMOKE_NAME%.gd"""')) { throw 'The headless dispatch does not use --headless.' }
    if (-not $suite.Contains('set "SMOKE_ARGS=--path ""%PROJECT_DIR%"" --script ""res://tests/%SMOKE_NAME%.gd"""')) { throw 'The Window dispatch does not use the real Window route.' }
    if (-not $suite.Contains('call "%PROBE%" "%RUN_LOG%" "%RUN_EXIT%" "%SUCCESS_MARKER%"')) { throw 'The shared Window dispatch is missing its exact marker and exit-code probe.' }
    if (-not $suite.Contains('call "%PROBE%" "%RUN_LOG%" "%RUN_EXIT%" "%SUCCESS_MARKER%" "%ALLOW_MODE%"')) { throw 'The headless dispatch is missing its exact marker and exit-code probe.' }
    if (-not $suite.Contains('if exist "%RUN_LOG%" del /q "%RUN_LOG%"') -or -not $suite.Contains('if exist "%ADDITIONAL_LOG%" del /q "%ADDITIONAL_LOG%"')) { throw 'The success cleanup does not use recognized conditional DEL commands.' }
    $suiteLines = [IO.File]::ReadAllLines($suitePath, [Text.Encoding]::UTF8)
    $finalizeStart = [Array]::IndexOf($suiteLines, ':finalize_suite')
    $reportStart = [Array]::IndexOf($suiteLines, ':report_suite')
    if ($finalizeStart -lt 0 -or $reportStart -le $finalizeStart) { throw 'The shared suite finalization and reporting labels are missing.' }
    $finalizeBlock = $suiteLines[$finalizeStart..($reportStart - 1)] -join "`n"
    if ([regex]::Matches($finalizeBlock, 'call :report_suite %SUITE_EXIT%').Count -ne 1) { throw 'Success and failure do not share exactly one suite summary call.' }
    if ($finalizeBlock.IndexOf('[smoke] All independent smoke checks passed.') -lt $finalizeBlock.IndexOf('call :report_suite %SUITE_EXIT%')) { throw 'The global PASS marker appears before the suite summary confirms exit code zero.' }

    [IO.File]::WriteAllText($logPath, "dispatch_probe: all checks passed`r`n", $utf8)
    $passingProbe = Invoke-Probe '0' 'dispatch_probe: all checks passed'
    if ($passingProbe.ExitCode -ne 0 -or $passingProbe.Output -notmatch '\[smoke probe\] PASS') { throw "cmd.exe rejected a valid zero-exit dispatch: $($passingProbe.Output)" }
    foreach ($case in @(
        [pscustomobject]@{ Exit = '7'; Marker = 'dispatch_probe: all checks passed'; Expected = 'Process exited with code 7.' },
        [pscustomobject]@{ Exit = '124'; Marker = 'dispatch_probe: all checks passed'; Expected = 'Process exited with code 124.' },
        [pscustomobject]@{ Exit = '0'; Marker = 'missing window marker'; Expected = 'Final success marker mismatch.' }
    )) {
        $rejected = Invoke-Probe $case.Exit $case.Marker
        if ($rejected.ExitCode -eq 0 -or $rejected.Output -notmatch [regex]::Escape($case.Expected)) { throw "cmd.exe accepted invalid dispatch case exit=$($case.Exit): $($rejected.Output)" }
    }

    $env:SMOKE_ARGS = '--headless --path "' + $root + '" --script "res://tests/player_skill2_spin_art_smoke.gd"'
    $runnerArgs = '-NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File ' + (Quote-Argument $boundedRunner) +
        ' -Executable ' + (Quote-Argument $godot) + ' -TimeoutSeconds 120 -LogPath ' + (Quote-Argument $boundedLog)
    $spin = Invoke-Native (Join-Path $PSHOME 'powershell.exe') $runnerArgs 150000
    if ($spin.ExitCode -ne 0) { throw "Real headless spin-art dispatch exited $($spin.ExitCode): $($spin.Output)" }
    $spinText = [IO.File]::ReadAllText($boundedLog, [Text.Encoding]::UTF8)
    if ($spinText -notmatch 'Actual process exit code: 0' -or $spinText -notmatch [regex]::Escape($marker)) { throw 'The real spin-art run did not produce exit 0 and the exact success marker.' }
    [IO.File]::Copy($boundedLog, $logPath, $true)
    $realProbe = Invoke-Probe '0' $marker
    if ($realProbe.ExitCode -ne 0 -or $realProbe.Output -notmatch '\[smoke probe\] PASS') { throw "cmd.exe rejected the real spin-art output: $($realProbe.Output)" }

    $cleanup = Invoke-Native $env:ComSpec ('/d /c if exist ' + (Quote-Argument $logPath) + ' del /q ' + (Quote-Argument $logPath))
    if ($cleanup.ExitCode -ne 0 -or $cleanup.Output -match '(?i)is not recognized as an internal or external command') { throw "cmd.exe cleanup failed: $($cleanup.Output)" }

    $fixtureArguments = '/d /c ""' + $suitePath + '" --accounting-fixture"'
    $accountingFixture = Invoke-Native $env:ComSpec $fixtureArguments 15000
    if ($accountingFixture.ExitCode -ne 0) { throw "Actual cmd.exe accounting fixture failed: $($accountingFixture.Output)" }
    $fixtureLines = @($accountingFixture.Output -split "`r?`n")
    $fixtureRecords = @($fixtureLines | Where-Object { $_ -match '^\[smoke\] additional_check=' })
    if ($fixtureRecords.Count -ne 4) { throw "Actual cmd.exe accounting fixture emitted $($fixtureRecords.Count) recorder rows instead of four." }
    $suiteSummaries = @($fixtureLines | Where-Object { $_ -match '^\[smoke\] suite process_exit=' })
    $accountingSummaries = @($fixtureLines | Where-Object { $_ -match '^\[smoke\] additional_checks=' })
    if ($suiteSummaries.Count -ne 1 -or $suiteSummaries[0] -notmatch '^\[smoke\] suite process_exit=1 elapsed_seconds=') { throw 'Actual cmd.exe failure fixture did not print exactly one suite summary with exit 1.' }
    if ($accountingSummaries.Count -ne 1 -or $accountingSummaries[0] -cne '[smoke] additional_checks=4 execution_types=headless,powershell additional_checks_process_exit=1') { throw 'Actual cmd.exe failure fixture did not print exactly one exact recorder summary.' }
    if (@($fixtureLines | Where-Object { $_ -ceq '[smoke] accounting_fixture: all checks passed' }).Count -ne 1) { throw 'Actual cmd.exe fixture did not return through its single completion marker.' }
    if (@($fixtureRecords | Where-Object { $_ -match 'process_exit=(7|124|9) ' }).Count -ne 3) { throw 'Actual cmd.exe fixture did not preserve all nonzero and timeout recorder exits.' }

    Write-Output 'cmd.exe dispatch trace: exit 0, exit 7, timeout 124, marker mismatch, one production failure summary, and recognized cleanup verified'
    Write-Output 'cmd.exe real player_skill2_spin_art_smoke: process_exit=0 and exact final marker accepted'
    Write-Output 'cmd.exe accounting fixture: four recorder rows and exactly one exit-1 suite summary verified'
    Write-Output 'smoke_suite_dispatch_smoke: all checks passed'
    exit 0
} finally {
    Remove-Item Env:\SMOKE_ARGS -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
}
