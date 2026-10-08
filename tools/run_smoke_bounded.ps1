param(
    [Parameter(Mandatory = $true)][string]$Executable,
    [Parameter(Mandatory = $true)][ValidateRange(1, 86400)][int]$TimeoutSeconds,
    [Parameter(Mandatory = $true)][string]$LogPath
)

$ErrorActionPreference = 'Stop'
$utf8 = New-Object System.Text.UTF8Encoding($false)
$stdout = ''
$stderr = ''
$processId = 0
$timedOut = $false
$exitCode = 1
$jobHandle = [IntPtr]::Zero
$treeTermination = 'not needed'
$startedAt = Get-Date

try {
    if (-not ('SmokeBounded.NativeJob' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
namespace SmokeBounded {
    public static class NativeJob {
        [StructLayout(LayoutKind.Sequential)] public struct BasicLimitInformation {
            public long PerProcessUserTimeLimit;
            public long PerJobUserTimeLimit;
            public uint LimitFlags;
            public UIntPtr MinimumWorkingSetSize;
            public UIntPtr MaximumWorkingSetSize;
            public uint ActiveProcessLimit;
            public UIntPtr Affinity;
            public uint PriorityClass;
            public uint SchedulingClass;
        }
        [StructLayout(LayoutKind.Sequential)] public struct IoCounters {
            public ulong ReadOperationCount, WriteOperationCount, OtherOperationCount;
            public ulong ReadTransferCount, WriteTransferCount, OtherTransferCount;
        }
        [StructLayout(LayoutKind.Sequential)] public struct ExtendedLimitInformation {
            public BasicLimitInformation BasicLimitInformation;
            public IoCounters IoInfo;
            public UIntPtr ProcessMemoryLimit, JobMemoryLimit, PeakProcessMemoryUsed, PeakJobMemoryUsed;
        }
        [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)]
        public static extern IntPtr CreateJobObject(IntPtr attributes, string name);
        [DllImport("kernel32.dll", SetLastError=true)]
        public static extern bool SetInformationJobObject(IntPtr job, int infoClass, ref ExtendedLimitInformation info, uint length);
        [DllImport("kernel32.dll", SetLastError=true)]
        public static extern bool AssignProcessToJobObject(IntPtr job, IntPtr process);
        [DllImport("kernel32.dll", SetLastError=true)]
        public static extern bool TerminateJobObject(IntPtr job, uint exitCode);
        [DllImport("kernel32.dll", SetLastError=true)]
        public static extern bool CloseHandle(IntPtr handle);
    }
}
'@
    }
    $jobHandle = [SmokeBounded.NativeJob]::CreateJobObject([IntPtr]::Zero, $null)
    if ($jobHandle -eq [IntPtr]::Zero) { throw "CreateJobObject failed: $([Runtime.InteropServices.Marshal]::GetLastWin32Error())" }
    $jobInfo = New-Object SmokeBounded.NativeJob+ExtendedLimitInformation
    $jobInfo.BasicLimitInformation.LimitFlags = 0x2000 # JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE
    $jobInfoSize = [Runtime.InteropServices.Marshal]::SizeOf([type][SmokeBounded.NativeJob+ExtendedLimitInformation])
    if (-not [SmokeBounded.NativeJob]::SetInformationJobObject($jobHandle, 9, [ref]$jobInfo, [uint32]$jobInfoSize)) {
        throw "SetInformationJobObject failed: $([Runtime.InteropServices.Marshal]::GetLastWin32Error())"
    }

    $arguments = [Environment]::GetEnvironmentVariable('SMOKE_ARGS')
    if ($null -eq $arguments) { $arguments = '' }

    $startInfo = New-Object System.Diagnostics.ProcessStartInfo
    $startInfo.FileName = $Executable
    $startInfo.Arguments = $arguments
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true

    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $startInfo
    if (-not $process.Start()) { throw 'Process.Start returned false.' }
    $processId = $process.Id
    if (-not [SmokeBounded.NativeJob]::AssignProcessToJobObject($jobHandle, $process.Handle)) {
        $assignError = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
        # Keep the root process killable even when the host forbids job assignment.
        $treeTermination = "job assignment failed ($assignError); taskkill fallback"
    } else {
        $treeTermination = 'Windows job object'
    }

    # Drain both pipes asynchronously so neither can fill and block the child.
    $stdoutTask = $process.StandardOutput.ReadToEndAsync()
    $stderrTask = $process.StandardError.ReadToEndAsync()
    if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
        $timedOut = $true
        if ($treeTermination -eq 'Windows job object') {
            if ([SmokeBounded.NativeJob]::TerminateJobObject($jobHandle, 124)) {
                $treeTermination = 'Windows job object termination requested'
            } else {
                $terminateError = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
                $treeTermination = "job termination failed ($terminateError); taskkill fallback"
                & taskkill.exe /PID $processId /T /F 2>$null | Out-Null
            }
        } else {
            & taskkill.exe /PID $processId /T /F 2>$null | Out-Null
            $treeTermination = 'taskkill /T termination requested'
        }
        if (-not $process.WaitForExit(5000)) {
            try { $process.Kill() } catch { }
            [void]$process.WaitForExit(5000)
        }
    }

    # Closing a kill-on-close job also releases descendants that inherited either pipe.
    if ($jobHandle -ne [IntPtr]::Zero) {
        [void][SmokeBounded.NativeJob]::CloseHandle($jobHandle)
        $jobHandle = [IntPtr]::Zero
    }

    # ReadToEnd completes after process exit and retains all output emitted before a timeout.
    $stdout = $stdoutTask.GetAwaiter().GetResult()
    $stderr = $stderrTask.GetAwaiter().GetResult()
    if (-not $timedOut) { $exitCode = $process.ExitCode }
} catch {
    $stderr += "`r`n[smoke bounded] Runner error: $($_.Exception.Message)`r`n"
    $exitCode = 125
}
finally {
    if ($jobHandle -ne [IntPtr]::Zero) {
        [void][SmokeBounded.NativeJob]::CloseHandle($jobHandle)
    }
}

$elapsed = [Math]::Round(((Get-Date) - $startedAt).TotalSeconds, 3)
$log = New-Object System.Text.StringBuilder
[void]$log.AppendLine("[smoke bounded] PID: $processId")
[void]$log.AppendLine("[smoke bounded] Timeout seconds: $TimeoutSeconds")
if ($timedOut) {
    [void]$log.AppendLine("[smoke bounded] RESULT: TIMEOUT after $TimeoutSeconds seconds; process tree termination: $treeTermination.")
    $exitCode = 124
} elseif ($exitCode -eq 125) {
    [void]$log.AppendLine('[smoke bounded] RESULT: RUNNER_ERROR')
} else {
    [void]$log.AppendLine("[smoke bounded] Actual process exit code: $exitCode")
}
[void]$log.AppendLine("[smoke bounded] Elapsed seconds: $elapsed")
[void]$log.AppendLine('----- stderr -----')
[void]$log.Append($stderr)
if (-not $stderr.EndsWith("`n") -and -not $stderr.EndsWith("`r")) { [void]$log.AppendLine() }
[void]$log.AppendLine('----- stdout -----')
[void]$log.Append($stdout)
if (-not $stdout.EndsWith("`n") -and -not $stdout.EndsWith("`r")) { [void]$log.AppendLine() }
[IO.File]::WriteAllText($LogPath, $log.ToString(), $utf8)
exit $exitCode
