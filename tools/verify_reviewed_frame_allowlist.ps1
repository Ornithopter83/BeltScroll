param(
	[Parameter(Mandatory = $false)]
	[string]$ProjectRoot = ''
)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($ProjectRoot)) {
	if (-not [string]::IsNullOrWhiteSpace($PSScriptRoot)) { $ProjectRoot = Split-Path -Parent $PSScriptRoot }
	else { $ProjectRoot = (Get-Location).Path }
}
$registryPath = Join-Path $ProjectRoot 'data/art/reviewed_frame_allowlist.json'
$manifestPath = Join-Path $ProjectRoot 'data/art/animation_manifest.json'
$registry = Get-Content -LiteralPath $registryPath -Encoding UTF8 -Raw | ConvertFrom-Json
$manifestBytes = [System.IO.File]::ReadAllBytes($manifestPath)
$manifestHash = [System.Security.Cryptography.SHA256]::Create().ComputeHash($manifestBytes)
$manifestHash = ([System.BitConverter]::ToString($manifestHash)).Replace('-', '').ToLowerInvariant()
$manifest = Get-Content -LiteralPath $manifestPath -Encoding UTF8 -Raw | ConvertFrom-Json

if ($registry.schema_version -ne 1 -or $null -eq $registry.entries) {
	throw 'Reviewed-frame allowlist must use schema_version 1 and an entries array.'
}

$approvedKeys = @{}
foreach ($entry in $registry.entries) {
	$key = '{0}_{1}' -f $entry.clip, $entry.phase
	if ($entry.clip -notin @('attack1', 'attack2', 'attack3') -or $entry.phase -notin @('startup', 'inbetween', 'recovery')) {
		throw "Registry entry $key uses an unsupported clip or phase. Contact art remains under the legacy byte allowlist."
	}
	if ($approvedKeys.ContainsKey($key)) { throw "Duplicate registry key: $key" }
	$approvedKeys[$key] = $true
	foreach ($field in @('clip', 'phase', 'texture', 'sha256', 'duration', 'foot_anchor', 'review_record', 'manifest_sha256')) {
		if ($null -eq $entry.$field) { throw "Registry entry $key is missing $field." }
	}
	if ($entry.sha256 -cnotmatch '^[0-9a-f]{64}$' -or $entry.manifest_sha256 -cnotmatch '^[0-9a-f]{64}$') {
		throw "Registry entry $key has a malformed SHA-256."
	}
	if ($entry.manifest_sha256 -cne $manifestHash) { throw "Registry entry $key does not bind the current manifest bytes." }
	if ($entry.duration -le 0 -or $entry.duration -gt 10) { throw "Registry entry $key has an invalid duration." }
	if ($entry.foot_anchor.x -lt 0 -or $entry.foot_anchor.x -gt 1 -or $entry.foot_anchor.y -lt 0 -or $entry.foot_anchor.y -gt 1) {
		throw "Registry entry $key has a non-normalized foot anchor."
	}
	if ($entry.texture -notmatch '^res://assets/art/player/[A-Za-z0-9_.-]+\.png$') { throw "Registry entry $key texture must be a project PNG path without traversal segments." }
	$textureRelative = $entry.texture.Substring('res://'.Length).Replace('/', [System.IO.Path]::DirectorySeparatorChar)
	$texturePath = [System.IO.Path]::GetFullPath((Join-Path $ProjectRoot $textureRelative))
	$rootFull = [System.IO.Path]::GetFullPath($ProjectRoot).TrimEnd([System.IO.Path]::DirectorySeparatorChar) + [System.IO.Path]::DirectorySeparatorChar
	if (-not $texturePath.StartsWith($rootFull, [System.StringComparison]::OrdinalIgnoreCase) -or -not (Test-Path -LiteralPath $texturePath -PathType Leaf)) {
		throw "Registry entry $key texture escapes the project or is missing."
	}
	$actualHash = (Get-FileHash -LiteralPath $texturePath -Algorithm SHA256).Hash.ToLowerInvariant()
	if ($actualHash -cne $entry.sha256) { throw "Registry entry $key PNG SHA-256 does not match its bytes." }
	if ($entry.review_record -notmatch '^res://docs/review/records/[A-Za-z0-9_.-]+$') { throw "Registry entry $key review record must be under docs/review/records without traversal segments." }
	$recordRelative = $entry.review_record.Substring('res://'.Length).Replace('/', [System.IO.Path]::DirectorySeparatorChar)
	$recordPath = [System.IO.Path]::GetFullPath((Join-Path $ProjectRoot $recordRelative))
	if (-not $recordPath.StartsWith($rootFull, [System.StringComparison]::OrdinalIgnoreCase) -or -not (Test-Path -LiteralPath $recordPath -PathType Leaf)) {
		throw "Registry entry $key manual review record is missing or escapes the project."
	}
	if ([string]::IsNullOrWhiteSpace((Get-Content -LiteralPath $recordPath -Encoding UTF8 -Raw))) { throw "Registry entry $key review record is empty." }

	$clip = @($manifest.clips | Where-Object { $_.id -ceq $entry.clip })
	$matches = @($clip | ForEach-Object { $_.frames } | Where-Object { $_.phase -ceq $entry.phase -and $_.approval_state -ceq 'approved' })
	if ($matches.Count -ne 1) { throw "Registry entry $key must match exactly one approved manifest frame." }
	$frame = $matches[0]
	if ($frame.texture -cne $entry.texture -or [double]$frame.duration -ne [double]$entry.duration -or [double]$frame.foot_anchor.x -ne [double]$entry.foot_anchor.x -or [double]$frame.foot_anchor.y -ne [double]$entry.foot_anchor.y) {
		throw "Registry entry $key does not match the manifest frame identity, duration, or anchor."
	}
}

$legacy = @{
	'idle_idle' = 'res://assets/art/player/elven_fighter_reference_v8_clean_candidate_1254x1254.png'
	'attack1_contact' = 'res://assets/art/player/elven_fighter_attack1_reference_v1_contour_candidate_1254x1254.png'
	'attack2_contact' = 'res://assets/art/player/elven_fighter_attack2_reference_v4_ink_final_candidate_1254x1254.png'
	'attack3_contact' = 'res://assets/art/player/elven_fighter_attack3_reference_v2_contour_candidate_1254x1254.png'
}
$seenLegacy = @{}
foreach ($clip in $manifest.clips) {
	foreach ($frame in $clip.frames) {
		$key = '{0}_{1}' -f $clip.id, $frame.phase
		if ($frame.approval_state -ceq 'approved') {
			if ($legacy.ContainsKey($key) -and $legacy[$key] -ceq $frame.texture) {
				$seenLegacy[$key] = $true
			} elseif (-not $approvedKeys.ContainsKey($key)) {
				throw "Approved non-legacy candidate has no reviewed registry entry: $key"
			}
		}
		if ($frame.approval_state -cne 'approved' -and $approvedKeys.ContainsKey($key)) {
			throw "Registry entry $key is not promoted in the manifest."
		}
	}
}
foreach ($key in $legacy.Keys) {
	if (-not $seenLegacy.ContainsKey($key)) { throw "Existing approved art was changed or removed: $key" }
}
if ($registry.entries.Count -eq 0) {
	Write-Output 'PASS: reviewed-frame registry is empty; existing approvals are intact and candidates remain unapplied.'
} else {
	Write-Output ("PASS: verified {0} reviewed-frame promotion(s), bound to current manifest and PNG bytes." -f $registry.entries.Count)
}
