[CmdletBinding()]
param(
    [string]$ProjectRoot = '',
    [string]$GodotReport = '.qa_logs/m6d_godot_automated.json',
    [string]$WindowReport = '.qa_logs/m6d_window_playthrough.json',
    [string]$ManualReviewReport = '.qa_logs/m6d_manual_acceptance.json',
    [switch]$SkipRemoteQuery
)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($ProjectRoot)) { $ProjectRoot = Split-Path -Parent $PSScriptRoot }
$ProjectRoot = [IO.Path]::GetFullPath($ProjectRoot)
$utf8 = New-Object System.Text.UTF8Encoding($false)
[Console]::OutputEncoding = $utf8
$OutputEncoding = $utf8

function Resolve-EvidencePath {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return $null }
    if ([IO.Path]::IsPathRooted($Path)) { return [IO.Path]::GetFullPath($Path) }
    return [IO.Path]::GetFullPath((Join-Path $ProjectRoot ($Path -replace '/', '\')))
}

function Read-JsonEvidence {
    param([string]$Path)
    $full = Resolve-EvidencePath $Path
    if (-not $full -or -not (Test-Path -LiteralPath $full -PathType Leaf)) { return $null }
    try { return (Get-Content -Encoding UTF8 -Raw -LiteralPath $full | ConvertFrom-Json) }
    catch { return $null }
}

function Test-EvidenceFiles {
    param([object]$Evidence)
    $paths = @($Evidence | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
    if ($paths.Count -eq 0) { return $false }
    foreach ($path in $paths) {
        $full = Resolve-EvidencePath ([string]$path)
        if (-not $full -or -not (Test-Path -LiteralPath $full -PathType Leaf)) { return $false }
    }
    return $true
}

function Get-ManualItemStatus {
    param([object]$Item, [string[]]$RequiredNames, [string]$Method)
    if ($null -eq $Item) { return 'NOT_VERIFIED' }
    if ([string]$Item.status -ne 'PASS' -or [string]::IsNullOrWhiteSpace([string]$Item.reviewer) -or
        [string]::IsNullOrWhiteSpace([string]$Item.observedAt) -or [string]$Item.method -ne $Method) { return 'UNVERIFIED' }
    $entries = @($Item.checks)
    foreach ($name in $RequiredNames) {
        $matched = @($entries | Where-Object { [string]$_.name -eq $name -and [string]$_.status -eq 'PASS' })
        if ($matched.Count -ne 1 -or -not (Test-EvidenceFiles $matched[0].evidence)) { return 'UNVERIFIED' }
    }
    return 'PASS'
}

$remote = [pscustomobject]@{ Status = 'UNVERIFIED'; Branch = 'origin/main'; Sha = $null; Detail = '원격 main SHA를 아직 확인하지 않았다.' }
if (-not $SkipRemoteQuery) {
    $git = Get-Command git -ErrorAction SilentlyContinue
    if ($git) {
        try {
            $remoteLines = @(& git -C $ProjectRoot ls-remote --heads origin main 2>&1)
            if ($LASTEXITCODE -ne 0) { throw ($remoteLines -join ' ') }
            $line = @($remoteLines | Where-Object { [string]$_ -match '^[0-9a-fA-F]{40,64}\s+refs/heads/main$' }) | Select-Object -First 1
            if ($line) {
                $remote.Sha = ([string]$line -split '\s+')[0].ToLowerInvariant()
                $remote.Status = 'VERIFIED'
                $remote.Detail = 'git ls-remote로 origin/main SHA를 읽기 전용 조회했다.'
            } else { $remote.Detail = 'origin/main SHA 응답이 비었거나 형식이 맞지 않는다.' }
        } catch { $remote.Detail = "원격 SHA 조회 실패: $($_.Exception.Message)" }
    } else { $remote.Detail = 'git을 찾지 못해 원격 SHA를 조회하지 않았다.' }
} else { $remote.Detail = 'SkipRemoteQuery 지정으로 원격 SHA를 조회하지 않았다.' }

$godotData = Read-JsonEvidence $GodotReport
$godot = [pscustomobject]@{ Status = 'NOT_VERIFIED'; Report = $GodotReport; ExitCode = $null; PassedChecks = 0; Detail = 'M6D Godot 자동 검증 보고서가 없다.' }
if ($godotData) {
    $godot.ExitCode = $godotData.exitCode
    $godot.PassedChecks = @($godotData.checks | Where-Object { [string]$_.status -eq 'PASS' }).Count
    $godot.Status = if ($godotData.result -eq 'PASS' -and $godotData.exitCode -eq 0 -and $godot.PassedChecks -gt 0 -and (Test-EvidenceFiles $godotData.evidence)) { 'PASS' } else { 'FAIL_OR_INCOMPLETE' }
    $godot.Detail = if ($godot.Status -eq 'PASS') { '보고서와 연결된 자동 검증 로그를 확인했다. 사람 수동 검토 상태에는 영향을 주지 않는다.' } else { '자동 검증 결과, 종료 코드, 성공 검사 또는 로그 증거가 불충분하다.' }
} elseif (Test-Path -LiteralPath (Resolve-EvidencePath $GodotReport) -PathType Leaf) {
    $godot.Status = 'UNVERIFIED'; $godot.Detail = 'Godot 보고서가 없거나 UTF-8 JSON으로 읽히지 않는다.'
}

$windowData = Read-JsonEvidence $WindowReport
$window = [pscustomobject]@{ Status = 'NOT_VERIFIED'; Report = $WindowReport; IsHeadless = $null; CaptureEvidence = @(); Detail = '실제 Window 플레이 증거 보고서가 없다.' }
if ($windowData) {
    $window.IsHeadless = [bool]$windowData.headless
    $window.CaptureEvidence = @($windowData.evidence)
    $valid = $windowData.result -eq 'PASS' -and $windowData.headless -eq $false -and
        -not [string]::IsNullOrWhiteSpace([string]$windowData.windowTitle) -and (Test-EvidenceFiles $windowData.evidence)
    $window.Status = if ($valid) { 'PASS_AUTOMATED_WINDOW' } else { 'FAIL_OR_INCOMPLETE' }
    $window.Detail = if ($valid) { '실제 Window 보고서와 연결된 파일을 확인했다. 캡처는 사람 시각 인수로 계산하지 않는다.' } else { 'Window 모드, 성공 결과, 창 식별 또는 증거 파일이 불충분하다.' }
} elseif (Test-Path -LiteralPath (Resolve-EvidencePath $WindowReport) -PathType Leaf) {
    $window.Status = 'UNVERIFIED'; $window.Detail = 'Window 보고서가 없거나 UTF-8 JSON으로 읽히지 않는다.'
}

$manual = Read-JsonEvidence $ManualReviewReport
$physical = Get-ManualItemStatus -Item $manual.physicalKeyboard -RequiredNames @('Num1','Num2','Num3','Num4','Num5','Num6','Num7','Num8','Num9') -Method 'physical-keyboard'
$physicalResult = [pscustomobject]@{ Status = $physical; Keys = @('Num1','Num2','Num3','Num4','Num5','Num6','Num7','Num8','Num9'); EvidenceReport = $ManualReviewReport; Detail = '각 숫자 키의 검사자 직접 관찰 기록과 개별 증거가 필요하다. 자동 입력은 인정하지 않는다.' }

$displayStatus = Get-ManualItemStatus -Item $manual.display -RequiredNames @('fullscreen','three-times-scale') -Method 'human-observed'
$displayResult = [pscustomobject]@{ Status = $displayStatus; Requirements = @('fullscreen','three-times-scale'); EvidenceReport = $ManualReviewReport; Detail = '전체화면과 3배 표시는 직접 관찰한 개별 기록으로만 통과한다.' }

$editorStatus = Get-ManualItemStatus -Item $manual.editorGuiRoundtrip -RequiredNames @('create','edit','save-close','reopen-verify','apply-to-game') -Method 'human-gui'
$editorResult = [pscustomobject]@{ Status = $editorStatus; Steps = @('create','edit','save-close','reopen-verify','apply-to-game'); EvidenceReport = $ManualReviewReport; Detail = '편집기 GUI 왕복 5단계 각각에 사람 관찰과 증거 파일이 필요하다.' }

$artReview = $manual.artReview
$approvedArtCount = 0
$approvedSequences = @()
if ($null -ne $artReview) {
    foreach ($sequence in @($artReview.sequences)) {
        $frames = @($sequence.frames | Sort-Object { [int]$_.index })
        $indices = @($frames | ForEach-Object { [int]$_.index })
        $contiguous = $indices.Count -ge 2
        for ($i = 1; $i -lt $indices.Count; $i++) { if ($indices[$i] -ne ($indices[$i - 1] + 1)) { $contiguous = $false } }
        $human = $artReview.method -eq 'human-visual-review' -and -not [string]::IsNullOrWhiteSpace([string]$artReview.reviewer) -and
            -not [string]::IsNullOrWhiteSpace([string]$artReview.reviewedAt) -and $sequence.decision -eq 'approved' -and
            @($frames | Where-Object { $_.humanApproved -eq $true -and (Test-EvidenceFiles $_.evidence) }).Count -eq $frames.Count
        if ($contiguous -and $human -and $frames.Count -ge 2) {
            $approvedArtCount += $frames.Count
            $approvedSequences += [string]$sequence.id
        }
    }
}
$artStatus = if ($approvedArtCount -gt 0) { 'PASS_HUMAN_APPROVED_CONTIGUOUS_FRAMES' } elseif ($null -eq $artReview) { 'NOT_VERIFIED' } else { 'BLOCKED_ZERO_NEW_HUMAN_APPROVED_ART' }
$artResult = [pscustomobject]@{ Status = $artStatus; NewHumanApprovedArtCount = $approvedArtCount; ApprovedSequences = $approvedSequences; EvidenceReport = $ManualReviewReport; Detail = '새 원화의 사람 시각 승인과 2장 이상 연속 프레임 인덱스를 모두 요구한다. 캡처·자동 판정만으로 승인 수를 늘리지 않는다.' }

$boss = [pscustomobject]@{ Status = 'NOT_VERIFIED'; Report = $WindowReport; Detail = '실제 Window 플레이스루의 보스전·승리·패배/종료 증거를 확인하지 않았다.' }
if ($windowData) {
    $natural = $windowData.inputMode -eq 'gameplay-events' -and $windowData.directStateMutation -eq $false -and $windowData.internalOutcomeCalls -eq $false
    $outcomes = @($windowData.outcomes)
    $bossChecks = @('boss-encounter','boss-defeated','player-defeat','restart')
    $bossPassed = @($outcomes | Where-Object { $_.status -eq 'PASS' } | ForEach-Object { [string]$_.name })
    $allOutcomes = @($bossChecks | Where-Object { $_ -notin $bossPassed }).Count -eq 0
    foreach ($outcomeName in $bossChecks) {
        $outcome = @($outcomes | Where-Object { [string]$_.name -eq $outcomeName -and [string]$_.status -eq 'PASS' }) | Select-Object -First 1
        if (-not $outcome -or -not (Test-EvidenceFiles $outcome.evidence)) { $allOutcomes = $false }
    }
    if ($window.Status -eq 'PASS_AUTOMATED_WINDOW' -and $natural -and $allOutcomes) { $boss.Status = 'PASS_AUTOMATED_PLAYTHROUGH' }
    elseif ($windowData.outcomes) { $boss.Status = 'FAIL_OR_INCOMPLETE' }
    $boss.Detail = if ($boss.Status -eq 'PASS_AUTOMATED_PLAYTHROUGH') { '입력 이벤트 기반 플레이스루에서 보스 조우·승리·플레이어 패배·재시작을 확인했다. 물리 키보드 수동 검수는 별도다.' } else { '보스와 종료 상태, 자연스러운 입력 이벤트 경로, 내부 결과 호출/직접 상태 변경 방지 증거가 불충분하다.' }
}

$hygiene = [pscustomobject]@{ Status = 'UNVERIFIED'; Findings = @(); Baseline = 'origin/main'; Detail = '저장소 위생 검사를 실행하지 않았다.' }
$hygieneScript = Join-Path $ProjectRoot 'tools/check_repository_hygiene.ps1'
if (Test-Path -LiteralPath $hygieneScript -PathType Leaf) {
    $hygieneOutput = @(& (Join-Path $PSHOME 'powershell.exe') -NoProfile -ExecutionPolicy Bypass -File $hygieneScript -RepositoryRoot $ProjectRoot 2>&1)
    $hygieneExit = $LASTEXITCODE
    $hygiene.Findings = @($hygieneOutput | ForEach-Object { [string]$_ })
    if ($hygieneExit -eq 0 -and @($hygieneOutput | Where-Object { [string]$_ -match '^Repository hygiene passed\.$' }).Count -eq 1) {
        $hygiene.Status = 'PASS'; $hygiene.Detail = '기존 Git 위생 스크립트가 origin/main 기준 PASS를 반환했다.'
    } elseif ($hygieneExit -eq 1) {
        $hygiene.Status = 'FAIL'; $hygiene.Detail = 'Git 위생 검사에서 추적 산출물 또는 위생 위반을 발견했다.'
    } else { $hygiene.Status = 'UNVERIFIED'; $hygiene.Detail = '기준 ref 또는 Git 상태를 확인할 수 없어 위생 결과가 미검증이다.' }
} else { $hygiene.Detail = 'tools/check_repository_hygiene.ps1가 없다.' }

$sections = @(
    [pscustomobject]@{ Name='원격 main SHA'; Status=$remote.Status },
    [pscustomobject]@{ Name='Godot 자동 검증'; Status=$godot.Status },
    [pscustomobject]@{ Name='실제 Window 플레이'; Status=$window.Status },
    [pscustomobject]@{ Name='물리 키보드 Num1~9'; Status=$physicalResult.Status },
    [pscustomobject]@{ Name='전체화면·3배 표시'; Status=$displayResult.Status },
    [pscustomobject]@{ Name='편집기 GUI 왕복'; Status=$editorResult.Status },
    [pscustomobject]@{ Name='원화 승인·연속 프레임'; Status=$artResult.Status },
    [pscustomobject]@{ Name='보스전과 종료'; Status=$boss.Status },
    [pscustomobject]@{ Name='Git 위생'; Status=$hygiene.Status }
)
$blockers = @($sections | Where-Object { $_.Status -notlike 'PASS*' } | ForEach-Object { "$($_.Name): $($_.Status)" })
if ($approvedArtCount -eq 0 -and -not ($blockers -match '원화 승인')) { $blockers += '신규 원화 사람 승인 수가 0이므로 최종 인수는 BLOCKED다.' }

$report = [pscustomobject]@{
    Audit = 'M6D integrated acceptance audit (2026-10-10)'
    GeneratedAtUtc = [DateTime]::UtcNow.ToString('o')
    ProjectRoot = $ProjectRoot
    Verdict = 'BLOCKED'
    FinalPassAllowed = $false
    Requirements = $sections
    RemoteMain = $remote
    GodotAutomatedValidation = $godot
    ActualWindow = $window
    PhysicalKeyboardNum1To9 = $physicalResult
    FullscreenAndThreeTimesScale = $displayResult
    EditorGuiRoundtrip = $editorResult
    ArtApprovalAndContinuousFrames = $artResult
    BossBattleAndEnding = $boss
    GitHygiene = $hygiene
    EvidenceRules = [pscustomobject]@{
        AutomatedInputIsPhysicalInput = $false
        CaptureIsHumanApproval = $false
        ZeroNewHumanApprovedArtBlocks = $true
        FinalPassCanBeIssued = $false
    }
    Blockers = $blockers
}
$report | ConvertTo-Json -Depth 12
exit 2
