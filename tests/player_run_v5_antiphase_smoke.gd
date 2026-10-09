extends SceneTree
"""Checks the v5 anti-phase candidate gate without approving or integrating it."""

const V1_SAFE := "res://assets/art/player/elven_fighter_run_stride_v1_safe_candidate_1254x1254.png"
const V5_SOURCE := "res://assets/art/player/elven_fighter_run_stride_v5_far_leg_forward_candidate_1254x1254.png"
const V5_SAFE := "res://assets/art/player/elven_fighter_run_stride_v5_safe_candidate_1254x1254.png"
const PREPARE := "res://tools/prepare_player_run_v5_safe.gd"
const REVIEW := "res://assets/art/review/player_run_v5_antiphase_comparison.png"
const GATE := "res://docs/review/player_run_v5_antiphase_gate.md"
const EXPECTED_V5_FILENAME := "elven_fighter_run_stride_v5_far_leg_forward_candidate_1254x1254.png"

var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	_check(_valid_rgba(V1_SAFE), "v1 safe comparison input is a 1254x1254 RGBA8 PNG")
	_check(FileAccess.file_exists(PREPARE), "conditional v5 safe and comparison generator exists")
	_check(FileAccess.file_exists(REVIEW), "fixed 192px whole-canvas comparison image exists")
	_check(FileAccess.file_exists(GATE), "human review gate records the current acquisition state")
	if FileAccess.file_exists(REVIEW):
		var review := Image.new()
		_check(review.load(ProjectSettings.globalize_path(REVIEW)) == OK and review.get_size() == Vector2i(520, 480), "comparison board is a readable 520x480 PNG")
	var has_source := FileAccess.file_exists(V5_SOURCE)
	_check(V5_SOURCE.get_file() == EXPECTED_V5_FILENAME, "v5 source lookup matches the acquired far-leg-forward original filename")
	if has_source:
		_check(_valid_rgba(V5_SOURCE), "acquired v5 original is 1254x1254 RGBA8")
		_check(_valid_rgba(V5_SAFE), "separate safe candidate exists for acquired v5")
		var safe := _load(V5_SAFE)
		if safe != null:
			var bounds := _alpha_bounds(safe)
			var margins := Vector4i(bounds.position.x, bounds.position.y, 1254 - bounds.end.x, 1254 - bounds.end.y)
			_check(margins.x >= 90 and margins.y >= 90 and margins.z >= 90 and margins.w >= 90, "v5 safe alpha margins are at least 90px on all sides")
			_check(_isolated_count(safe) == 0, "v5 safe has no isolated alpha pixels")
	else:
		_check(not FileAccess.file_exists(V5_SAFE), "no v5 safe is fabricated while its original is absent")
	if FileAccess.file_exists(PREPARE):
		var source := FileAccess.get_file_as_string(PREPARE)
		_check(source.contains("source_bytes") and source.contains("_sha256(source_bytes)"), "v5 generator records original byte count and SHA-256")
		_check(source.contains("_read_bytes(V5_SOURCE) != source_bytes"), "v5 generator verifies original bytes remain unchanged")
		_check(source.contains("MIN_MARGIN := 90") and source.contains("_isolated_count(safe)"), "v5 generator enforces alpha margin and isolated pixel requirements")
		_check(source.contains("DISPLAY := 192") and source.contains("sprite.resize(DISPLAY, DISPLAY"), "comparison uses the full 1254px canvas at a shared 192px scale")
		_check(source.contains("acceptance=not_granted") and source.contains("player_or_manifest_integration=none"), "generator leaves approval and integration to a person")
	if FileAccess.file_exists(GATE):
		var gate := FileAccess.get_file_as_string(GATE)
		_check(gate.contains("가까운 다리") and gate.contains("먼 다리"), "gate explicitly checks near and far leg opposition")
		_check(gate.contains("골반") and gate.contains("포니테일") and gate.contains("발 anchor"), "gate records requested anatomy and anchor comparison fields")
		_check(gate.contains("미수용") and gate.contains("manifest") and gate.contains("승인"), "gate rejects missing or unverified v5 and prohibits registration before approval")
	if failures.is_empty():
		print("player_run_v5_antiphase_smoke: candidate integrity and non-approval gate verified")
		quit(0)
		return
	for failure in failures:
		push_error("player_run_v5_antiphase_smoke: " + failure)
	quit(1)

func _valid_rgba(path: String) -> bool:
	var image := _load(path)
	return image != null and image.get_size() == Vector2i(1254, 1254) and image.get_format() == Image.FORMAT_RGBA8

func _load(path: String) -> Image:
	var full := ProjectSettings.globalize_path(path)
	if not FileAccess.file_exists(full):
		return null
	var bytes := FileAccess.get_file_as_bytes(full)
	var image := Image.new()
	return image if not bytes.is_empty() and image.load_png_from_buffer(bytes) == OK else null

func _alpha_bounds(image: Image) -> Rect2i:
	var left := image.get_width()
	var top := image.get_height()
	var right := -1
	var bottom := -1
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			if image.get_pixel(x, y).a > 0.0:
				left = mini(left, x)
				top = mini(top, y)
				right = maxi(right, x)
				bottom = maxi(bottom, y)
	return Rect2i(left, top, right - left + 1, bottom - top + 1) if right >= left else Rect2i()

func _isolated_count(image: Image) -> int:
	var count := 0
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			if image.get_pixel(x, y).a <= 0.0:
				continue
			var neighbor := false
			for oy in range(-1, 2):
				for ox in range(-1, 2):
					var nx := x + ox
					var ny := y + oy
					if (ox != 0 or oy != 0) and nx >= 0 and ny >= 0 and nx < image.get_width() and ny < image.get_height() and image.get_pixel(nx, ny).a > 0.0:
						neighbor = true
			if not neighbor:
				count += 1
	return count

func _check(condition: bool, message: String) -> void:
	if condition:
		print("PASS: " + message)
	else:
		failures.append(message)
