[CmdletBinding()]
param(
    [string]$ProjectRoot,
    [string]$GodotPath,
    [string]$OutputDirectory
)

$ErrorActionPreference = 'Stop'
$utf8 = New-Object System.Text.UTF8Encoding($false)
[Console]::OutputEncoding = $utf8
$OutputEncoding = $utf8

if ([string]::IsNullOrWhiteSpace($ProjectRoot)) {
    $ProjectRoot = Split-Path -Parent $PSScriptRoot
}
$ProjectRoot = [IO.Path]::GetFullPath($ProjectRoot)
$projectFile = Join-Path $ProjectRoot 'project.godot'
$recorder = Join-Path $ProjectRoot 'tools\capture_manual_input_audit.gd'
if (-not (Test-Path -LiteralPath $projectFile -PathType Leaf)) { throw "Godot project not found: $projectFile" }
if (-not (Test-Path -LiteralPath $recorder -PathType Leaf)) { throw "Input recorder not found: $recorder" }

if ([string]::IsNullOrWhiteSpace($GodotPath)) {
    $godotCommand = Get-Command godot -ErrorAction SilentlyContinue
    if ($null -eq $godotCommand) { $godotCommand = Get-Command godot4 -ErrorAction SilentlyContinue }
    if ($null -eq $godotCommand) { throw 'Godot executable not found. Pass -GodotPath explicitly or add godot to PATH.' }
    $GodotPath = $godotCommand.Source
}
if (-not (Test-Path -LiteralPath $GodotPath -PathType Leaf)) { throw "Godot executable not found: $GodotPath" }

if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
    $OutputDirectory = Join-Path ([IO.Path]::GetTempPath()) ('BeltScrollManualInput_' + (Get-Date -Format 'yyyyMMdd_HHmmss'))
}
$OutputDirectory = [IO.Path]::GetFullPath($OutputDirectory)
[void][IO.Directory]::CreateDirectory($OutputDirectory)
$logPath = Join-Path $OutputDirectory 'input-events.jsonl'
$reviewPath = Join-Path $OutputDirectory 'manual-review.json'
$checklist = @('Num1','Num2','Num3','Num4','Num5','Num6','Num7','Num8','Num9','W','A','S','D','Space','Shift','J','MouseLeft','Esc')
$unattended = [Environment]::UserInteractive -eq $false -or [Console]::IsInputRedirected

if ($unattended) {
    $blockedControls = [ordered]@{}
    foreach ($control in $checklist) { $blockedControls[$control] = 'not_tested' }
    $blockedReview = [ordered]@{
        status = 'BLOCKED_UNVERIFIED'
        process_exit_code = $null
        reviewed_at_local = (Get-Date).ToString('o')
        reviewer_observed_physical_devices = $false
        focus_loss_and_return_observed = $false
        controls = $blockedControls
        reviewer_notes = 'Unattended or redirected console: manual inspection was not possible; the game was not launched.'
        input_log = $logPath
        physical_origin_proven_by_log = $false
    }
    [IO.File]::WriteAllText($reviewPath, (ConvertTo-Json -InputObject $blockedReview -Depth 5), $utf8)
    Write-Output '검수 상태: BLOCKED_UNVERIFIED (무인 실행에서는 검사자 입력을 확인할 수 없어 본편을 실행하지 않았습니다.)'
    Write-Output "수동 결과: $reviewPath"
    exit 2
}

Write-Output '수동 입력 인수 검수를 시작합니다.'
Write-Output 'Godot 본편 1920×1080 창이 열리면 Num1~9, WASD, Space, Shift, J, 좌클릭, Esc를 실제 장치로 확인하세요.'
Write-Output '창 포커스를 잃었다가 복귀하는 동작도 확인하세요. 자동/합성 입력은 직접 입력으로 간주하지 마세요.'
Write-Output '로그만으로 물리 장치 출처를 증명할 수 없습니다. 화면 반응은 검사자가 직접 확인하고 종료 후 기록합니다.'
Write-Output "이벤트 로그: $logPath"

function Quote-NativeArgument([string]$Value) {
    '"' + $Value.Replace('"', '\\"') + '"'
}
$arguments = @(
    '--path', $ProjectRoot,
    '--script', $recorder,
    '--windowed',
    '--resolution', '1920x1080',
    '--', '--audit-output', $logPath
) | ForEach-Object { Quote-NativeArgument ([string]$_) }
$process = Start-Process -FilePath $GodotPath -ArgumentList $arguments -PassThru -Wait

$results = [ordered]@{}
Write-Output ''
Write-Output '각 입력의 화면 반응을 실제로 확인했는지 기록합니다. 가능한 값: pass / fail / not_tested.'
foreach ($control in $checklist) {
    $answer = (Read-Host "$control 결과").Trim().ToLowerInvariant()
    if ($answer -notin @('pass','fail','not_tested')) { $answer = 'not_tested' }
    $results[$control] = $answer
}
$focusAnswer = (Read-Host '포커스 상실/복귀 구분을 직접 확인했습니까? (yes/no)').Trim().ToLowerInvariant()
$physicalAnswer = (Read-Host '요청된 키/마우스를 실제 장치로 조작하는 것을 직접 확인했습니까? (yes/no)').Trim().ToLowerInvariant()
$notes = Read-Host '검사자/관찰 메모 (선택)'

$allPass = @($results.Values | Where-Object { $_ -ne 'pass' }).Count -eq 0
$status = 'BLOCKED_UNVERIFIED'
if ($process.ExitCode -eq 0 -and $allPass -and $focusAnswer -eq 'yes' -and $physicalAnswer -eq 'yes') {
    $status = 'MANUAL_REVIEW_RECORDED'
}
$review = [ordered]@{
    status = $status
    process_exit_code = $process.ExitCode
    reviewed_at_local = (Get-Date).ToString('o')
    reviewer_observed_physical_devices = ($physicalAnswer -eq 'yes')
    focus_loss_and_return_observed = ($focusAnswer -eq 'yes')
    controls = $results
    reviewer_notes = $notes
    input_log = $logPath
    physical_origin_proven_by_log = $false
}
[IO.File]::WriteAllText($reviewPath, (ConvertTo-Json -InputObject $review -Depth 5), $utf8)
Write-Output "검수 상태: $status"
Write-Output "수동 결과: $reviewPath"
if ($status -eq 'BLOCKED_UNVERIFIED') { exit 2 }
exit 0
