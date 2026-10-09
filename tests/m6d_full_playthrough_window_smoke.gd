extends SceneTree
"""Starts the M6D real-Window input replay and checks its evidence and verdicts."""

const TOOL_PATH := "res://tools/capture_m6d_full_playthrough.gd"
const OUTPUT_PATH := "res://assets/art/review/m6d_full_playthrough_evidence.png"
const REQUIRED_PASS_ROWS := [
	"M6D|RESULT|title=PASS",
	"M6D|RESULT|sections_1_to_3=PASS",
	"M6D|RESULT|raider_combat=PASS",
	"M6D|RESULT|boss_encounter_and_attacks=PASS",
	"M6D|RESULT|victory=PASS",
	"M6D|RESULT|restart=PASS",
	"M6D|RESULT|player_hit=PASS",
	"M6D|RESULT|defeat=PASS",
	"M6D|SUMMARY|PASS",
]

var _failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var source := FileAccess.get_file_as_string(TOOL_PATH)
	_check(not source.is_empty(), "playthrough replay tool exists")
	_check(load(TOOL_PATH) != null, "playthrough replay tool parses as GDScript")
	_check(source.contains("InputEventKey.new()") and source.contains("root.push_input(event, true)"), "automated actions are routed into the real Window as input events")
	_check(source.contains("AUTOMATED_INPUT_EVENT_REPLAY") and source.contains("PHYSICAL_INPUT_OBSERVATION") and source.contains("PHYSICAL_INPUT"), "human input and injected input are separately labeled")
	_check(not source.contains("receive_hit(") and not source.contains("_finish_session(") and not source.contains("set(\"health\""), "replay does not force combat damage or victory state")
	_check(source.contains("UNVERIFIED") and source.contains("FAIL"), "unobservable milestones can never silently pass")
	if DisplayServer.get_name() == "headless" or OS.has_feature("dedicated_server"):
		_failures.append("A real Window is required; runtime replay is UNVERIFIED under headless display.")
	else:
		var output: Array = []
		var status := OS.execute(OS.get_executable_path(), ["--path", ProjectSettings.globalize_path("res://"), "--script", TOOL_PATH], output, true)
		var log := "\n".join(PackedStringArray(output))
		if status != 0:
			push_error("M6D child replay log:\n" + log)
		_check(status == 0, "real Window replay exits successfully (code %d)" % status)
		for row in REQUIRED_PASS_ROWS:
			_check(log.contains(row), "runtime milestone: %s" % row)
		_check(log.contains("M6D|MODE|AUTOMATED_INPUT_EVENT_REPLAY"), "runtime identifies automated input source")
		_check(log.contains("M6D|FRAME|RESTART - FRESH GAMEPLAY"), "restart is captured from the fresh gameplay Window")
		_check(log.contains("Boss victory result followed observed boss health reaching zero"), "victory follows real attack and observed health transition")
		_check(log.contains("health decreased") and log.contains("health reaching zero from enemy attacks"), "damage and defeat follow active enemy attacks")
		_check(not log.contains("M6D|FAIL|") and not log.contains("M6D|UNVERIFIED|"), "no runtime failure or unverified milestone")
		var evidence := Image.new()
		var image_error := evidence.load(ProjectSettings.globalize_path(OUTPUT_PATH))
		_check(image_error == OK and not evidence.is_empty(), "actual Window contact sheet decodes")
		if image_error == OK and not evidence.is_empty():
			_check(evidence.get_width() == 1920 and evidence.get_height() >= 4 * 380, "evidence sheet retains all full-width Window checkpoints")
	_finish()

func _check(condition: bool, description: String) -> void:
	if condition:
		print("PASS: " + description)
	else:
		_failures.append(description)

func _finish() -> void:
	if _failures.is_empty():
		print("m6d_full_playthrough_window_smoke: PASS")
		quit(0)
		return
	for failure in _failures:
		push_error("m6d_full_playthrough_window_smoke: " + failure)
	quit(1)
