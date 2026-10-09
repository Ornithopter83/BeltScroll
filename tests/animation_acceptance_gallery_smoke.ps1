[CmdletBinding()]
param([string]$ProjectRoot = '')

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)
if ([string]::IsNullOrWhiteSpace($ProjectRoot)) {
    $scriptPath = if (-not [string]::IsNullOrWhiteSpace($PSCommandPath)) { $PSCommandPath } else { $MyInvocation.MyCommand.Path }
    $ProjectRoot = Split-Path -Parent (Split-Path -Parent $scriptPath)
}
$ProjectRoot = [System.IO.Path]::GetFullPath($ProjectRoot)
$builder = Join-Path $ProjectRoot 'tools/build_animation_acceptance_gallery.ps1'
$htmlPath = Join-Path $ProjectRoot 'docs/review/animation_acceptance_gallery.html'
$templatePath = Join-Path $ProjectRoot 'docs/review/records/REVIEW_TEMPLATE.md'
if (-not (Test-Path -LiteralPath $builder -PathType Leaf)) { throw "Builder missing: $builder" }
& $builder -ProjectRoot $ProjectRoot
if (-not (Test-Path -LiteralPath $htmlPath -PathType Leaf)) { throw "Gallery missing: $htmlPath" }
$html = [System.IO.File]::ReadAllText($htmlPath, [System.Text.Encoding]::UTF8)
$visibleHtml = [System.Net.WebUtility]::HtmlDecode($html)
$template = [System.IO.File]::ReadAllText($templatePath, [System.Text.Encoding]::UTF8)

# Keep every original card and append secured, explicitly unaccepted candidates.
$turnOriginal = 'assets/art/player/elven_fighter_turn_rear_mid_v1_candidate_1254x1254.png'
$turnSafe = 'assets/art/player/elven_fighter_turn_rear_mid_v1_safe_candidate_1254x1254.png'
$turnV2OriginalCandidates = @('assets/art/player/elven_fighter_turn_rear_mid_v2_candidate_1254x1254.png','assets/art/player/elven_fighter_turn_pivot_v2_candidate_1254x1254.png')
$turnV2Original = @($turnV2OriginalCandidates | Where-Object { Test-Path -LiteralPath (Join-Path $ProjectRoot $_) -PathType Leaf } | Select-Object -First 1)[0]
$turnV2SafeCandidates = @('assets/art/player/elven_fighter_turn_rear_mid_v2_safe_candidate_1254x1254.png','assets/art/player/elven_fighter_turn_pivot_v2_safe_candidate_1254x1254.png')
$turnV2Safe = @($turnV2SafeCandidates | Where-Object { Test-Path -LiteralPath (Join-Path $ProjectRoot $_) -PathType Leaf } | Select-Object -First 1)[0]
$turnOriginalExists = Test-Path -LiteralPath (Join-Path $ProjectRoot $turnOriginal) -PathType Leaf
$turnV2Exists = [bool]$turnV2Original -and (Test-Path -LiteralPath (Join-Path $ProjectRoot $turnV2Original) -PathType Leaf)
$requiredIds = @('idle','attack1-contact','attack2-contact','attack3-contact','run-v1','run-v2','run-v4','run-v5','turn','jump-rise','jump-fall','hit','skill1','skill2-v1','skill2-v2','attack1-startup','attack3-startup','run-v3')
if ($turnOriginalExists) { $requiredIds += 'turn-rear-mid' }
if ($turnV2Exists) { $requiredIds += 'turn-rear-mid-v2' }
foreach ($id in $requiredIds) {
    if ($html -notmatch ('id="' + [regex]::Escape($id) + '"')) { throw "Required gallery card missing: $id" }
}
$cardCount = [regex]::Matches($html, '<article class="card"').Count
$expectedCardCount = 17 + 1 + [int]$turnOriginalExists + [int]$turnV2Exists
if ($cardCount -ne $expectedCardCount) { throw "Expected 17 preserved cards, run-v3, and conditional turn v1/v2 cards ($expectedCardCount), found $cardCount" }
foreach ($token in @('192×192px','576×576px','nearest-neighbor','REVIEW_TEMPLATE.md','수용 제안은 승인 자체가 아니며','자동 저장·네트워크 전송·승인 레지스트리 변경을 하지 않습니다')) {
    if (-not $visibleHtml.Contains($token)) { throw "Required gallery text missing: $token" }
}
if ($html -notmatch 'id="run-v5"[^>]*data-status="pending"' -or $html -notmatch 'elven_fighter_run_stride_v5_far_leg_forward_candidate_1254x1254\.png') { throw 'The v5 original must remain a pending gallery candidate.' }
foreach ($evidence in @('player_run_v5_antiphase_comparison.png','player_run_v5_motion_strip.png','player_run_v5_antiphase_gate.md','player_run_v5_motion_gate.md')) {
    if (-not $html.Contains($evidence)) { throw "v5 gallery evidence missing: $evidence" }
}
foreach ($evidence in @('player_animation_state_matrix.png','player_motion_states_capture.png','qa_actual_gameplay_20261009.png','player_run_v3_antiphase_strip.png')) {
    if (-not $html.Contains($evidence)) { throw "Window evidence missing: $evidence" }
}
foreach ($token in @('elven_fighter_run_stride_v3_left_lead_candidate_1254x1254.png','player_run_v3_antiphase_strip.png','동일 앞발 리드와 반대 보폭 미입증')) {
    if (-not $visibleHtml.Contains($token)) { throw "run-v3 non-acceptance evidence missing: $token" }
}
foreach ($version in 1..5) {
    if ($html -notmatch ('id="run-v' + $version + '"[^>]*data-status="pending"')) { throw "run-v$version must remain an unapproved card." }
    $runCard = [regex]::Match($html, ('<article class="card" id="run-v' + $version + '"[\s\S]*?</article>'))
    if (-not $runCard.Success -or -not $runCard.Value.Contains('v1-v5 same stride not accepted') -or -not $visibleHtml.Contains('v1~v5 동일 보폭')) { throw "run-v$version same-stride rejection missing." }
}
if ($html -notmatch 'id="turn"[^>]*data-status="procedural"') { throw 'The procedural turn action card must remain.' }
if ($turnOriginalExists) {
    foreach ($token in @('id="turn-rear-mid"','data-status="pending"','elven_fighter_turn_rear_mid_v1_candidate_1254x1254.png','player_turn_mid_comparison.png','player_turn_candidate_motion_gate.md','달리기형 보폭','크기 팝','미수용')) {
        if (-not $visibleHtml.Contains($token)) { throw "Secured turn candidate must appear as an unapproved card with evidence: $token" }
    }
    if (Test-Path -LiteralPath (Join-Path $ProjectRoot $turnSafe) -PathType Leaf) {
        if (-not $html.Contains('elven_fighter_turn_rear_mid_v1_safe_candidate_1254x1254.png')) { throw 'The available turn safe derivative must be linked.' }
    }
} elseif (-not $turnV2Exists -and $visibleHtml -notmatch '전용 turn 후보 PNG 미확보') { throw 'Missing-turn state must be shown only when both turn source candidates are unavailable.' }
if ($turnV2Exists) {
    foreach ($token in @('id="turn-rear-mid-v2"',[IO.Path]::GetFileName($turnV2Original),'신규 v2 원본·safe 후보 확보','별도 미승인 카드')) {
        if (-not $visibleHtml.Contains($token)) { throw "Available turn v2 must be linked as a separate pending card: $token" }
    }
    if ($turnV2Safe -and -not $html.Contains([IO.Path]::GetFileName($turnV2Safe))) { throw 'The available v2 safe derivative must be linked.' }
    foreach ($evidence in @('player_turn_pivot_v2_comparison.png','player_turn_pivot_v2_window.png','player_turn_pivot_v2_gate.md')) {
        if (-not $html.Contains($evidence)) { throw "Turn v2 review evidence missing: $evidence" }
    }
} elseif ($visibleHtml -notmatch '신규 v2 원본은 현재 미확보입니다') { throw 'Missing turn v2 state must be visible when no source exists.' }
foreach ($decision in @('safe 후보의 검정·적색 복장','16.23 game px','체공 미입증','jump anchor 미검증','6.7% 차이','Num5 v1 직선 타격형 미수용','Num5 v2 직선 타격형 미수용','직선 타격형으로 읽힌다. Num5 v1/v2 모두 회전 접촉으로 미수용한다.')) {
    if (-not $visibleHtml.Contains($decision)) { throw "Recorded visual review finding missing: $decision" }
}

# Download is gated by a per-card click, contains REVIEW_TEMPLATE fields, and records a non-approval disclaimer.
foreach ($token in @('download-review','addEventListener(''click''','new Blob','a.click()','reviewer','review-time','conditions','proposal','reason','판정:','실제 플레이/표시 조건:','검수 일시 (시간대 포함):','☑ 아니오','비승인 제안 기록')) {
    if (-not $visibleHtml.Contains($token)) { throw "Explicit local review download contract missing: $token" }
}
foreach ($token in @('## 검수 정보','## 후보별 판정','- 판정:','- 검수자:','- 검수 일시 (시간대 포함):','- 실제 플레이/표시 조건:','- 수정 요청 또는 반려 근거:')) {
    if (-not $template.Contains($token)) { throw "REVIEW_TEMPLATE contract field missing: $token" }
}
if ($html -match 'reviewed_frame_allowlist\.json|fetch\s*\(|XMLHttpRequest|sendBeacon|localStorage|sessionStorage|FileSystem|showSaveFilePicker') {
    throw 'Gallery must not access the approval registry, persist input, or send review data.'
}

# If Node.js is installed, exercise the actual click handler with an in-memory browser stub.
# This captures the Blob payload only; it does not create or save a file.
$nodeCommand = Get-Command node -ErrorAction SilentlyContinue
if ($nodeCommand) {
    $nodeSource = @'
const fs=require('fs'),vm=require('vm');
const html=fs.readFileSync(process.argv[1],'utf8');
const script=html.match(/<script>([\s\S]*)<\/script>/)[1];
const handlers={},fields={'.proposal':{value:'수용 제안'},'.reason':{value:'시뮬레이션 검증 사유'},'.reviewer':{value:'검수자 테스트'},'.conditions':{value:'192×192, 양향, 3×'},'.review-time':{value:''}};
const card={id:'run-v3',dataset:{candidate:'Run v3 candidate'},querySelector:(s)=>fields[s]};
const button={addEventListener:(name,fn)=>handlers.download=fn,closest:()=>card};
let captured='',downloadName='';
const document={querySelector:(s)=>({value:s==='#search'?'':'all',addEventListener:()=>{},setAttribute:()=>{},textContent:''}),querySelectorAll:(s)=>s==='.card'?[]:[button],body:{classList:{toggle:()=>false},appendChild:()=>{}},createElement:()=>({click(){downloadName=this.download},remove(){}})};
class CapturedBlob{constructor(parts,options){captured=parts.join('');if(options.type!=='text/markdown;charset=utf-8')throw Error('wrong MIME')}}
const context={document,Blob:CapturedBlob,URL:{createObjectURL:()=> 'blob:local',revokeObjectURL:()=>{}},setTimeout:()=>{},alert:(m)=>{throw Error(m)},console};
vm.runInNewContext(script,context);handlers.download();
for(const token of ['☑ 수용 제안','### 후보: Run v3 candidate','검수자 테스트','시뮬레이션 검증 사유','192×192, 양향, 3×','비승인 제안 기록','승인 프레임 등록이나 본편 사용 권한을 부여하지 않는다.'])if(!captured.includes(token))throw Error('download payload missing: '+token);
const dateLine=captured.split('\n').find(line=>line.startsWith('- 검수 일시 (시간대 포함): '));
if(!dateLine||!/[0-9]{4}/.test(dateLine)||dateLine.includes('미기록'))throw Error('download timestamp missing');
if(downloadName!=='review_run-v3.md')throw Error('download name mismatch');
console.log('PASS: explicit-click Markdown payload contains candidate review fields and a non-approval notice');
'@
    $nodeEncoded = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($nodeSource))
    $nodeArgument = "eval(Buffer.from('$nodeEncoded','base64').toString())"
    & $nodeCommand.Source -e $nodeArgument $htmlPath
    if ($LASTEXITCODE -ne 0) { throw 'Download payload execution check failed.' }
}

# Verify every relative src/href resolves, including evidence, candidate PNGs, and the template.
$galleryDirectory = Split-Path -Parent $htmlPath
$references = [regex]::Matches($html, '(?:src|href)="([^"]+)"')
foreach ($match in $references) {
    $reference = [System.Net.WebUtility]::HtmlDecode($match.Groups[1].Value)
    if ($reference.StartsWith('#') -or $reference -match '^(?i)(https?:|data:|mailto:|blob:)') { continue }
    $reference = [uri]::UnescapeDataString(($reference -split '[?#]', 2)[0]).Replace('/', [System.IO.Path]::DirectorySeparatorChar)
    $target = [System.IO.Path]::GetFullPath((Join-Path $galleryDirectory $reference))
    if (-not (Test-Path -LiteralPath $target -PathType Leaf)) { throw "Broken local gallery reference: $($match.Groups[1].Value) -> $target" }
}

Write-Output ("PASS: 17 original cards and v5/Window evidence preserved; run-v3 pending; turn source {0} and pending candidate card {1}; hit, jump and Num5 findings represented; 192px/576px mirrored review and explicit non-approval Markdown download checked; all local references resolve." -f $(if ($turnOriginalExists) { 'secured' } else { 'missing' }), $(if ($turnOriginalExists) { 'present' } else { 'not applicable' }))
