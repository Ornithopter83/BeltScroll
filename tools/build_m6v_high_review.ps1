param([string]$Before = 'assets/art/review/m6v_high_before_isolated/contact_sheet.png.json', [string]$After = 'assets/art/review/m6v_animation_quality_contact_sheet.png.json')
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
Add-Type -AssemblyName System.Drawing
$root = Split-Path $PSScriptRoot -Parent
$output = Join-Path $root 'assets/art/review/m6v_high_comparison'
New-Item -ItemType Directory -Force $output | Out-Null
$beforeData = Get-Content (Join-Path $root $Before) -Encoding UTF8 -Raw | ConvertFrom-Json
$afterData = Get-Content (Join-Path $root $After) -Encoding UTF8 -Raw | ConvertFrom-Json
$font = New-Object Drawing.Font('Arial', 10)
$states = @('walk', 'jump_rise', 'jump_fall', 'landing', 'attack1_startup', 'attack1_contact', 'attack1_recovery', 'attack2_startup', 'attack2_contact', 'attack2_recovery', 'attack3_startup', 'attack3_contact', 'attack3_recovery', 'skill1_startup', 'skill1_contact', 'skill1_recovery', 'skill2_startup', 'skill2_contact', 'skill2_recovery', 'hit', 'ko')
$reviewedBoards = @($states) + @('turn_left', 'transition_attack2_startup', 'transition_attack3_startup')
$reviewedFrames = @{}
foreach ($board in @($states) + @($states | ForEach-Object { 'transition_' + $_ }) + @('turn_left', 'turn_right')) {
    $state = $board -replace '^transition_', ''
    $bitmap = New-Object Drawing.Bitmap(1120, 656)
    $graphics = [Drawing.Graphics]::FromImage($bitmap)
    $graphics.Clear([Drawing.Color]::FromArgb(23,34,38))
    $graphics.InterpolationMode = [Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    for ($row = 0; $row -lt 2; $row++) {
        $data = if ($row -eq 0) { $beforeData } else { $afterData }
        $frames = @($data.raw_frames | Where-Object state -eq $state)
        if ($board.StartsWith('transition_') -or $board.StartsWith('turn_')) {
            $center = 0
            for ($i = 1; $i -lt $data.raw_frames.Count; $i++) {
                $current = $data.raw_frames[$i]
                $previous = $data.raw_frames[$i - 1]
                $match = $current.state -eq $state -and $previous.state -ne $state
                if ($board -eq 'turn_left') { $match = $current.facing -lt 0 -and $previous.facing -gt 0 }
                if ($board -eq 'turn_right') { $match = $current.facing -gt 0 -and $previous.facing -lt 0 }
                if ($match) { $center = $i; break }
            }
            if (!$center) { throw "Missing transition $board" }
            $frames = @($data.raw_frames[($center - 1)..($center + 2)])
        }
        if (!$frames.Count) { throw "Missing state $state" }
        for ($column = 0; $column -lt 4; $column++) {
            $frame = $frames[[Math]::Floor(($frames.Count - 1) * $column / 3)]
            $imagePath = Join-Path $root ($frame.path -replace '^res://','')
            $source = [Drawing.Image]::FromFile($imagePath)
            $graphics.DrawImage($source, [Drawing.Rectangle]::new($column * 280, $row * 328 + 28, 280, 300))
            $tag = if ($row -eq 0) { 'BEFORE' } else { 'AFTER' }
            if ($reviewedBoards -contains $board) { $reviewedFrames["$($tag.ToLower()):$($frame.sequence)"] = $true }
            $graphics.DrawString("$tag $($frame.state) #$($frame.sequence)", $font, [Drawing.Brushes]::White, $column * 280, $row * 328)
            $source.Dispose()
        }
    }
    $graphics.Dispose()
    $bitmap.Save((Join-Path $output "$board.png"), [Drawing.Imaging.ImageFormat]::Png)
    $bitmap.Dispose()
}
$rows = foreach ($run in @('before', 'after')) {
    $data = if ($run -eq 'before') { $beforeData } else { $afterData }
    foreach ($frame in $data.raw_frames) {
        $reviewed = $reviewedFrames.ContainsKey("${run}:$($frame.sequence)")
        $note = 'AI 미열람; 원본 PNG를 사람 검수할 것'
        if ($reviewed) {
            $note = switch -Regex ($frame.state) {
                '^walk$' { if ($run -eq 'before') {'부츠/종아리 늘어짐과 좌향 반전 후 다리 접힘 관찰'} else {'동일 프레임의 부츠 늘어짐 감소; 보폭과 골반 리듬의 자연스러움은 미승인'}; break }
                '^attack1' {'팔을 뻗은 단일 원화 유지; 준비/회수의 팔꿈치 변화와 체중 이동 부족'; break }
                '^attack2' {'J1 대비 청록색 의상/허리 장식 변화, 전환 중간 자세 부족'; break }
                '^attack3' {'위로 뻗는 자세는 구별됨; J2→J3 손/머리 위치의 급격한 변화 잔여'; break }
                '^skill1' {'전신은 가드 자세에 가까움; 돌진은 이동과 청록 VFX에 의존'; break }
                '^skill2' {'가드 자세와 보라 VFX가 주로 보임; 백피스트 팔/등 회전 실루엣 부족'; break }
                '^jump' {'상승/하강 전이 확인; 정점의 머리 crop 잘림은 별도 전체 Window 자료 참조'; break }
                '^landing$' {'착지 압축/복귀 확인; 무릎 굽힘과 체중 흡수 자연스러움 미승인'; break }
                '^hit$' {'작은 뒤틀림만 관찰; 가드 팔과 표정 유지로 피격 표현 약함'; break }
                '^ko$' {'전신 원화 회전으로 쓰러짐; 손/무릎의 가드 자세 유지, 전체 Window 자료 참조'; break }
                default {'전환 비교 보드에서 관찰; 사람 승인 아님'}
            }
        }
        [PSCustomObject][ordered]@{
            run=$run; sequence=$frame.sequence; window_frame=$frame.window_frame; state=$frame.state; image=$frame.path
            stimulus=$frame.stimulus; support_residual_px=$frame.support_residual
            joint_distortion='UNVERIFIED'; foot_sliding='UNVERIFIED'; hand_shape_alignment='UNVERIFIED'
            duplicate_silhouette='UNVERIFIED'; transition_jump='UNVERIFIED'; dropped_frames='UNVERIFIED'
            face_ear_ponytail_costume='UNVERIFIED'; human_approval='UNVERIFIED'
            ai_reviewed=$reviewed; ai_observation=$note
            measurement_note=$(if ($frame.support_residual -gt 1.5) {'support residual >1.5px; inspect image'} else {''})
        }
    }
}
$rows | Export-Csv (Join-Path $output 'frame_review.csv') -NoTypeInformation -Encoding UTF8
$font.Dispose()
Write-Output "Created $($states.Count * 2 + 2) before/after boards and $($rows.Count) frame review rows. Human approval remains UNVERIFIED."
