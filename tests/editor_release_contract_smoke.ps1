param(
    [Parameter(Mandatory = $true)]
    [string]$PackagePath,
    [int]$TimeoutSeconds = 180
)

$ErrorActionPreference = 'Stop'
$utf8 = New-Object System.Text.UTF8Encoding($false)
[Console]::OutputEncoding = $utf8
$OutputEncoding = $utf8
$projectRoot = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$packageSmokePath = Join-Path $PSScriptRoot 'editor_release_package_smoke.ps1'
$packageFullPath = [IO.Path]::GetFullPath($PackagePath)
if (-not (Test-Path -LiteralPath $packageFullPath -PathType Leaf)) { throw "Package ZIP not found: $packageFullPath" }
if (-not (Test-Path -LiteralPath $packageSmokePath -PathType Leaf)) { throw "Package smoke script not found: $packageSmokePath" }

$smokeSource = [IO.File]::ReadAllText($packageSmokePath, [Text.Encoding]::UTF8)
foreach ($contractMarker in @('schemaVersion -ne 1', 'clipCount -ne 11', 'frameCount -ne 4', 'schema_version', 'attack1', 'Assert-ValidPng', 'Extracted outside project')) {
    if ($smokeSource -notmatch [regex]::Escape($contractMarker)) { throw "Package smoke does not enforce required release contract marker: $contractMarker" }
}
if ($smokeSource -notmatch "AllowGuiUnverified.*GUI_UNAVAILABLE" -and $smokeSource -notmatch "GUI_UNAVAILABLE.*AllowGuiUnverified") {
    throw 'AllowGuiUnverified must only allow explicit GUI_UNAVAILABLE conditions.'
}
if ($smokeSource -match 'AllowGuiUnverified[^\r\n]*(clipCount|frameCount|schema_version|passed)') {
    throw 'AllowGuiUnverified must not bypass release contract or data validation failures.'
}

$powershell51 = Get-Command 'powershell.exe' -ErrorAction SilentlyContinue
$pwsh7 = Get-Command 'pwsh.exe' -ErrorAction SilentlyContinue
if (-not $powershell51) { throw 'Windows PowerShell 5.1 (powershell.exe) is required for the contract smoke.' }
if (-not $pwsh7) { throw 'PowerShell 7 (pwsh.exe) is required for the contract smoke.' }
$tempRoot = Join-Path ([IO.Path]::GetTempPath()) ('BeltScrollReleaseContract_' + [Guid]::NewGuid().ToString('N'))
if ($tempRoot.StartsWith($projectRoot, [StringComparison]::OrdinalIgnoreCase)) { throw "Contract logs must be outside the project: $tempRoot" }
[void][IO.Directory]::CreateDirectory($tempRoot)

function Quote-ProcessArgument([string]$Value) {
    return '"' + $Value.Replace('"', '\"') + '"'
}

function Invoke-SmokeInShell([string]$ShellPath, [string]$ShellName) {
    $stdoutPath = Join-Path $tempRoot ($ShellName + '.stdout.txt')
    $stderrPath = Join-Path $tempRoot ($ShellName + '.stderr.txt')
    $args = @('-NoLogo', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $packageSmokePath, '-PackagePath', $packageFullPath, '-TimeoutSeconds', [string]$TimeoutSeconds, '-AllowGuiUnverified')
    $info = New-Object System.Diagnostics.ProcessStartInfo
    $info.FileName = $ShellPath
    $info.Arguments = ($args | ForEach-Object { Quote-ProcessArgument $_ }) -join ' '
    $info.WorkingDirectory = $tempRoot
    $info.UseShellExecute = $false
    $info.CreateNoWindow = $true
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    $info.StandardOutputEncoding = $utf8
    $info.StandardErrorEncoding = $utf8
    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $info
    if (-not $process.Start()) { throw "$ShellName did not start package smoke." }
    $stdoutTask = $process.StandardOutput.ReadToEndAsync()
    $stderrTask = $process.StandardError.ReadToEndAsync()
    if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
        try { $process.Kill() } catch { }
        try { $process.WaitForExit(10000) } catch { }
        $stdout = if ($stdoutTask.IsCompleted) { $stdoutTask.Result } else { '(stdout did not drain before timeout)' }
        $stderr = if ($stderrTask.IsCompleted) { $stderrTask.Result } else { '(stderr did not drain before timeout)' }
        [IO.File]::WriteAllText($stdoutPath, $stdout, $utf8)
        [IO.File]::WriteAllText($stderrPath, $stderr, $utf8)
        throw "$ShellName package smoke timed out. Logs: $stdoutPath ; $stderrPath"
    }
    $process.WaitForExit()
    $stdout = $stdoutTask.Result
    $stderr = $stderrTask.Result
    [IO.File]::WriteAllText($stdoutPath, $stdout, $utf8)
    [IO.File]::WriteAllText($stderrPath, $stderr, $utf8)
    if ($process.ExitCode -ne 0) { throw "$ShellName package smoke failed (exit=$($process.ExitCode)). Logs: $stdoutPath ; $stderrPath`n$stderr`n$stdout" }
    Write-Output ("[{0}] package smoke passed; {1}" -f $ShellName, $stdout.Trim())
}

Invoke-SmokeInShell $powershell51.Source 'WindowsPowerShell-5.1'
Invoke-SmokeInShell $pwsh7.Source 'PowerShell-7'
Write-Output "editor_release_contract_smoke: both shells passed; extraction and logs are outside the project at $tempRoot"
