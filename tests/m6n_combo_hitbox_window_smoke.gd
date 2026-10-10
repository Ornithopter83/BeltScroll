extends SceneTree
"""Checks M6N capture provenance, source-video hash, measured report, and PNG."""

const TOOL_PATH := "res://tools/capture_m6n_combo_hitbox_window.gd"
const REPORT_PATH := "res://docs/review/m6n_video_comparison_gate.md"
const IMAGE_PATH := "res://assets/art/review/m6n_combo_hitbox_contact_sheet.png"
const VIDEO_PATH := "res://temp/ProjectHub/attachments/30319a1f00274afb8876fbb88d14dd9ahq/BeltScroll (DEBUG) 2026-10-10 14-56-36.mp4"
const EXPECTED_SHA256 := "113A486A3D025A1166FA1143D8B1A7139412883B2A6751343947535530B03814"

var _failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var tool := FileAccess.get_file_as_string(TOOL_PATH)
	_check(not tool.is_empty(), "capture tool exists")
	_check(load(TOOL_PATH) != null, "capture tool parses")
	_check(tool.contains("Input.parse_input_event") and tool.contains("source=auto_input_event") and tool.contains("human_visual_approval=false"), "synthetic input and automated capture provenance are explicit")
	_check(tool.contains("DisplayServer.get_name() == \"headless\"") and tool.contains("root.get_texture().get_image()"), "capture requires a rendered Godot Window viewport")
	_check(tool.contains("attack_phase") and tool.contains("combo_hold") and tool.contains("monitoring") and tool.contains("global_position"), "combo phases, hitbox state, and world positions are observed")
	_check(tool.contains("set_combat_active") and tool.contains("_wait_for_player_hp_change") and tool.contains("_wait_for_boss_hp_change"), "Raider and Boss use live combat activation and health observations")
	_check(not tool.contains("set(\"health\"") and not tool.contains("receive_hit(") and not tool.contains("_begin_attack("), "no direct HP mutation or internal combat invocation")

	var video_bytes := FileAccess.get_file_as_bytes(VIDEO_PATH)
	if video_bytes.is_empty():
		_check(false, "attached reference video is readable for SHA256")
	else:
		var hashing := HashingContext.new()
		var hash_started := hashing.start(HashingContext.HASH_SHA256) == OK
		if hash_started:
			hashing.update(video_bytes)
			_check(hashing.finish().hex_encode().to_upper() == EXPECTED_SHA256, "reference video SHA256 matches the requested value")
		else:
			_check(false, "SHA256 context initializes")

	var report := FileAccess.get_file_as_string(REPORT_PATH)
	_check(report.contains(EXPECTED_SHA256), "report records the verified video SHA256")
	_check(report.contains("UNVERIFIED") and report.contains("ffmpeg") and report.contains("human_visual_approval"), "source comparison remains unverified with honest automation provenance")
	_check(report.contains("IDLE 프레임") and report.contains("활성 판정") and report.contains("Raider HP") and report.contains("Boss HP"), "report includes requested combo, hitbox, and HP measurements")
	_check(report.contains("source=auto_input_event") and report.contains("육안 승인"), "report does not claim physical input or human visual approval")
	_check(report.contains("1타 x") and report.contains("2타 x") and report.contains("3타 x") and report.contains("OFF 상태 확인") and report.contains("ON 상태 확인"), "report has per-stage hitbox offsets and both F10 states")

	var image := Image.new()
	var load_error := image.load(ProjectSettings.globalize_path(IMAGE_PATH))
	_check(load_error == OK, "Window contact sheet PNG decodes")
	if load_error == OK:
		_check(image.get_width() == 1920 and image.get_height() >= 270, "contact sheet uses 480x270 cells across four columns")
	_finish()

func _check(condition: bool, message: String) -> void:
	if condition:
		print("PASS: " + message)
	else:
		_failures.append(message)

func _finish() -> void:
	if _failures.is_empty():
		print("m6n_combo_hitbox_window_smoke: PASS")
		quit(0)
		return
	for message in _failures:
		push_error("m6n_combo_hitbox_window_smoke: " + message)
	quit(1)
