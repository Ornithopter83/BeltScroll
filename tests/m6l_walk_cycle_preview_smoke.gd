extends SceneTree
"""Checks the isolated, animated M6L walk-candidate review contract."""

const SCENE_PATH := "res://scenes/review/m6k_walk_cycle_preview.tscn"
const SCRIPT_PATH := "res://tools/prepare_m6k_walk_candidate_preview.gd"
const GATE_PATH := "res://docs/review/m6l_walk_cycle_review_gate.md"
const OPPOSITE_PATH := "res://assets/art/player/elven_fighter_walk_opposite_stride_v1_candidate_1254x1254.png"
const PASSING_PATH := "res://assets/art/player/elven_fighter_walk_passing_v1_candidate_1254x1254.png"
const LEGACY_FILES := [
	"res://assets/art/player/elven_fighter_run_stride_v1_candidate_1254x1254.png",
	"res://assets/art/player/elven_fighter_run_stride_v2_opposite_candidate_1254x1254.png",
	"res://assets/art/player/elven_fighter_run_stride_v3_left_lead_candidate_1254x1254.png",
	"res://assets/art/player/elven_fighter_run_stride_v4_opposite_contact_candidate_1254x1254.png",
	"res://assets/art/player/elven_fighter_run_stride_v5_far_leg_forward_candidate_1254x1254.png",
]

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var failures: Array[String] = []
	_check(FileAccess.file_exists(SCENE_PATH), "F6 review scene exists", failures)
	_check(FileAccess.file_exists(SCRIPT_PATH), "animated review script exists", failures)
	_check(FileAccess.file_exists(GATE_PATH), "human review gate exists", failures)
	var preview_script := load(SCRIPT_PATH) as GDScript
	_check(preview_script != null, "animated review script parses", failures)
	for path in LEGACY_FILES:
		_check(FileAccess.file_exists(path), "legacy candidate exists: " + path.get_file(), failures)
	_check(FileAccess.file_exists(OPPOSITE_PATH), "opposite-stride source PNG is acquired", failures)
	if FileAccess.file_exists(SCENE_PATH):
		var scene := FileAccess.get_file_as_string(SCENE_PATH)
		_check(scene.contains("prepare_m6k_walk_candidate_preview.gd"), "scene attaches the dedicated preview script", failures)
	if FileAccess.file_exists(SCRIPT_PATH):
		var source := FileAccess.get_file_as_string(SCRIPT_PATH)
		_check(source.contains("DISPLAY_HEIGHT := 192.0") and source.contains("FRAME_SECONDS"), "candidate frames play at 192px with a continuous cadence", failures)
		_check(source.contains("_find_additional_stride_candidates") and source.contains("lower.contains(\"stride\")"), "walk opposite stride is discovered from the acquired PNG", failures)
		_check(source.contains("lower.contains(\"passing\")"), "passing keypose filenames without stride are independently discovered", failures)
		_check(source.contains("not lower.contains(\"_safe\")"), "safe-matte derivatives do not crowd the stride review sequence", failures)
		_check(source.contains("KEY_SPACE") and source.contains("KEY_LEFT") and source.contains("KEY_RIGHT"), "preview supports pause, resume, and manual frame stepping", failures)
		_check(source.contains("_detect_duplicate_drawings") and source.contains("FAIL · 동일 원화 중복"), "identical stride drawings produce a visible FAIL", failures)
		_check(source.contains("same_run_lead") and source.contains("FAIL · 같은 전진 보폭 phase 반복") and source.contains("_stride_phase_failures"), "visually repeated run-stride phase is judged and shown as FAIL", failures)
		_check(source.contains("manifest") and source.contains("allowlist") and source.contains("Player 연결 없음"), "preview declares its isolated integration boundary", failures)
		_check(not source.contains("RESOURCE 보폭 후보") and not source.contains("has_resource_candidate"), "acquired opposite stride is not misreported as a missing RESOURCE", failures)
	if FileAccess.file_exists(OPPOSITE_PATH) and preview_script != null:
		var preview := Control.new()
		preview.set_script(preview_script)
		var load_started_usec := Time.get_ticks_usec()
		root.add_child(preview)
		await process_frame
		var load_elapsed_ms := float(Time.get_ticks_usec() - load_started_usec) / 1000.0
		_check(load_elapsed_ms < 10000.0, "candidate image processing completes under 10 seconds (%.1f ms)" % load_elapsed_ms, failures)
		var candidates: Array = preview.get("_candidates")
		_check(candidates.size() >= LEGACY_FILES.size() + 1, "acquired locomotion drawings are sequenced as separate frames", failures)
		var safe_derivative_found := false
		for candidate in candidates:
			safe_derivative_found = safe_derivative_found or str(candidate.get("path", "")).to_lower().contains("_safe")
		_check(not safe_derivative_found, "review sequence stays on stride drawings rather than safe-matte derivatives", failures)
		var opposite_loaded := false
		var loaded_texture_count := 0
		for candidate in candidates:
			if not bool(candidate.get("missing", true)) and candidate.get("texture") is Texture2D:
				loaded_texture_count += 1
			if str(candidate.get("path", "")) == OPPOSITE_PATH:
				opposite_loaded = not bool(candidate.get("missing", true))
		_check(loaded_texture_count >= LEGACY_FILES.size() + 1, "real candidate PNGs load as drawable textures", failures)
		_check(opposite_loaded, "acquired opposite stride is loaded as an independent review frame", failures)
		var phase_failures: Array = preview.get("_stride_phase_failures")
		var phase_duplicate_count := 0
		for candidate in candidates:
			if bool(candidate.get("phase_duplicate", false)):
				phase_duplicate_count += 1
		_check(phase_duplicate_count >= 2 and not phase_failures.is_empty() and str(phase_failures[0]).contains("같은 전진 보폭 phase 반복"), "runtime duplicate phase markers feed the visible FAIL summary", failures)
		preview.call("_unhandled_key_input", _key_event(KEY_SPACE))
		_check(not bool(preview.get("_playing")), "Space pauses the continuous preview", failures)
		preview.call("_unhandled_key_input", _key_event(KEY_SPACE))
		_check(bool(preview.get("_playing")), "Space resumes the continuous preview", failures)
		var advancing_index := int(preview.get("_frame_index"))
		preview.call("_process", 0.19)
		_check(int(preview.get("_frame_index")) == posmod(advancing_index + 1, candidates.size()), "continuous playback advances a frame after one cadence", failures)
		preview.call("_unhandled_key_input", _key_event(KEY_SPACE))
		_check(not bool(preview.get("_playing")), "Space pauses again before manual stepping", failures)
		var paused_index := int(preview.get("_frame_index"))
		preview.call("_unhandled_key_input", _key_event(KEY_RIGHT))
		_check(not bool(preview.get("_playing")) and int(preview.get("_frame_index")) == posmod(paused_index + 1, candidates.size()), "Right advances one frame while paused", failures)
		preview.call("_unhandled_key_input", _key_event(KEY_LEFT))
		_check(int(preview.get("_frame_index")) == paused_index, "Left advances back to the prior frame", failures)
		preview.queue_free()
	if FileAccess.file_exists(PASSING_PATH) and preview_script != null:
		var preview := Control.new()
		preview.set_script(preview_script)
		root.add_child(preview)
		await process_frame
		var candidates: Array = preview.get("_candidates")
		var passing_loaded := false
		for candidate in candidates:
			if str(candidate.get("path", "")) == PASSING_PATH:
				passing_loaded = not bool(candidate.get("missing", true)) and str(candidate.get("kind", "")).contains("독립 검토")
		_check(passing_loaded, "passing candidate appears as an independent frame only when its file exists", failures)
		preview.queue_free()
	if failures.is_empty():
		print("m6l_walk_cycle_preview_smoke: acquired candidates, playback controls, and review isolation are present")
		quit(0)
		return
	for failure in failures:
		push_error("m6l_walk_cycle_preview_smoke: " + failure)
	quit(1)

func _check(condition: bool, message: String, failures: Array[String]) -> void:
	if condition:
		print("PASS: " + message)
	else:
		failures.append(message)

func _key_event(key: Key) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = key
	event.pressed = true
	return event
