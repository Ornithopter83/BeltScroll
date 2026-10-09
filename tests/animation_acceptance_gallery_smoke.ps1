[CmdletBinding()]
param([string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot))

$ErrorActionPreference = 'Stop'
$ProjectRoot = [System.IO.Path]::GetFullPath($ProjectRoot)
$builder = Join-Path $ProjectRoot 'tools/build_animation_acceptance_gallery.ps1'
$htmlPath = Join-Path $ProjectRoot 'docs/review/animation_acceptance_gallery.html'
if (-not (Test-Path -LiteralPath $builder -PathType Leaf)) { throw "Builder missing: $builder" }
& $builder -ProjectRoot $ProjectRoot
if (-not (Test-Path -LiteralPath $htmlPath -PathType Leaf)) { throw "Gallery missing: $htmlPath" }
$html = [System.IO.File]::ReadAllText($htmlPath, [System.Text.Encoding]::UTF8)

$requiredIds = @('idle','attack1-contact','attack2-contact','attack3-contact','run-v1','run-v2','run-v4','run-v5','turn','jump-rise','jump-fall','hit','skill1','skill2-v1','skill2-v2','attack1-startup','attack3-startup')
foreach ($id in $requiredIds) {
    if ($html -notmatch ('id="' + [regex]::Escape($id) + '"')) { throw "Required gallery card missing: $id" }
}
$cardCount = [regex]::Matches($html, '<article class="card"').Count
if ($cardCount -ne 17) { throw "Expected 17 review cards, found $cardCount" }
foreach ($token in @('192px','576px','identity','접지','프레임 팝','기존 승인','미승인','REVIEW_TEMPLATE.md','전용 turn 후보 PNG 없음','레지스트리에 쓰는 기능은 없습니다')) {
    if (-not $html.Contains($token)) { throw "Required gallery text missing: $token" }
}
if ($html -notmatch 'id="run-v5"[^>]*data-status="pending"' -or $html -notmatch 'elven_fighter_run_stride_v5_far_leg_forward_candidate_1254x1254\.png') { throw 'The acquired v5 original must be shown as a pending gallery candidate.' }
foreach ($evidence in @('player_run_v5_antiphase_comparison.png','player_run_v5_motion_strip.png','player_run_v5_antiphase_gate.md','player_run_v5_motion_gate.md')) {
    if (-not $html.Contains($evidence)) { throw "v5 gallery evidence missing: $evidence" }
}
if ($html -match 'reviewed_frame_allowlist\.json' -or $html -match 'fetch\s*\(' -or $html -match 'localStorage|sessionStorage|XMLHttpRequest') {
    throw 'Gallery must not reference the approval registry or persist/send review data.'
}

$galleryDirectory = Split-Path -Parent $htmlPath
$references = [regex]::Matches($html, '(?:src|href)="([^"]+)"')
foreach ($match in $references) {
    $reference = [System.Net.WebUtility]::HtmlDecode($match.Groups[1].Value)
    if ($reference.StartsWith('#') -or $reference -match '^(?i)(https?:|data:|mailto:)') { continue }
    $reference = [uri]::UnescapeDataString(($reference -split '[?#]', 2)[0]).Replace('/', [System.IO.Path]::DirectorySeparatorChar)
    $target = [System.IO.Path]::GetFullPath((Join-Path $galleryDirectory $reference))
    if (-not (Test-Path -LiteralPath $target -PathType Leaf)) { throw "Broken local gallery reference: $($match.Groups[1].Value) -> $target" }
}

Write-Output 'PASS: 17 cards; v5 original, safe, Window evidence and gate are linked; all local image/document links exist; approval data is read-only; missing turn art is explicit.'
