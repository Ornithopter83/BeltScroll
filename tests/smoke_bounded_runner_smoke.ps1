$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$runner = Join-Path $root 'tools\run_smoke_bounded.ps1'
$hangFixture = Join-Path $PSScriptRoot 'fixtures\smoke_hang.ps1'
$shell = Join-Path $PSHOME 'powershell.exe'
$tempRoot = Join-Path ([IO.Path]::GetTempPath()) ('beltscroll_bounded_' + [Guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($tempRoot)

function Quote-NativeArgument([string]$Value) {
    '"' + $Value.Replace('"', '\\"') + '"'
}

function Invoke-BoundedCase([string]$Arguments, [int]$TimeoutSeconds, [string]$LogPath) {
    $env:SMOKE_ARGS = $Arguments
    $startInfo = New-Object System.Diagnostics.ProcessStartInfo
    $startInfo.FileName = $shell
    $startInfo.Arguments = '-NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File ' + (Quote-NativeArgument $runner) +
        ' -Executable ' + (Quote-NativeArgument $shell) +
        ' -TimeoutSeconds ' + $TimeoutSeconds +
        ' -LogPath ' + (Quote-NativeArgument $LogPath)
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $process = [Diagnostics.Process]::Start($startInfo)
    $null = $process.WaitForExit(30000)
    if (-not $process.HasExited) {
        & taskkill.exe /PID $process.Id /T /F 2>$null | Out-Null
        throw 'The bounded runner itself did not return within 30 seconds.'
    }
    $process.ExitCode
}

try {
    $successLog = Join-Path $tempRoot 'success.log'
    $successArgs = '-NoProfile -NonInteractive -Command "Write-Output ''stdout-marker''; [Console]::Error.WriteLine(''stderr-marker''); exit 0"'
    $successCode = Invoke-BoundedCase $successArgs 10 $successLog
    $successText = [IO.File]::ReadAllText($successLog, [Text.Encoding]::UTF8)
    if ($successCode -ne 0 -or $successText -notmatch 'Actual process exit code: 0' -or
        $successText -notmatch 'stdout-marker' -or $successText -notmatch 'stderr-marker' -or
        $successText -notmatch '\[smoke bounded\] PID: \d+' -or
        -not $successText.TrimEnd().EndsWith('stdout-marker')) {
        throw 'Immediate success did not preserve its exit code, PID, stdout, and stderr.'
    }

    $failureLog = Join-Path $tempRoot 'failure.log'
    $failureCode = Invoke-BoundedCase '-NoProfile -NonInteractive -Command "exit 7"' 10 $failureLog
    $failureText = [IO.File]::ReadAllText($failureLog, [Text.Encoding]::UTF8)
    if ($failureCode -ne 7 -or $failureText -notmatch 'Actual process exit code: 7') {
        throw 'The bounded runner did not return the child process exit code.'
    }

    $childPidPath = Join-Path $tempRoot 'child.pid'
    $hangLog = Join-Path $tempRoot 'hang.log'
    $hangArgs = '-NoProfile -NonInteractive -ExecutionPolicy Bypass -File ' +
        (Quote-NativeArgument $hangFixture) + ' -ChildPidPath ' + (Quote-NativeArgument $childPidPath)
    $timer = [Diagnostics.Stopwatch]::StartNew()
    $hangCode = Invoke-BoundedCase $hangArgs 3 $hangLog
    $timer.Stop()
    $hangText = [IO.File]::ReadAllText($hangLog, [Text.Encoding]::UTF8)
    if ($hangCode -ne 124 -or $timer.Elapsed.TotalSeconds -ge 15 -or
        $hangText -notmatch 'RESULT: TIMEOUT' -or $hangText -notmatch '\[smoke bounded\] PID: \d+') {
        throw 'A silent hanging process was not reported as a bounded timeout.'
    }
    if (-not (Test-Path -LiteralPath $childPidPath)) { throw 'The hang fixture did not create its child process.' }
    $childPid = [int][IO.File]::ReadAllText($childPidPath, [Text.Encoding]::ASCII)
    Start-Sleep -Milliseconds 300
    if (Get-Process -Id $childPid -ErrorAction SilentlyContinue) {
        throw "Timed-out process tree left child PID $childPid running."
    }

    Write-Output 'smoke_bounded_runner_smoke: all checks passed'
} finally {
    Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item Env:\SMOKE_ARGS -ErrorAction SilentlyContinue
}
