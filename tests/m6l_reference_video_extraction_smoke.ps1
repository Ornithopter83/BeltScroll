[CmdletBinding()]
param([string]$InputPath)

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)
$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$extractor = Join-Path $projectRoot 'tools\extract_m6l_reference_video_frames.ps1'
if ([string]::IsNullOrWhiteSpace($InputPath)) {
    $attachmentRoot = Join-Path $projectRoot 'temp\ProjectHub\attachments'
    $videos = @(Get-ChildItem -LiteralPath $attachmentRoot -Recurse -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Extension -match '^\.mp4$' })
    if ($videos.Count -ne 1) { throw "Expected exactly one attached MP4 for smoke check, found $($videos.Count). Pass -InputPath." }
    $InputPath = $videos[0].FullName
}
if (-not (Test-Path -LiteralPath $extractor -PathType Leaf)) { throw "Extractor missing: $extractor" }
if (-not (Test-Path -LiteralPath $InputPath -PathType Leaf)) { throw "Input video missing: $InputPath" }

$extractorText = Get-Content -LiteralPath $extractor -Encoding UTF8 -Raw
foreach ($required in @('Get-FileHash', 'SHA256', 'VerifiedSequentialDecoderAvailable', 'showinfo', 'prev_selected_t', 'TimestampOrderStrictlyIncreasing', 'AllFrameHashesDistinct', 'AdjacentImageDifferencesPositive', 'UNVERIFIED')) {
    if (-not $extractorText.Contains($required)) { throw "Extractor does not contain required verification behavior: $required" }
}

$powershell = (Get-Command powershell.exe -ErrorAction Stop).Source
$startInfo = New-Object System.Diagnostics.ProcessStartInfo
$startInfo.FileName = $powershell
$startInfo.Arguments = '-NoProfile -ExecutionPolicy Bypass -File "' + $extractor + '" -ProbeOnly -InputPath "' + (Resolve-Path -LiteralPath $InputPath).Path + '"'
$startInfo.UseShellExecute = $false
$startInfo.CreateNoWindow = $true
$startInfo.RedirectStandardOutput = $true
$startInfo.RedirectStandardError = $true
$process = New-Object System.Diagnostics.Process
$process.StartInfo = $startInfo
if (-not $process.Start()) { throw 'Could not start PowerShell decoder probe.' }
$stdout = $process.StandardOutput.ReadToEnd()
$stderr = $process.StandardError.ReadToEnd()
$process.WaitForExit()
if ($process.ExitCode -ne 0) { throw "Decoder probe failed ($($process.ExitCode)): $stderr" }
$probeResult = $stdout | ConvertFrom-Json
$expectedHash = (Get-FileHash -LiteralPath $InputPath -Algorithm SHA256).Hash
if ($probeResult.InputSha256 -ne $expectedHash) { throw 'Probe SHA256 does not match Get-FileHash for the source video.' }
if ($probeResult.InputBytes -ne (Get-Item -LiteralPath $InputPath).Length) { throw 'Probe source byte count does not match the source video.' }
if ($probeResult.Status -eq 'UNVERIFIED' -and $probeResult.Probe.VerifiedSequentialDecoderAvailable) { throw 'Probe reports UNVERIFIED despite an available ffmpeg executable.' }
if ($probeResult.Status -eq 'READY' -and -not $probeResult.Probe.VerifiedSequentialDecoderAvailable) { throw 'Probe reports READY without an available ffmpeg executable.' }

Write-Output "PASS: source SHA256 $expectedHash; decoder probe status $($probeResult.Status); verification gates are present."
