[CmdletBinding()]
param(
    [string]$InputPath,
    [string]$OutputDirectory,
    [double]$IntervalSeconds = 0.25,
    [switch]$ProbeOnly
)

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)
$script:StatusUnverified = 'UNVERIFIED'

function Find-ReferenceVideo {
    param([string]$RequestedPath)

    if (-not [string]::IsNullOrWhiteSpace($RequestedPath)) {
        if (-not (Test-Path -LiteralPath $RequestedPath -PathType Leaf)) {
            throw "Input video does not exist: $RequestedPath"
        }
        return (Get-Item -LiteralPath $RequestedPath).FullName
    }

    $projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
    $attachmentRoot = Join-Path $projectRoot 'temp\ProjectHub\attachments'
    $matches = @(Get-ChildItem -LiteralPath $attachmentRoot -Recurse -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Extension -match '^\.mp4$' })
    if ($matches.Count -ne 1) {
        throw "Expected exactly one attached MP4 under '$attachmentRoot'; found $($matches.Count). Pass -InputPath explicitly."
    }
    return $matches[0].FullName
}

function Get-DecoderProbe {
    $ffmpeg = Get-Command ffmpeg.exe, ffmpeg -ErrorAction SilentlyContinue | Select-Object -First 1
    $ffprobe = Get-Command ffprobe.exe, ffprobe -ErrorAction SilentlyContinue | Select-Object -First 1
    $mediaFoundation = [ordered]@{
        Available = $false
        Components = @()
        ExtractionReady = $false
        Note = 'Media Foundation presence alone does not provide a verified sequential frame and source-PTS extraction path.'
    }
    if ($env:WINDIR) {
        foreach ($component in @('mfplat.dll', 'mfreadwrite.dll', 'mf.dll')) {
            if (Test-Path -LiteralPath (Join-Path $env:WINDIR "System32\$component")) {
                $mediaFoundation.Components += $component
            }
        }
        $mediaFoundation.Available = $mediaFoundation.Components.Count -gt 0
    }
    $wmpAvailable = $false
    if ($env:OS -eq 'Windows_NT') {
        try {
            $wmp = New-Object -ComObject WMPlayer.OCX -ErrorAction Stop
            $wmpAvailable = $true
            [void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($wmp)
        } catch { }
    }
    return [pscustomobject]@{
        FfmpegPath = if ($ffmpeg) { $ffmpeg.Source } else { $null }
        FfprobePath = if ($ffprobe) { $ffprobe.Source } else { $null }
        MediaFoundation = [pscustomobject]$mediaFoundation
        WindowsMediaPlayerComAvailable = $wmpAvailable
        VerifiedSequentialDecoderAvailable = [bool]$ffmpeg
    }
}

function Get-ImageDifference {
    param([string]$PreviousPath, [string]$CurrentPath)

    $previous = [System.Drawing.Bitmap]::new($PreviousPath)
    $current = [System.Drawing.Bitmap]::new($CurrentPath)
    try {
        if ($previous.Width -ne $current.Width -or $previous.Height -ne $current.Height) {
            return [double]::PositiveInfinity
        }
        $stepX = [Math]::Max(1, [int][Math]::Floor($current.Width / 128.0))
        $stepY = [Math]::Max(1, [int][Math]::Floor($current.Height / 128.0))
        [double]$sum = 0
        [long]$count = 0
        for ($y = 0; $y -lt $current.Height; $y += $stepY) {
            for ($x = 0; $x -lt $current.Width; $x += $stepX) {
                $a = $previous.GetPixel($x, $y)
                $b = $current.GetPixel($x, $y)
                $sum += [Math]::Abs($a.R - $b.R) + [Math]::Abs($a.G - $b.G) + [Math]::Abs($a.B - $b.B)
                $count += 3
            }
        }
        if ($count -eq 0) { return 0.0 }
        return [Math]::Round($sum / $count, 6)
    } finally {
        $previous.Dispose()
        $current.Dispose()
    }
}

try {
    if ($IntervalSeconds -le 0) { throw '-IntervalSeconds must be greater than zero.' }
    $resolvedInput = Find-ReferenceVideo -RequestedPath $InputPath
    $inputHash = (Get-FileHash -LiteralPath $resolvedInput -Algorithm SHA256).Hash
    $probe = Get-DecoderProbe

    if ($ProbeOnly) {
        [pscustomobject]@{
            InputPath = $resolvedInput
            InputBytes = (Get-Item -LiteralPath $resolvedInput).Length
            InputSha256 = $inputHash
            Probe = $probe
            Status = if ($probe.VerifiedSequentialDecoderAvailable) { 'READY' } else { $script:StatusUnverified }
        } | ConvertTo-Json -Depth 6 -Compress
        exit 0
    }

    if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
        throw 'Pass -OutputDirectory to choose where frame evidence and its manifest will be written.'
    }
    $outputRoot = [System.IO.Path]::GetFullPath($OutputDirectory)
    [void](New-Item -ItemType Directory -Path $outputRoot -Force)
    $runName = 'run_' + (Get-Date -Format 'yyyyMMdd_HHmmss_fff')
    $output = Join-Path $outputRoot $runName
    [void](New-Item -ItemType Directory -Path $output)
    $manifestPath = Join-Path $output 'm6l_reference_video_manifest.json'

    $manifest = [ordered]@{
        Status = $script:StatusUnverified
        InputPath = $resolvedInput
        InputBytes = (Get-Item -LiteralPath $resolvedInput).Length
        InputSha256 = $inputHash
        DecoderProbe = $probe
        DecodeMethod = $null
        SamplingIntervalSeconds = $IntervalSeconds
        Frames = @()
        M6KWindowComparisonEvidence = @()
        Validation = [ordered]@{
            TimestampOrderStrictlyIncreasing = $false
            AllFrameHashesDistinct = $false
            AdjacentImageDifferencesPositive = $false
            FrameCountAtLeastTwo = $false
        }
        Reason = $null
    }

    if (-not $probe.VerifiedSequentialDecoderAvailable) {
        $manifest.Reason = 'No ffmpeg executable is available. Windows Media Foundation DLLs and Windows Media Player COM were probed when present, but no verified sequential frame export preserving source presentation timestamps is implemented for those interfaces. No arbitrary seek or repeated display frame is accepted as extracted evidence.'
        $manifest | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $manifestPath -Encoding UTF8
        Write-Output "UNVERIFIED: no verified sequential decoder. Manifest: $manifestPath"
        exit 2
    }

    Add-Type -AssemblyName System.Drawing
    $ffmpegPath = $probe.FfmpegPath
    $logPath = Join-Path $output 'ffmpeg_decode.log'
    $filter = "select='isnan(prev_selected_t)+gte(t-prev_selected_t\,$IntervalSeconds)',showinfo"
    $framePattern = Join-Path $output 'frame_%06d.png'
    $ffmpegArgs = @('-hide_banner', '-nostats', '-loglevel', 'info', '-i', $resolvedInput,
        '-vf', $filter, '-vsync', '0', '-start_number', '0', $framePattern)
    $decodeLines = @(& $ffmpegPath @ffmpegArgs 2>&1)
    $decodeExitCode = $LASTEXITCODE
    $decodeLines | Set-Content -LiteralPath $logPath -Encoding UTF8
    $manifest.DecodeMethod = 'ffmpeg single-process sequential decode with select on decoded-frame presentation timestamps; showinfo source pts_time; passthrough output timestamps'

    $timestamps = @()
    foreach ($line in $decodeLines) {
        if ([string]$line -match 'showinfo.*\bn:\s*(?<index>\d+).*\bpts_time:(?<time>-?\d+(?:\.\d+)?)') {
            $timestamps += [pscustomobject]@{ Index = [int]$Matches.index; TimestampSeconds = [double]::Parse($Matches.time, [Globalization.CultureInfo]::InvariantCulture) }
        }
    }
    $frameFiles = @(Get-ChildItem -LiteralPath $output -Filter 'frame_*.png' -File | Sort-Object Name)
    if ($decodeExitCode -ne 0) {
        $manifest.Reason = "ffmpeg sequential decode exited with code $decodeExitCode. See ffmpeg_decode.log; partial files are not verified evidence."
    } elseif ($frameFiles.Count -ne $timestamps.Count) {
        $manifest.Reason = "Decoded PNG count ($($frameFiles.Count)) does not match showinfo source timestamp count ($($timestamps.Count)); output is unverified."
    } else {
        $previousPath = $null
        $previousTime = $null
        $orderOk = $true
        $distinctOk = $true
        $diffOk = $true
        $seenHashes = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
        for ($index = 0; $index -lt $frameFiles.Count; $index++) {
            $file = $frameFiles[$index]
            $hash = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash
            $difference = $null
            if (-not $seenHashes.Add($hash)) { $distinctOk = $false }
            if ($null -ne $previousPath) {
                $difference = Get-ImageDifference -PreviousPath $previousPath -CurrentPath $file.FullName
                if ($timestamps[$index].TimestampSeconds -le $previousTime) { $orderOk = $false }
                if ($difference -le 0) { $diffOk = $false }
            }
            $manifest.Frames += [pscustomobject]@{
                Sequence = $index
                TimestampSeconds = $timestamps[$index].TimestampSeconds
                RelativePath = [System.IO.Path]::GetFileName($file.FullName)
                Sha256 = $hash
                MeanAbsoluteRgbDifferenceFromPrevious = $difference
                Bytes = $file.Length
            }
            $previousPath = $file.FullName
            $previousTime = $timestamps[$index].TimestampSeconds
        }
        $manifest.Validation.TimestampOrderStrictlyIncreasing = $orderOk
        $manifest.Validation.AllFrameHashesDistinct = ($frameFiles.Count -ge 2 -and $distinctOk)
        $manifest.Validation.AdjacentImageDifferencesPositive = ($frameFiles.Count -ge 2 -and $diffOk)
        $manifest.Validation.FrameCountAtLeastTwo = ($frameFiles.Count -ge 2)
        if ($manifest.Validation.TimestampOrderStrictlyIncreasing -and $manifest.Validation.AllFrameHashesDistinct -and $manifest.Validation.AdjacentImageDifferencesPositive -and $manifest.Validation.FrameCountAtLeastTwo) {
            $manifest.Status = 'VERIFIED'
            $manifest.Reason = 'Sequential decode completed and timestamp order, unique SHA256 hashes, positive adjacent image differences, and minimum frame count passed.'
        } else {
            $manifest.Reason = 'One or more frame evidence checks failed (strict time order, distinct hashes, positive image differences, or at least two frames). Treat the extraction as UNVERIFIED.'
        }
    }
    $manifest | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $manifestPath -Encoding UTF8
    Write-Output "$($manifest.Status): $($manifest.Reason) Manifest: $manifestPath"
    if ($manifest.Status -ne 'VERIFIED') { exit 2 }
} catch {
    if ($null -ne $manifest -and -not [string]::IsNullOrWhiteSpace($manifestPath)) {
        $manifest.Status = $script:StatusUnverified
        $manifest.Reason = "Extraction could not be verified: $($_.Exception.Message)"
        try { $manifest | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $manifestPath -Encoding UTF8 } catch { }
    }
    [Console]::Error.WriteLine("UNVERIFIED: $($_.Exception.Message)")
    exit 2
}
