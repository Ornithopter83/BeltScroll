[CmdletBinding()]
param(
    [string]$ProjectRoot = '',
    [string]$GodotReport = '.qa_logs/m6d_godot_automated.json',
    [string]$WindowReport = '.qa_logs/m6d_window_playthrough.json',
    [string]$ManualReviewReport = '.qa_logs/m6d_manual_acceptance.json',
    [int]$MaxEvidenceAgeDays = 7,
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

function Invoke-GitRead {
    param([string[]]$Arguments)
    $lines = @(& git -C $ProjectRoot @Arguments 2>&1)
    if ($LASTEXITCODE -ne 0) { throw ($lines -join ' ') }
    return ([string]::Join('', [string[]]$lines)).Trim()
}

function Test-FreshTimestamp {
    param([object]$Value)
    if ([string]::IsNullOrWhiteSpace([string]$Value)) { return $false }
    try {
        $date = [DateTimeOffset]::Parse([string]$Value).ToUniversalTime()
        $age = [DateTimeOffset]::UtcNow - $date
        return ($age.TotalDays -ge -0.05 -and $age.TotalDays -le $MaxEvidenceAgeDays)
    } catch { return $false }
}

function Test-EvidenceFiles {
    param([object]$Evidence, [object]$Manifest)
    $paths = @($Evidence | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
    if ($paths.Count -eq 0 -or $null -eq $Manifest) { return $false }
    foreach ($pathValue in $paths) {
        $path = [string]$pathValue
        $full = Resolve-EvidencePath $path
        if (-not $full -or -not (Test-Path -LiteralPath $full -PathType Leaf)) { return $false }
        $entry = @($Manifest | Where-Object { [string]$_.path -eq $path })
        if ($entry.Count -ne 1 -or [string]$entry[0].sha256 -notmatch '^[0-9a-fA-F]{64}$') { return $false }
        $actual = (Get-FileHash -LiteralPath $full -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($actual -ne ([string]$entry[0].sha256).ToLowerInvariant()) { return $false }
        $item = Get-Item -LiteralPath $full
        if ((([DateTimeOffset]$item.LastWriteTimeUtc).ToUniversalTime() - [DateTimeOffset]::UtcNow).TotalDays -lt -$MaxEvidenceAgeDays) { return $false }
        if ($item.Length -le 0) { return $false }
    }
    return $true
}

function Test-ReportBinding {
    param([object]$Data, [string]$HeadSha)
    if ($null -eq $Data) { return $false }
    return ([string]$Data.targetCommitSha -eq $HeadSha -and
        (Test-FreshTimestamp $Data.generatedAtUtc) -and
        (Test-EvidenceFiles $Data.evidence $Data.evidenceHashes))
}

function Test-WindowImageEvidence {
    param([object]$Evidence)
    $images = @($Evidence | Where-Object { [string]$_ -match '(?i)\.png$' })
    if ($images.Count -eq 0) { return $false }
    try {
        Add-Type -AssemblyName System.Drawing
        foreach ($path in $images) {
            $full = Resolve-EvidencePath ([string]$path)
            if (-not $full -or -not (Test-Path -LiteralPath $full -PathType Leaf)) { return $false }
            $image = [System.Drawing.Image]::FromFile($full)
            try { if ($image.Width -lt 1280 -or $image.Height -lt 720) { return $false } }
            finally { $image.Dispose() }
        }
        return $true
    } catch { return $false }
}

function Test-HumanEvidence {
    param([object]$Evidence, [object]$Manifest)
    return ((Test-EvidenceFiles $Evidence $Manifest) -and (Test-WindowImageEvidence $Evidence))
}

function Get-ManualItemStatus {
    param([object]$Item, [string[]]$RequiredNames, [string]$Method, [object]$Report, [string]$HeadSha)
    if ($null -eq $Item) { return 'NOT_VERIFIED' }
    if ([string]$Item.status -ne 'PASS' -or [string]::IsNullOrWhiteSpace([string]$Item.reviewer) -or
        -not (Test-FreshTimestamp $Item.observedAt) -or [string]$Item.method -ne $Method -or
        [string]$Report.targetCommitSha -ne $HeadSha -or -not (Test-ReportBinding $Report $HeadSha)) { return 'UNVERIFIED' }
    $entries = @($Item.checks)
    foreach ($name in $RequiredNames) {
        $matched = @($entries | Where-Object { [string]$_.name -eq $name -and [string]$_.status -eq 'PASS' })
        if ($matched.Count -ne 1 -or -not (Test-HumanEvidence $matched[0].evidence $Report.evidenceHashes)) { return 'UNVERIFIED' }
    }
    return 'PASS_HUMAN_REVIEW'
}

$gitState = [pscustomobject]@{ HeadSha = $null; Error = $null }
try {
    $gitState.HeadSha = Invoke-GitRead @('rev-parse', '--verify', 'HEAD^{commit}')
    if ($gitState.HeadSha -notmatch '^[0-9a-fA-F]{40,64}$') { throw 'Local HEAD returned an invalid commit SHA.' }
    $gitState.HeadSha = $gitState.HeadSha.ToLowerInvariant()
} catch { $gitState.Error = $_.Exception.Message }

$remote = [pscustomobject]@{ Status = 'UNVERIFIED'; Branch = 'origin/main'; Sha = $null; InspectedCommitSha = $gitState.HeadSha; MatchesInspectedCommit = $false; Detail = '원격 main SHA를 아직 확인하지 않았다.' }
if (-not $SkipRemoteQuery) {
    try {
        $remoteLines = @(& git -C $ProjectRoot ls-remote --heads origin main 2>&1)
        if ($LASTEXITCODE -ne 0) { throw ($remoteLines -join ' ') }
        $line = @($remoteLines | Where-Object { [string]$_ -match '^[0-9a-fA-F]{40,64}\s+refs/heads/main$' }) | Select-Object -First 1
        if (-not $line) { throw 'origin/main SHA 응답이 비었거나 형식이 맞지 않는다.' }
        $remote.Sha = ([string]$line -split '\s+')[0].ToLowerInvariant()
        if (-not $gitState.HeadSha) { $remote.Detail = '원격 SHA는 조회했지만 검사 대상 HEAD를 확인할 수 없다.' }
        elseif ($remote.Sha -ne $gitState.HeadSha) { $remote.Status = 'MISMATCH'; $remote.Detail = '원격 main SHA와 실제 검사 대상 HEAD가 다르다.' }
        else { $remote.Status = 'PASS_VERIFIED_MATCH'; $remote.MatchesInspectedCommit = $true; $remote.Detail = 'git ls-remote SHA와 실제 검사 대상 HEAD가 일치한다.' }
    } catch { $remote.Detail = "원격 SHA 조회 실패: $($_.Exception.Message)" }
} else { $remote.Detail = 'SkipRemoteQuery 지정으로 원격 SHA를 조회하지 않았으며 최종 준비 조건을 충족하지 않는다.' }

$godotData = Read-JsonEvidence $GodotReport
$godotStatus = 'NOT_VERIFIED'
$godotDetail = 'M6D Godot 자동 검증 보고서가 없다.'
$godotPassed = 0
if ($godotData) {
    $godotPassed = @($godotData.checks | Where-Object { [string]$_.status -eq 'PASS' -and -not [string]::IsNullOrWhiteSpace([string]$_.name) }).Count
    if ([string]$godotData.result -eq 'PASS' -and [int]$godotData.exitCode -eq 0 -and $godotPassed -gt 0 -and (Test-ReportBinding $godotData $gitState.HeadSha)) {
        $godotStatus = 'PASS_AUTOMATED'; $godotDetail = '보고서가 현재 검사 HEAD에 결속되고 최근 생성됐으며 SHA-256 증거 manifest가 일치한다.'
    } else { $godotStatus = 'BLOCKED'; $godotDetail = '성공 결과·검사·현재 HEAD 결속·신선한 생성 시각·증거 SHA-256 manifest 중 하나 이상이 유효하지 않다.' }
} elseif (Test-Path -LiteralPath (Resolve-EvidencePath $GodotReport) -PathType Leaf) { $godotStatus = 'UNVERIFIED'; $godotDetail = 'Godot 보고서가 없거나 UTF-8 JSON으로 읽히지 않는다.' }
$godot = [pscustomobject]@{ Status=$godotStatus; Report=$GodotReport; TargetCommitSha=$godotData.targetCommitSha; ExitCode=$godotData.exitCode; PassedChecks=$godotPassed; Detail=$godotDetail }

$windowData = Read-JsonEvidence $WindowReport
$windowStatus = 'NOT_VERIFIED'
$windowDetail = '실제 Window 플레이 증거 보고서가 없다.'
if ($windowData) {
    $valid = [string]$windowData.result -eq 'PASS' -and $windowData.headless -eq $false -and
        -not [string]::IsNullOrWhiteSpace([string]$windowData.windowTitle) -and
        [string]$windowData.inputMode -eq 'gameplay-events' -and $windowData.directStateMutation -eq $false -and
        $windowData.internalOutcomeCalls -eq $false -and (Test-WindowImageEvidence $windowData.evidence) -and
        (Test-ReportBinding $windowData $gitState.HeadSha)
    if ($valid) { $windowStatus = 'PASS_AUTOMATED_WINDOW'; $windowDetail = '실제 Window 보고서가 현재 HEAD·신선도·해시 manifest에 결속됐다. 자동 입력은 수동 증거가 아니다.' }
    else { $windowStatus = 'BLOCKED'; $windowDetail = '합성/미지원 입력 모드, 상태 직접 변경, 내부 결과 호출, 오래된 증거, SHA 불일치 또는 Window 정보 누락이다.' }
} elseif (Test-Path -LiteralPath (Resolve-EvidencePath $WindowReport) -PathType Leaf) { $windowStatus = 'UNVERIFIED'; $windowDetail = 'Window 보고서가 없거나 UTF-8 JSON으로 읽히지 않는다.' }
$window = [pscustomobject]@{ Status=$windowStatus; Report=$WindowReport; TargetCommitSha=$windowData.targetCommitSha; IsHeadless=$windowData.headless; CaptureEvidence=@($windowData.evidence); Detail=$windowDetail }

$manual = Read-JsonEvidence $ManualReviewReport
$physical = Get-ManualItemStatus $manual.physicalKeyboard @('Num1','Num2','Num3','Num4','Num5','Num6','Num7','Num8','Num9') 'physical-keyboard' $manual $gitState.HeadSha
$displayStatus = Get-ManualItemStatus $manual.display @('fullscreen','three-times-scale') 'human-observed' $manual $gitState.HeadSha
$editorStatus = Get-ManualItemStatus $manual.editorGuiRoundtrip @('create','edit','save-close','reopen-verify','apply-to-game') 'human-gui' $manual $gitState.HeadSha
$physicalResult = [pscustomobject]@{ Status=$physical; Keys=@('Num1','Num2','Num3','Num4','Num5','Num6','Num7','Num8','Num9'); EvidenceReport=$ManualReviewReport; Detail='각 물리 키를 최근에 직접 관찰하고 현재 검사 HEAD에 결속된 SHA-256 증거가 필요하다.' }
$displayResult = [pscustomobject]@{ Status=$displayStatus; Requirements=@('fullscreen','three-times-scale'); EvidenceReport=$ManualReviewReport; Detail='전체화면과 3배 표시의 신선한 사람 관찰 증거가 필요하다.' }
$editorResult = [pscustomobject]@{ Status=$editorStatus; Steps=@('create','edit','save-close','reopen-verify','apply-to-game'); EvidenceReport=$ManualReviewReport; Detail='GUI 왕복 5단계 각각의 신선한 사람 관찰 증거가 필요하다.' }

$approvedArtCount = 0
$approvedSequences = @()
$artReview = $manual.artReview
if ($artReview -and [string]$artReview.method -eq 'human-visual-review' -and -not [string]::IsNullOrWhiteSpace([string]$artReview.reviewer) -and
    (Test-FreshTimestamp $artReview.reviewedAt) -and [string]$manual.targetCommitSha -eq $gitState.HeadSha -and (Test-ReportBinding $manual $gitState.HeadSha)) {
    foreach ($sequence in @($artReview.sequences)) {
        $frames = @($sequence.frames | Sort-Object { [int]$_.index })
        $indices = @($frames | ForEach-Object { [int]$_.index })
        $contiguous = $indices.Count -ge 2
        for ($i = 1; $i -lt $indices.Count; $i++) { if ($indices[$i] -ne ($indices[$i - 1] + 1)) { $contiguous = $false } }
        $frameOk = $frames.Count -ge 2 -and @($frames | Where-Object { $_.humanApproved -ne $true -or -not (Test-HumanEvidence $_.evidence $manual.evidenceHashes) }).Count -eq 0
        if ($contiguous -and $frameOk -and [string]$sequence.decision -eq 'approved' -and $sequence.newApproval -eq $true -and (Test-FreshTimestamp $sequence.approvedAt)) {
            $approvedArtCount += $frames.Count; $approvedSequences += [string]$sequence.id
        }
    }
}
$artStatus = if ($approvedArtCount -gt 0) { 'PASS_HUMAN_APPROVED_NEW_ART' } elseif ($null -eq $artReview) { 'NOT_VERIFIED' } else { 'BLOCKED_ZERO_NEW_HUMAN_APPROVED_ART' }
$artResult = [pscustomobject]@{ Status=$artStatus; NewHumanApprovedArtCount=$approvedArtCount; ApprovedSequences=$approvedSequences; EvidenceReport=$ManualReviewReport; Detail='현재 HEAD에 결속된 신규 승인 표시, 최근 사람 승인, 연속 프레임과 실제 파일 해시가 모두 필요하다.' }

$bossStatus = 'NOT_VERIFIED'
$bossDetail = '실제 Window 플레이스루의 보스전·승리·패배/종료 증거를 확인하지 않았다.'
if ($windowData) {
    $requiredOutcomes = @('boss-encounter','boss-defeated','player-defeat','restart')
    $validOutcomes = (Test-ReportBinding $windowData $gitState.HeadSha)
    foreach ($name in $requiredOutcomes) {
        $matches = @($windowData.outcomes | Where-Object { [string]$_.name -eq $name -and [string]$_.status -eq 'PASS' })
        if ($matches.Count -ne 1 -or -not (Test-EvidenceFiles $matches[0].evidence $windowData.evidenceHashes)) { $validOutcomes = $false }
    }
    if ($window.Status -eq 'PASS_AUTOMATED_WINDOW' -and $validOutcomes) { $bossStatus = 'PASS_AUTOMATED_PLAYTHROUGH'; $bossDetail = '현재 HEAD에 결속된 gameplay-events 보고서의 네 종료 항목을 확인했다.' }
    else { $bossStatus = 'BLOCKED'; $bossDetail = '필수 플레이 결과, SHA-256 증거, 보고서 신선도 또는 HEAD 결속이 유효하지 않다.' }
}
$boss = [pscustomobject]@{ Status=$bossStatus; Report=$WindowReport; Detail=$bossDetail }

$requiredDocuments = @('docs/review/m6d_integrated_acceptance_gate.md','docs/review/m6d_full_playthrough_gate.md','docs/review/manual_input_acceptance_gate.md','docs/review/editor_acceptance_gate.md','docs/review/m6d_motion_candidate_gate.md')
$missingDocuments = @($requiredDocuments | Where-Object { -not (Test-Path -LiteralPath (Join-Path $ProjectRoot ($_ -replace '/', '\')) -PathType Leaf) })
$documents = [pscustomobject]@{ Status=if ($missingDocuments.Count -eq 0) {'PASS_DOCUMENTS_PRESENT'} else {'BLOCKED_MISSING_DOCUMENTS'}; Required=$requiredDocuments; Missing=$missingDocuments }

$hygiene = [pscustomobject]@{ Status='UNVERIFIED'; Findings=@(); Baseline='origin/main'; Detail='저장소 위생 검사를 실행하지 않았다.' }
$hygieneScript = Join-Path $ProjectRoot 'tools/check_repository_hygiene.ps1'
if (Test-Path -LiteralPath $hygieneScript -PathType Leaf) {
    try {
        $hygieneOutput = @(& (Join-Path $PSHOME 'powershell.exe') -NoProfile -ExecutionPolicy Bypass -File $hygieneScript -RepositoryRoot $ProjectRoot 2>&1)
        $hygieneExit = $LASTEXITCODE
        $hygiene.Findings = @($hygieneOutput | ForEach-Object { [string]$_ })
        if ($hygieneExit -eq 0 -and @($hygieneOutput | Where-Object { [string]$_ -ceq 'Repository hygiene passed.' }).Count -eq 1) { $hygiene.Status='PASS'; $hygiene.Detail='Git 위생 검사기가 origin/main 기준 PASS를 반환했다.' }
        elseif ($hygieneExit -eq 1) { $hygiene.Status='FAIL'; $hygiene.Detail='Git 위생 검사에서 위반을 발견했다.' }
        else { $hygiene.Status='UNVERIFIED'; $hygiene.Detail='기준 ref 또는 Git 상태를 확인할 수 없어 위생 결과가 미검증이다.' }
    } catch { $hygiene.Status='UNVERIFIED'; $hygiene.Detail="Git 위생 검사 실행 실패: $($_.Exception.Message)" }
} else { $hygiene.Detail='tools/check_repository_hygiene.ps1가 없다.' }

$sections = @(
    [pscustomobject]@{ Name='원격 main SHA와 검사 HEAD'; Status=$remote.Status },
    [pscustomobject]@{ Name='Godot 자동 검증'; Status=$godot.Status },
    [pscustomobject]@{ Name='실제 Window 플레이'; Status=$window.Status },
    [pscustomobject]@{ Name='물리 키보드 Num1~9'; Status=$physicalResult.Status },
    [pscustomobject]@{ Name='전체화면·3배 표시'; Status=$displayResult.Status },
    [pscustomobject]@{ Name='편집기 GUI 왕복'; Status=$editorResult.Status },
    [pscustomobject]@{ Name='원화 승인·연속 프레임'; Status=$artResult.Status },
    [pscustomobject]@{ Name='보스전과 종료'; Status=$boss.Status },
    [pscustomobject]@{ Name='필수 검수 서류'; Status=$documents.Status },
    [pscustomobject]@{ Name='Git 위생'; Status=$hygiene.Status }
)
$blockers = @($sections | Where-Object { $_.Status -notlike 'PASS*' } | ForEach-Object { "$($_.Name): $($_.Status)" })
$ready = $blockers.Count -eq 0 -and $approvedArtCount -gt 0
$finalApprovalStatus = if ($ready) { 'PENDING_HUMAN_APPROVAL' } else { 'BLOCKED' }
if ($ready) { $blockers = @('최종 제품 인수는 사람의 명시적 승인 대기 중이다.') }

$report = [pscustomobject]@{
    Audit='M6D integrated acceptance audit (2026-10-10)'
    GeneratedAtUtc=[DateTime]::UtcNow.ToString('o')
    ProjectRoot=$ProjectRoot
    InspectedCommitSha=$gitState.HeadSha
    Verdict=$finalApprovalStatus
    FinalHumanApproval=$finalApprovalStatus
    FinalPassAllowed=$false
    Requirements=$sections
    RemoteMain=$remote
    GodotAutomatedValidation=$godot
    ActualWindow=$window
    PhysicalKeyboardNum1To9=$physicalResult
    FullscreenAndThreeTimesScale=$displayResult
    EditorGuiRoundtrip=$editorResult
    ArtApprovalAndContinuousFrames=$artResult
    BossBattleAndEnding=$boss
    RequiredDocuments=$documents
    GitHygiene=$hygiene
    EvidencePolicy=[pscustomobject]@{ MaxEvidenceAgeDays=$MaxEvidenceAgeDays; ReportsRequireTargetCommitSha=$true; ReportsRequireGeneratedAtUtc=$true; EvidenceRequiresSha256Manifest=$true; SyntheticInputAccepted=$false; ZeroNewHumanApprovedArtBlocks=$true; FinalPassCanBeIssued=$false }
    Blockers=$blockers
}
$report | ConvertTo-Json -Depth 14
exit 2
