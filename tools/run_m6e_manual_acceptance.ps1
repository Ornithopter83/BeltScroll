[CmdletBinding()]
param(
    [string]$ProjectRoot = '',
    [string]$GodotPath = '',
    [string]$EditorPath = '',
    [string]$OutputDirectory = ''
)

$ErrorActionPreference = 'Stop'
$utf8 = New-Object System.Text.UTF8Encoding($false)
[Console]::OutputEncoding = $utf8
$OutputEncoding = $utf8

if ([string]::IsNullOrWhiteSpace($ProjectRoot)) { $ProjectRoot = Split-Path -Parent $PSScriptRoot }
$ProjectRoot = [IO.Path]::GetFullPath($ProjectRoot)
if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
    $OutputDirectory = Join-Path ([IO.Path]::GetTempPath()) ('BeltScrollM6E_' + (Get-Date -Format 'yyyyMMdd_HHmmss_fff'))
}
$OutputDirectory = [IO.Path]::GetFullPath($OutputDirectory)
[void][IO.Directory]::CreateDirectory($OutputDirectory)
if ((Test-Path -LiteralPath (Join-Path $OutputDirectory 'input-events.jsonl')) -or
    (Test-Path -LiteralPath (Join-Path $OutputDirectory 'manual-review.json')) -or
    (Test-Path -LiteralPath (Join-Path $OutputDirectory 'm6d_manual_acceptance.json'))) {
    do {
        $OutputDirectory = Join-Path $OutputDirectory ('session_' + (Get-Date -Format 'yyyyMMdd_HHmmss_fff') + '_' + [Guid]::NewGuid().ToString('N').Substring(0,8))
    } while (Test-Path -LiteralPath $OutputDirectory)
    [void][IO.Directory]::CreateDirectory($OutputDirectory)
}
$reviewPath = Join-Path $OutputDirectory 'm6d_manual_acceptance.json'
$manualReviewPath = Join-Path $OutputDirectory 'manual-review.json'
$inputLog = Join-Path $OutputDirectory 'input-events.jsonl'
$playLog = Join-Path $OutputDirectory 'physical-playthrough.log'
$playErrorLog = Join-Path $OutputDirectory 'physical-playthrough-error.log'
$automaticFrameSheet = Join-Path $ProjectRoot 'assets\art\review\m6d_full_playthrough_evidence.png'
$inputRecorder = Join-Path $ProjectRoot 'tools\capture_manual_input_audit.gd'
$playthrough = Join-Path $ProjectRoot 'tools\capture_m6d_full_playthrough.gd'
$projectFile = Join-Path $ProjectRoot 'project.godot'

function Write-BlockedReport([string]$Reason) {
    $report = [ordered]@{
        status = 'BLOCKED_UNVERIFIED'
        generatedAtUtc = [DateTime]::UtcNow.ToString('o')
        projectRoot = $ProjectRoot
        mode = 'manual-human-only'
        blockedReason = $Reason
        nextActions = @('대화형 Windows PowerShell 창에서 검수자가 직접 실행한다.','게임·편집기 GUI를 실제 조작한 뒤 각 질문에 pass와 기존 증거 파일 경로를 기록한다.','미확인 항목은 통과로 바꾸지 말고 별도 사람 검수를 마친 후 다시 실행한다.')
        physicalKeyboard = @{ status='NOT_VERIFIED'; method='physical-keyboard'; reviewer=''; observedAt=''; checks=@(foreach ($key in 1..9) { @{ name="Num$key"; status='not_tested'; evidence=@() } }) }
        display = @{ status='NOT_VERIFIED'; method='human-observed'; reviewer=''; observedAt=''; checks=@(@{name='fullscreen';status='not_tested';evidence=@()},@{name='three-times-scale';status='not_tested';evidence=@()}) }
        playthrough = @{ status='NOT_VERIFIED'; method='physical-keyboard'; checks=@(@{name='boss-encounter';status='not_tested';evidence=@()},@{name='boss-defeated';status='not_tested';evidence=@()},@{name='restart';status='not_tested';evidence=@()},@{name='player-defeat';status='not_tested';evidence=@()}) }
        editorGuiRoundtrip = @{ status='NOT_VERIFIED'; method='human-gui'; reviewer=''; observedAt=''; checks=@(@{name='create';status='not_tested';evidence=@()},@{name='edit';status='not_tested';evidence=@()},@{name='save-close';status='not_tested';evidence=@()},@{name='reopen-verify';status='not_tested';evidence=@()},@{name='apply-to-game';status='not_tested';evidence=@()}) }
        evidenceHashes = @()
        physicalOriginProvenByLog = $false
        automatedInputOrCaptureSubstitutesForHumanAcceptance = $false
        selfTestUsedAsHumanEvidence = $false
    }
    [IO.File]::WriteAllText($reviewPath, (ConvertTo-Json -InputObject $report -Depth 10), $utf8)
    [IO.File]::WriteAllText($manualReviewPath, (ConvertTo-Json -InputObject $report -Depth 10), $utf8)
    Write-Output "검수 상태: BLOCKED_UNVERIFIED ($Reason)"
    Write-Output "미확인 보고서: $reviewPath"
    exit 2
}
function Quote-NativeArgument([string]$Value) { '"' + $Value.Replace('"', '\"') + '"' }

# Refuse before starting any GUI if this process cannot collect a real reviewer's answers.
if ([Environment]::UserInteractive -eq $false -or [Console]::IsInputRedirected) {
    Write-BlockedReport '무인 또는 표준 입력 리디렉션 세션이므로 GUI를 실행하지 않았다.'
}
if (-not (Test-Path -LiteralPath $projectFile -PathType Leaf) -or -not (Test-Path -LiteralPath $inputRecorder -PathType Leaf) -or -not (Test-Path -LiteralPath $playthrough -PathType Leaf)) {
    Write-BlockedReport '프로젝트 또는 수동 관찰 스크립트가 없어 실행할 수 없다.'
}
if ([string]::IsNullOrWhiteSpace($GodotPath)) {
    $godotCommand = Get-Command godot -ErrorAction SilentlyContinue
    if ($null -eq $godotCommand) { $godotCommand = Get-Command godot4 -ErrorAction SilentlyContinue }
    if ($null -eq $godotCommand) { Write-BlockedReport 'Godot 실행 파일을 찾지 못했다. -GodotPath를 지정해 다시 실행한다.' }
    $GodotPath = $godotCommand.Source
}
if (-not (Test-Path -LiteralPath $GodotPath -PathType Leaf)) { Write-BlockedReport "Godot 실행 파일이 없다: $GodotPath" }
if (-not [string]::IsNullOrWhiteSpace($EditorPath)) {
    if (-not [IO.Path]::IsPathRooted($EditorPath)) { $EditorPath = Join-Path $ProjectRoot $EditorPath }
    $EditorPath = [IO.Path]::GetFullPath($EditorPath)
    if (-not (Test-Path -LiteralPath $EditorPath -PathType Leaf)) { Write-BlockedReport "지정한 편집기 실행 파일이 없다: $EditorPath" }
}

Write-Output 'M6E 실제 사람 수동 인수를 시작합니다. Num1~9는 실제 키보드로 눌렀다 놓고 게임 반응을 직접 확인합니다.'
Write-Output '첫 번째 게임 창에서 전체화면·1920×1080 및 원화 기준 3배 표시를 확인한 뒤 Num1~9를 확인하고 창을 직접 닫으세요.'
Write-Output "증거 폴더: $OutputDirectory"
$inputArgs = @('--path', $ProjectRoot, '--script', $inputRecorder, '--fullscreen', '--resolution', '1920x1080', '--', '--audit-output', $inputLog) | ForEach-Object { Quote-NativeArgument ([string]$_) }
$inputProcess = Start-Process -FilePath $GodotPath -ArgumentList ($inputArgs -join ' ') -PassThru -Wait

Write-Output ''
Write-Output '이제 두 번째 실제 Window에서 타이틀부터 보스전, 승리, 재시작, 패배까지 진행하세요.'
Write-Output 'Enter로 시작하고 직접 플레이합니다. 승리 화면에서 R로 재시작한 뒤 보스에게 패배하세요. 관찰 종료는 F10입니다.'
Write-Output '관찰기는 입력을 주입하지 않습니다. 자동 프레임 캡처와 이벤트 로그는 보조 자료이며 사람의 화면 확인을 대신하지 않습니다.'
$playArgs = @('--path', $ProjectRoot, '--script', $playthrough, '--fullscreen', '--resolution', '1920x1080', '--', '--manual') | ForEach-Object { Quote-NativeArgument ([string]$_) }
$playProcess = Start-Process -FilePath $GodotPath -ArgumentList ($playArgs -join ' ') -PassThru -Wait -RedirectStandardOutput $playLog -RedirectStandardError $playErrorLog

if ([string]::IsNullOrWhiteSpace($EditorPath)) {
    $EditorPath = Join-Path $ProjectRoot 'dist\BeltScrollEditor.exe'
}
Write-Output ''
Write-Output '외부 편집기 GUI 인수 단계입니다. 새 항목 생성, 수정, 저장 후 닫기, 재열기와 저장값 확인, 게임 재적용을 직접 수행하세요.'
Write-Output '자동 self-test/GUI acceptance는 실행하지 않으며, 통과 증거로 기록하지 않습니다.'
if (Test-Path -LiteralPath $EditorPath -PathType Leaf) {
    Write-Output "편집기를 엽니다: $EditorPath"
    $editorProcess = Start-Process -FilePath $EditorPath -PassThru -Wait
} else {
    Write-Output "편집기 실행 파일을 찾지 못했습니다: $EditorPath (편집기 항목은 미확인으로 남습니다.)"
}

$reviewer = (Read-Host '검수자 이름 (비워두면 모든 사람 확인 항목은 미검증)').Trim()
$reviewerNotes = (Read-Host '사용한 키보드/관찰 메모 (선택)').Trim()
$observedAt = [DateTimeOffset]::Now.ToString('o')
$hashMap = @{}
function Read-ReviewCheck([string]$Name, [string]$Question) {
    Write-Host $Question
    $answer = (Read-Host "$Name 결과 (pass / fail / not_tested)").Trim().ToLowerInvariant()
    if ($answer -notin @('pass','fail','not_tested')) { $answer = 'not_tested' }
    $evidence = (Read-Host "$Name 증거 파일 전체 경로 (미확인이면 비움)").Trim()
    if ([string]::IsNullOrWhiteSpace($reviewer) -or $answer -ne 'pass' -or [string]::IsNullOrWhiteSpace($evidence)) { $answer = if ($answer -eq 'fail') { 'fail' } else { 'not_tested' }; return @{name=$Name;status=$answer;evidence=@()} }
    try {
        if (-not [IO.Path]::IsPathRooted($evidence)) { $evidence = Join-Path $ProjectRoot $evidence }
        $evidence = [IO.Path]::GetFullPath($evidence)
        if (-not (Test-Path -LiteralPath $evidence -PathType Leaf)) { return @{name=$Name;status='not_tested';evidence=@()} }
        $automaticPaths = @($inputLog,$playLog,$playErrorLog,$automaticFrameSheet) | ForEach-Object { [IO.Path]::GetFullPath([string]$_) }
        if ($evidence -in $automaticPaths) { return @{name=$Name;status='not_tested';evidence=@()} }
        $evidenceFile = Get-Item -LiteralPath $evidence
        if ($evidenceFile.Length -le 0 -or (([DateTimeOffset]$evidenceFile.LastWriteTimeUtc).ToUniversalTime() - [DateTimeOffset]::UtcNow).TotalDays -lt -7) { return @{name=$Name;status='not_tested';evidence=@()} }
        $hashMap[$evidence] = (Get-FileHash -LiteralPath $evidence -Algorithm SHA256).Hash.ToLowerInvariant()
        return @{name=$Name;status='PASS';evidence=@($evidence)}
    } catch { return @{name=$Name;status='not_tested';evidence=@()} }
}
function Get-GroupStatus($Checks) {
    if (@($Checks | Where-Object { $_.status -eq 'fail' }).Count -gt 0) { return 'FAIL' }
    if (@($Checks | Where-Object { $_.status -ne 'PASS' }).Count -gt 0) { return 'NOT_VERIFIED' }
    return 'PASS'
}

$physicalChecks = @()
foreach ($key in 1..9) { $physicalChecks += Read-ReviewCheck "Num$key" "Num$key 물리 키를 눌렀다 놓고 해당 본편 반응을 화면에서 직접 확인했습니까? 자동 입력은 인정하지 않습니다." }
$displayChecks = @(
    (Read-ReviewCheck 'fullscreen' '게임 표시가 전체화면이고 화면 잘림/비정상 stretch가 없는 것을 직접 확인했습니까?'),
    (Read-ReviewCheck 'three-times-scale' '원화 기준 3배 크기를 실제 게임 화면에서 직접 확인했습니까?')
)
$playChecks = @(
    (Read-ReviewCheck 'boss-encounter' '타이틀에서 시작해 세 구역/적 진행 후 실제 보스 조우를 직접 관찰했습니까?'),
    (Read-ReviewCheck 'boss-defeated' '실제 플레이로 보스를 쓰러뜨리고 승리 화면을 확인했습니까?'),
    (Read-ReviewCheck 'restart' '승리 화면에서 재시작해 새 게임 시작 상태를 확인했습니까?'),
    (Read-ReviewCheck 'player-defeat' '재시작 뒤 플레이어 패배 화면을 실제 전투 결과로 확인했습니까?')
)
$editorChecks = @(
    (Read-ReviewCheck 'create' '외부 편집기 GUI에서 새 데이터 항목을 생성했습니까?'),
    (Read-ReviewCheck 'edit' '항목을 수정하고 수정값을 확인했습니까?'),
    (Read-ReviewCheck 'save-close' '수정값을 저장한 뒤 편집기를 닫았습니까?'),
    (Read-ReviewCheck 'reopen-verify' '편집기를 다시 열어 저장값이 유지된 것을 확인했습니까?'),
    (Read-ReviewCheck 'apply-to-game' '저장 데이터를 게임에 다시 적용/동기화하고 게임 반영을 확인했습니까?')
)

$physicalMethod = if ($reviewer) { 'physical-keyboard' } else { 'physical-keyboard' }
$report = [ordered]@{
    status = 'BLOCKED_UNVERIFIED'
    generatedAtUtc = [DateTime]::UtcNow.ToString('o')
    targetCommitSha = $null
    mode = 'physical-human-observation'
    reviewer = $reviewer
    reviewerNotes = $reviewerNotes
    physicalKeyboard = @{status=(Get-GroupStatus $physicalChecks);method=$physicalMethod;reviewer=$reviewer;observedAt=$observedAt;checks=$physicalChecks}
    display = @{status=(Get-GroupStatus $displayChecks);method='human-observed';reviewer=$reviewer;observedAt=$observedAt;checks=$displayChecks}
    playthrough = @{status=(Get-GroupStatus $playChecks);method='physical-keyboard';checks=$playChecks;observerLog=$playLog;observerExitCode=$playProcess.ExitCode;automatedCaptureIsHumanApproval=$false}
    editorGuiRoundtrip = @{status=(Get-GroupStatus $editorChecks);method='human-gui';reviewer=$reviewer;observedAt=$observedAt;checks=$editorChecks;editorPath=$EditorPath;selfTestUsedAsHumanEvidence=$false}
    processExitCodes = @{inputRecorder=$inputProcess.ExitCode;physicalPlaythrough=$playProcess.ExitCode}
    observerArtifacts = @{inputEvents=$inputLog;playthroughStdout=$playLog;playthroughStderr=$playErrorLog;physicalOriginProvenByLog=$false}
    evidenceHashes = @($hashMap.Keys | Sort-Object | ForEach-Object { @{path=$_;sha256=$hashMap[$_]} })
    automatedInputOrCaptureSubstitutesForHumanAcceptance = $false
    selfTestUsedAsHumanEvidence = $false
    nextActions = @()
}
try {
    $git = Get-Command git -ErrorAction SilentlyContinue
    if ($git) {
        $sha = @(& git -C $ProjectRoot rev-parse HEAD 2>$null | Select-Object -First 1)
        if ($LASTEXITCODE -eq 0 -and $sha.Count -gt 0) { $report.targetCommitSha = ([string]$sha[0]).Trim() }
    }
} catch { }
if (-not $reviewer) { $report.nextActions += '검수자 부재/이름 미기록: 실제 검수자가 직접 조작하고 이름을 기록해 다시 검수한다.' }
if ((Get-GroupStatus $physicalChecks) -ne 'PASS') { $report.nextActions += 'Num1~9 중 미통과 또는 증거가 없는 물리 키를 직접 확인하고 각 증거 경로를 기록한다.' }
if ((Get-GroupStatus $displayChecks) -ne 'PASS') { $report.nextActions += '전체화면과 3배 표시를 실제 화면에서 확인하고 증거 파일을 연결한다.' }
if ((Get-GroupStatus $playChecks) -ne 'PASS') { $report.nextActions += '타이틀부터 보스 조우·승리·재시작·패배까지 물리 입력으로 수행하고 미확인 결과를 다시 관찰한다.' }
if ((Get-GroupStatus $editorChecks) -ne 'PASS') { $report.nextActions += '외부 편집기 GUI의 생성·수정·저장·닫기·재열기·게임 재적용을 완료하고 단계별 증거를 연결한다.' }
if (-not $report.targetCommitSha) { $report.nextActions += '현재 HEAD SHA를 읽지 못했다. 수동 보고서를 해당 검수 HEAD에 결속해 다시 실행한다.' }
$groups = @($report.physicalKeyboard.status,$report.display.status,$report.playthrough.status,$report.editorGuiRoundtrip.status)
if ($reviewer -and $report.targetCommitSha -and @($groups | Where-Object { $_ -ne 'PASS' }).Count -eq 0 -and $inputProcess.ExitCode -eq 0 -and $playProcess.ExitCode -eq 0) {
    $report.status = 'MANUAL_REVIEW_RECORDED'
} elseif (@($groups | Where-Object { $_ -eq 'FAIL' }).Count -gt 0) {
    $report.status = 'MANUAL_REVIEW_FAILED'
} else {
    $report.status = 'BLOCKED_UNVERIFIED'
}
[IO.File]::WriteAllText($reviewPath, (ConvertTo-Json -InputObject $report -Depth 12), $utf8)
[IO.File]::WriteAllText($manualReviewPath, (ConvertTo-Json -InputObject $report -Depth 12), $utf8)
Write-Output "수동 결과: $reviewPath"
Write-Output "판정: $($report.status)"
Write-Output '자동 입력·자동 캡처·self-test는 사람 확인으로 계산하지 않았습니다.'
if ($report.status -eq 'MANUAL_REVIEW_RECORDED') { exit 0 }
if ($report.status -eq 'MANUAL_REVIEW_FAILED') { exit 1 }
exit 2
