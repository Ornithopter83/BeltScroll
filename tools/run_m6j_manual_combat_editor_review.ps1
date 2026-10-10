[CmdletBinding()]
param(
    [string]$ProjectRoot = '',
    [string]$ReportPath = '.qa_logs/m6j_manual_combat_editor_review.json'
)

$ErrorActionPreference = 'Stop'
$utf8 = New-Object System.Text.UTF8Encoding($false)
[Console]::OutputEncoding = $utf8
$OutputEncoding = $utf8
if ([string]::IsNullOrWhiteSpace($ProjectRoot)) { $ProjectRoot = Split-Path -Parent $PSScriptRoot }
$ProjectRoot = [IO.Path]::GetFullPath($ProjectRoot)

function Resolve-ReviewPath {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return $null }
    if ([IO.Path]::IsPathRooted($Path)) { return [IO.Path]::GetFullPath($Path) }
    return [IO.Path]::GetFullPath((Join-Path $ProjectRoot ($Path -replace '/', '\')))
}

function Read-RequiredValue {
    param([string]$Prompt)
    do { $value = (Read-Host $Prompt).Trim() } while ([string]::IsNullOrWhiteSpace($value))
    return $value
}

function Get-Sha256OrNull {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Test-PngFile {
    param([string]$Path)
    if (-not $Path -or -not (Test-Path -LiteralPath $Path -PathType Leaf) -or [IO.Path]::GetExtension($Path) -ine '.png') { return $false }
    $stream = $null
    try {
        $stream = [IO.File]::OpenRead($Path)
        if ($stream.Length -lt 8) { return $false }
        $signature = New-Object byte[] 8
        return ($stream.Read($signature, 0, 8) -eq 8 -and [BitConverter]::ToString($signature) -eq '89-50-4E-47-0D-0A-1A-0A')
    } catch { return $false }
    finally { if ($stream) { $stream.Dispose() } }
}

function Add-ManualReviewEntry {
    param(
        [string]$Id,
        [string]$Title,
        [string]$Instruction,
        [string]$RequiredInputSource,
        [string]$Application,
        [string]$ExecutablePath
    )
    Write-Host ''
    Write-Host ("[{0}] {1}" -f $Id, $Title) -ForegroundColor Cyan
    Write-Host $Instruction
    $observed = (Read-RequiredValue '직접 수행하고 화면에서 확인했으면 YES, 아니면 NO 입력').ToUpperInvariant()
    $decision = 'UNVERIFIED'
    if ($observed -eq 'YES') {
        $decision = (Read-RequiredValue '검수자 판정 PASS 또는 FAIL').ToUpperInvariant()
        if ($decision -notin @('PASS', 'FAIL')) { $decision = 'UNVERIFIED' }
    }
    $inputSource = Read-RequiredValue ("입력 출처 입력 (요구값: {0})" -f $RequiredInputSource)
    $inputSourceValid = $inputSource -ceq $RequiredInputSource
    $evidenceInput = (Read-Host '사람이 직접 찍은 이 항목의 PNG 화면 증거 절대 경로 입력 (없으면 Enter)').Trim()
    $evidencePath = Resolve-ReviewPath $evidenceInput
    $evidenceHash = $null
    $evidenceValid = $false
    if (Test-PngFile $evidencePath) {
        $evidenceHash = Get-Sha256OrNull $evidencePath
        $evidenceValid = ((Get-Item -LiteralPath $evidencePath).Length -gt 0 -and $evidenceHash -match '^[0-9a-f]{64}$')
    }
    $reviewer = Read-RequiredValue '검수자 이름 또는 식별자 입력'
    $visualApproval = (Read-RequiredValue '증거 이미지를 직접 열어 이 항목을 눈으로 확인했으면 I_VISUALLY_APPROVE 입력').ToUpperInvariant() -ceq 'I_VISUALLY_APPROVE'
    $eligible = ($observed -eq 'YES' -and $decision -in @('PASS', 'FAIL') -and $inputSourceValid -and $evidenceValid -and $visualApproval)
    $status = if (-not $eligible) { 'BLOCKED_UNVERIFIED' } elseif ($decision -eq 'PASS') { 'PASS' } else { 'FAIL' }
    return [pscustomobject]@{
        id = $Id
        title = $Title
        application = $Application
        executablePath = $ExecutablePath
        inputSource = $inputSource
        requiredInputSource = $RequiredInputSource
        inputSourceValid = $inputSourceValid
        observedByReviewer = ($observed -eq 'YES')
        reviewerDecision = $decision
        reviewer = $reviewer
        visualApproval = $visualApproval
        evidence = if ($evidenceValid) { $evidencePath } else { $null }
        evidenceSha256 = $evidenceHash
        evidenceValid = $evidenceValid
        status = $status
        observedAtUtc = [DateTimeOffset]::UtcNow.ToString('o')
    }
}

function Write-ReviewReport {
    param([object]$Report, [string]$Path)
    $full = Resolve-ReviewPath $Path
    $parent = Split-Path -Parent $full
    if (-not (Test-Path -LiteralPath $parent -PathType Container)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
    $json = ConvertTo-Json -InputObject $Report -Depth 12
    [IO.File]::WriteAllText($full, $json + [Environment]::NewLine, $utf8)
    Write-Host ("검수 보고서: {0}" -f $full)
}

$headSha = $null
try {
    $gitOutput = @(& git -C $ProjectRoot rev-parse --verify 'HEAD^{commit}' 2>$null)
    if ($LASTEXITCODE -eq 0) { $candidateSha = ([string]::Join('', [string[]]$gitOutput)).Trim().ToLowerInvariant(); if ($candidateSha -match '^[0-9a-f]{40,64}$') { $headSha = $candidateSha } }
} catch { $headSha = $null }

$report = [ordered]@{
    schema = 'm6j-manual-combat-editor-review/v1'
    status = 'BLOCKED_UNVERIFIED'
    generatedAtUtc = [DateTimeOffset]::UtcNow.ToString('o')
    projectRoot = $ProjectRoot
    targetCommitSha = $headSha
    attendedInteractiveSession = $false
    policy = [ordered]@{
        humanPhysicalInputRequired = $true
        humanVisualApprovalRequired = $true
        automatedInputAccepted = $false
        automatedCaptureAccepted = $false
        unattendedExecutionCanPass = $false
    }
    reviewer = $null
    godotExecutable = $null
    editorExecutable = $null
    savedOverrideFile = $null
    editorButton = '전투 연습장 실행'
    checks = @()
    summary = '대화형 사람 검수를 완료하지 않았거나 필수 화면 증거가 누락되어 확인되지 않음.'
}

if ([Environment]::UserInteractive -and -not [Console]::IsInputRedirected -and -not [Console]::IsOutputRedirected) {
    $report.attendedInteractiveSession = $true
    Write-Host 'M6J 수동 전투/편집기 검수. 이 스크립트는 입력 전송, 앱 실행, 화면 캡처를 하지 않습니다.' -ForegroundColor Yellow
    Write-Host '각 화면 동작은 검수자가 직접 하고, PNG를 직접 캡처해 파일을 열어 본 뒤에만 판정하세요.'
    $sessionReviewer = Read-RequiredValue '검수자 이름 또는 식별자'
    $report.reviewer = $sessionReviewer
    $godotInput = Read-RequiredValue 'Godot 4.7.2 편집기 실행 파일 godot*.exe 절대 경로'
    $godotPath = Resolve-ReviewPath $godotInput
    $editorInput = Read-RequiredValue '독립 BeltScrollEditor.exe 절대 경로'
    $editorPath = Resolve-ReviewPath $editorInput
    $overrideInput = Read-RequiredValue '저장 및 적용할 data/editor/overrides.json 절대 경로'
    $overridePath = Resolve-ReviewPath $overrideInput
    $report.godotExecutable = [ordered]@{ path = $godotPath; sha256 = Get-Sha256OrNull $godotPath; exists = [bool]($godotPath -and (Test-Path -LiteralPath $godotPath -PathType Leaf) -and [IO.Path]::GetExtension($godotPath) -ieq '.exe' -and [IO.Path]::GetFileName($godotPath) -like 'godot*.exe') }
    $report.editorExecutable = [ordered]@{ path = $editorPath; sha256 = Get-Sha256OrNull $editorPath; exists = [bool]($editorPath -and (Test-Path -LiteralPath $editorPath -PathType Leaf) -and [IO.Path]::GetExtension($editorPath) -ieq '.exe' -and [IO.Path]::GetFileName($editorPath) -ieq 'BeltScrollEditor.exe') }
    $report.savedOverrideFile = [ordered]@{ path = $overridePath; sha256BeforeEdit = Get-Sha256OrNull $overridePath; sha256AfterSave = $null; exists = [bool]($overridePath -and (Test-Path -LiteralPath $overridePath -PathType Leaf)) }
    Write-Host ''
    Write-Host '먼저 Godot 편집기에서 프로젝트를 연 다음 scenes/review/m6i_combat_test_arena.tscn을 활성 씬으로 선택하고 F6을 누르세요.' -ForegroundColor Green
    $godotWindow = Read-RequiredValue '실제 Godot 게임 창이 열린 것을 확인한 뒤 창 제목 입력'
    $godotChecks = @(
        @('godot_j_three_combo', 'Godot F6: 물리 J 연타 3콤보', 'J를 물리 키보드로 세 번 연속 눌러 1→2→3타 콤보와 종료 후 초기화를 확인합니다.', 'physical-keyboard'),
        @('godot_num4', 'Godot F6: Num4', '숫자열 4가 아닌 키패드 Num4를 물리적으로 눌러 돌진 phase와 쿨다운 변화를 확인합니다.', 'physical-keyboard'),
        @('godot_num5', 'Godot F6: Num5', '키패드 Num5를 물리적으로 눌러 회전 공격 phase와 쿨다운 변화를 확인합니다.', 'physical-keyboard'),
        @('godot_enemy_counterattack', 'Godot F6: 적 반격', 'Raider가 실제로 공격해 플레이어 HP가 변하는 장면을 확인합니다.', 'physical-keyboard'),
        @('godot_hit_stun', 'Godot F6: 피격 경직', '피격 뒤 넉백/경직 잔여 시간이 표시되고 경직 중 입력이 제한되는지 확인합니다.', 'physical-keyboard'),
        @('godot_recovery', 'Godot F6: 경직 복귀', '경직 타이머가 끝난 뒤 이동 또는 공격 입력이 다시 처리되는지 확인합니다.', 'physical-keyboard'),
        @('godot_restart_r', 'Godot F6: R 재시작', '물리 R 키로 씬을 재시작하고 실제 플레이어/적/HP가 초기 상태로 돌아오는지 확인합니다.', 'physical-keyboard')
    )
    foreach ($check in $godotChecks) {
        $entry = Add-ManualReviewEntry -Id $check[0] -Title $check[1] -Instruction $check[2] -RequiredInputSource $check[3] -Application 'Godot editor F6 current-scene run' -ExecutablePath $godotPath
        $entry | Add-Member -NotePropertyName windowTitle -NotePropertyValue $godotWindow
        $entry | Add-Member -NotePropertyName executableSha256 -NotePropertyValue $report.godotExecutable.sha256
        $report.checks += $entry
    }

    Write-Host ''
    Write-Host '이제 실제 WinForms 독립 편집기를 직접 열고, 저장된 편집값을 바꾼 뒤 저장하고 버튼을 클릭하세요.' -ForegroundColor Green
    Write-Host '버튼은 게임 창이 아니라 WinForms 편집기의 [전투 연습장 실행]이어야 합니다.'
    $editorWindow = Read-RequiredValue 'WinForms 편집기 창 제목을 직접 확인해 입력'
    $fieldName = Read-RequiredValue '실제로 수정할 편집 필드명 (예: Player.attack_damage)'
    $beforeValue = Read-RequiredValue '수정 전 표시 값'
    $afterValue = Read-RequiredValue '수정 후 저장할 값'
    $saveEntry = Add-ManualReviewEntry -Id 'editor_save_value' -Title '독립 편집기: 값 편집 및 저장' -Instruction ("{0}을 {1}에서 {2}로 직접 바꾸고 저장합니다. 저장 상태/경로를 화면에서 확인하세요." -f $fieldName, $beforeValue, $afterValue) -RequiredInputSource 'physical-mouse-and-keyboard' -Application 'standalone WinForms editor' -ExecutablePath $editorPath
    $saveEntry | Add-Member -NotePropertyName windowTitle -NotePropertyValue $editorWindow
    $saveEntry | Add-Member -NotePropertyName field -NotePropertyValue $fieldName
    $saveEntry | Add-Member -NotePropertyName beforeValue -NotePropertyValue $beforeValue
    $saveEntry | Add-Member -NotePropertyName savedValue -NotePropertyValue $afterValue
    $saveEntry | Add-Member -NotePropertyName executableSha256 -NotePropertyValue $report.editorExecutable.sha256
    $report.checks += $saveEntry
    $report.savedOverrideFile.sha256AfterSave = Get-Sha256OrNull $overridePath
    $buttonEntry = Add-ManualReviewEntry -Id 'editor_arena_button_launch' -Title '독립 편집기: 연습장 버튼으로 실행' -Instruction '저장 후 편집기의 [전투 연습장 실행] 버튼을 마우스로 직접 클릭합니다. 별도 Godot 프로세스가 실제로 열리는지 확인하세요.' -RequiredInputSource 'physical-mouse' -Application 'standalone WinForms editor button: 전투 연습장 실행' -ExecutablePath $editorPath
    $buttonEntry | Add-Member -NotePropertyName windowTitle -NotePropertyValue $editorWindow
    $buttonEntry | Add-Member -NotePropertyName executableSha256 -NotePropertyValue $report.editorExecutable.sha256
    $report.checks += $buttonEntry
    $appliedWindow = Read-RequiredValue 'WinForms 버튼으로 열린 실제 Godot 게임 창 제목을 직접 확인해 입력'
    $appliedEntry = Add-ManualReviewEntry -Id 'editor_saved_value_applied' -Title '독립 편집기 실행: 저장값 적용 확인' -Instruction ("별도 Godot 연습장에서 {0}이 저장된 값 {1}로 실제 적용됐는지 화면에서 확인합니다." -f $fieldName, $afterValue) -RequiredInputSource 'human-visual-observation' -Application 'Godot process launched by WinForms arena button' -ExecutablePath $godotPath
    $appliedEntry | Add-Member -NotePropertyName windowTitle -NotePropertyValue $appliedWindow
    $appliedEntry | Add-Member -NotePropertyName executableSha256 -NotePropertyValue $report.godotExecutable.sha256
    $appliedEntry | Add-Member -NotePropertyName field -NotePropertyValue $fieldName
    $appliedEntry | Add-Member -NotePropertyName expectedAppliedValue -NotePropertyValue $afterValue
    $appliedEntry | Add-Member -NotePropertyName savedOverrideSha256 -NotePropertyValue $report.savedOverrideFile.sha256AfterSave
    $report.checks += $appliedEntry
} else {
    Write-Warning '표준 콘솔 입력이 가능한 대화형 세션이 아닙니다. 수동 검수를 진행하지 않고 BLOCKED_UNVERIFIED를 기록합니다.'
}

$checks = @($report.checks)
$requiredCount = 10
$evidencePaths = @($checks | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_.evidence) } | ForEach-Object { ([string]$_.evidence).ToLowerInvariant() } | Sort-Object -Unique)
$evidenceHashes = @($checks | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_.evidenceSha256) } | ForEach-Object { ([string]$_.evidenceSha256).ToLowerInvariant() } | Sort-Object -Unique)
$hasMissing = (-not $report.attendedInteractiveSession -or $checks.Count -ne $requiredCount -or -not $report.targetCommitSha -or
    -not $report.godotExecutable.exists -or -not $report.godotExecutable.sha256 -or
    -not $report.editorExecutable.exists -or -not $report.editorExecutable.sha256 -or
    -not $report.savedOverrideFile.exists -or -not $report.savedOverrideFile.sha256AfterSave -or
    $evidencePaths.Count -ne $requiredCount -or $evidenceHashes.Count -ne $requiredCount)
if ($hasMissing -or @($checks | Where-Object { $_.status -eq 'BLOCKED_UNVERIFIED' }).Count -gt 0) {
    $report.status = 'BLOCKED_UNVERIFIED'
    $report.summary = '사람의 대화형 검수, 실행 파일/설정 SHA-256, 필수 항목별 PNG 증거와 시각 판정 중 하나 이상이 누락되어 확인되지 않음.'
} elseif (@($checks | Where-Object { $_.status -eq 'FAIL' }).Count -gt 0) {
    $report.status = 'FAIL'
    $report.summary = '검수자가 화면을 직접 확인한 항목 중 FAIL이 있습니다. 세부 결과를 확인하세요.'
} else {
    $report.status = 'PASS_HUMAN_REVIEW'
    $report.summary = '모든 항목을 사람이 직접 조작/관찰하고 각 PNG 증거를 직접 시각 승인했습니다.'
}

Write-ReviewReport -Report $report -Path $ReportPath
if ($report.status -eq 'PASS_HUMAN_REVIEW') { exit 0 }
if ($report.status -eq 'FAIL') { exit 1 }
exit 2
