[CmdletBinding()]
param(
    [string]$ProjectRoot,
    [string]$GodotPath,
    [string]$OutputDirectory,
    [switch]$DecisionProbe,
    [int]$ProbeProcessExitCode = 0,
    [string]$ProbeControlsBase64 = 'e30=',
    [switch]$ProbeFocusConfirmed,
    [switch]$ProbePhysicalConfirmed,
    [switch]$ProbeUnattended
)

$ErrorActionPreference = 'Stop'
$utf8 = New-Object System.Text.UTF8Encoding($false)
[Console]::OutputEncoding = $utf8
$OutputEncoding = $utf8

$inputControls = @('Num1','Num2','Num3','Num4','Num5','Num6','Num7','Num8','Num9','W','A','S','D','Space','Shift','J','MouseLeft','Esc')
$reviewControls = @(
    'Display1920x1080', 'Fullscreen', 'ThreeTimesScale', 'WindowFocusLossReturn',
    'PlayerHealthBar', 'RaiderHealthBars', 'Skill4AndSkill5Differ',
    'EditorManualCreate', 'EditorManualModify', 'EditorManualSave', 'EditorManualReopen', 'EditorGameReapply',
    'ArtIdentity', 'RunStride', 'TurnRotation', 'FramePops'
)

function Get-ManualInputDecision {
    param(
        [int]$ProcessExitCode,
        [System.Collections.IDictionary]$Controls,
        [bool]$FocusConfirmed,
        [bool]$PhysicalConfirmed,
        [bool]$Unattended
    )
    if ($Unattended) { return 'BLOCKED_UNVERIFIED' }
    if ($ProcessExitCode -ne 0 -or -not $FocusConfirmed -or -not $PhysicalConfirmed) { return 'BLOCKED_UNVERIFIED' }
    foreach ($name in $reviewControls) {
        if (-not $Controls.Contains($name) -or $Controls[$name] -ne 'pass') { return 'BLOCKED_UNVERIFIED' }
    }
    foreach ($name in $inputControls) {
        if (-not $Controls.Contains($name) -or $Controls[$name] -ne 'pass') { return 'BLOCKED_UNVERIFIED' }
    }
    return 'MANUAL_REVIEW_RECORDED'
}

if ($DecisionProbe) {
    $probeJson = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($ProbeControlsBase64))
    $probeControls = ConvertFrom-Json -InputObject $probeJson
    $map = [ordered]@{}
    foreach ($property in $probeControls.PSObject.Properties) { $map[$property.Name] = [string]$property.Value }
    # Probe mode exercises only the pure decision rule; it cannot launch the game or write a review.
    $isUnattended = [bool]$ProbeUnattended
    $decision = Get-ManualInputDecision -ProcessExitCode $ProbeProcessExitCode -Controls $map -FocusConfirmed $ProbeFocusConfirmed -PhysicalConfirmed $ProbePhysicalConfirmed -Unattended $isUnattended
    [pscustomobject]@{ status = $decision; exit_code = if ($decision -eq 'BLOCKED_UNVERIFIED') { 2 } else { 0 } } | ConvertTo-Json -Compress
    exit 0
}

if ([string]::IsNullOrWhiteSpace($ProjectRoot)) { $ProjectRoot = Split-Path -Parent $PSScriptRoot }
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
    $OutputDirectory = Join-Path ([IO.Path]::GetTempPath()) ('BeltScrollManualInput_' + (Get-Date -Format 'yyyyMMdd_HHmmss_fff'))
}
$OutputDirectory = [IO.Path]::GetFullPath($OutputDirectory)
[void][IO.Directory]::CreateDirectory($OutputDirectory)
# Never truncate a prior event log or user review. Use an isolated child folder on collisions.
$sessionDirectory = $OutputDirectory
if ((Test-Path -LiteralPath (Join-Path $sessionDirectory 'input-events.jsonl')) -or (Test-Path -LiteralPath (Join-Path $sessionDirectory 'manual-review.json'))) {
    do {
        $sessionDirectory = Join-Path $OutputDirectory ('session_' + (Get-Date -Format 'yyyyMMdd_HHmmss_fff') + '_' + [Guid]::NewGuid().ToString('N').Substring(0,8))
    } while (Test-Path -LiteralPath $sessionDirectory)
    [void][IO.Directory]::CreateDirectory($sessionDirectory)
}
$logPath = Join-Path $sessionDirectory 'input-events.jsonl'
$reviewPath = Join-Path $sessionDirectory 'manual-review.json'

$unattended = [Environment]::UserInteractive -eq $false -or [Console]::IsInputRedirected
if ($unattended) {
    $blockedControls = [ordered]@{}
    foreach ($control in ($inputControls + $reviewControls)) { $blockedControls[$control] = 'not_tested' }
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
        automated_input_or_gui_self_test_substitutes_for_human_acceptance = $false
    }
    [IO.File]::WriteAllText($reviewPath, (ConvertTo-Json -InputObject $blockedReview -Depth 5), $utf8)
    Write-Output '검수 상태: BLOCKED_UNVERIFIED (무인 실행에서는 검사자 입력을 확인할 수 없어 본편을 실행하지 않았습니다.)'
    Write-Output "수동 결과: $reviewPath"
    exit 2
}

Write-Output '수동 통합 인수 검수를 시작합니다.'
Write-Output '본편 창이 1920×1080 전체화면인지, 캐릭터가 기준 원화의 3배 크기로 표시되는지 먼저 직접 확인하세요.'
Write-Output 'Num1~9, WASD, Space, Shift, J, 마우스 좌클릭, Esc를 실제 장치로 조작하고 각 화면 반응을 확인하세요.'
Write-Output '창 포커스를 잃었다가 복귀하고 입력이 정상 회복되는지 확인하세요. 양측 체력바와 Num4/Num5 스킬 표시·동작 차이도 확인하세요.'
Write-Output '별도 편집기에서 생성·수정·저장·재열기·게임 재적용을 수동 수행하고 원화 identity·보폭·회전·프레임 팝을 검수하세요.'
Write-Output '자동 입력, 입력 로그, 편집기 self-test 또는 자동 GUI 시험은 사람의 직접 확인을 대체하지 않습니다.'
Write-Output "증거 폴더: $sessionDirectory"
Write-Output "이벤트 로그: $logPath"

function Quote-NativeArgument([string]$Value) { '"' + $Value.Replace('"', '\"') + '"' }
$arguments = @(
    '--path', $ProjectRoot,
    '--script', $recorder,
    '--fullscreen',
    '--resolution', '1920x1080',
    '--', '--audit-output', $logPath
) | ForEach-Object { Quote-NativeArgument ([string]$_) }
$process = Start-Process -FilePath $GodotPath -ArgumentList $arguments -PassThru -Wait

$results = [ordered]@{}
Write-Output ''
Write-Output '각 결과를 실제 화면을 직접 확인한 뒤 pass / fail / not_tested로 기록합니다.'
foreach ($control in ($inputControls + $reviewControls)) {
    $answer = (Read-Host "$control 결과").Trim().ToLowerInvariant()
    if ($answer -notin @('pass','fail','not_tested')) { $answer = 'not_tested' }
    $results[$control] = $answer
}
$focusAnswer = (Read-Host '창 포커스 상실/복귀 및 복귀 후 입력 회복을 직접 확인했습니까? (yes/no)').Trim().ToLowerInvariant()
$physicalAnswer = (Read-Host '요청된 키/마우스를 실제 장치로 조작하는 것을 직접 확인했습니까? (yes/no)').Trim().ToLowerInvariant()
$notes = Read-Host '검사자, 관찰 사항 및 캡처 파일 경로 (선택)'

$focusConfirmed = $focusAnswer -eq 'yes' -and $results['WindowFocusLossReturn'] -eq 'pass'
$status = Get-ManualInputDecision -ProcessExitCode $process.ExitCode -Controls $results -FocusConfirmed $focusConfirmed -PhysicalConfirmed ($physicalAnswer -eq 'yes') -Unattended $false
$review = [ordered]@{
    status = $status
    process_exit_code = $process.ExitCode
    reviewed_at_local = (Get-Date).ToString('o')
    requested_display = [ordered]@{ width = 1920; height = 1080; fullscreen = $true; character_scale = '3x'; directly_observed = $results['Display1920x1080'] -eq 'pass' -and $results['Fullscreen'] -eq 'pass' -and $results['ThreeTimesScale'] -eq 'pass' }
    reviewer_observed_physical_devices = ($physicalAnswer -eq 'yes')
    focus_loss_and_return_observed = $focusConfirmed
    controls = $results
    reviewer_notes = $notes
    input_log = $logPath
    physical_origin_proven_by_log = $false
    automated_input_or_gui_self_test_substitutes_for_human_acceptance = $false
}
[IO.File]::WriteAllText($reviewPath, (ConvertTo-Json -InputObject $review -Depth 6), $utf8)
Write-Output "검수 상태: $status"
Write-Output "수동 결과: $reviewPath"
if ($status -eq 'BLOCKED_UNVERIFIED') { exit 2 }
exit 0
