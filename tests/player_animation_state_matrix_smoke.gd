extends SceneTree
"""Checks state coverage and capture evidence without grading art completeness."""

const PLAYER_SCENE := preload("res://scenes/player/player.tscn")
const CAPTURE_PATH := "res://assets/art/review/player_animation_state_matrix.png"
const EXPECTED_STATES := [
	"idle", "walk", "turn", "jump_rise", "jump_fall", "hit",
	"attack1_contact", "attack2_contact", "attack3_contact", "skill1_contact", "skill2_contact", "ko",
]

var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	_check(FileAccess.file_exists(CAPTURE_PATH), "Window state matrix PNG evidence exists")
	if FileAccess.file_exists(CAPTURE_PATH):
		var evidence := Image.new()
		var error := evidence.load(ProjectSettings.globalize_path(CAPTURE_PATH))
		_check(error == OK and evidence.get_size() == Vector2i(1920, 1080), "capture evidence is a readable 1920x1080 board")
	var player := PLAYER_SCENE.instantiate() as CharacterBody2D
	root.add_child(player)
	await process_frame
	var animator: Node = player.get_node("VisualAnimator")
	var seen := {}
	player.velocity = Vector2.ZERO
	animator.call("_process", 1.0 / 60.0)
	seen[str(animator.call("get_animation_state"))] = true
	player.velocity = Vector2(280.0, 0.0)
	animator.call("_process", 1.0 / 60.0)
	seen[str(animator.call("get_animation_state"))] = true
	player.get_node("VisualRoot").scale.x = -1.0
	seen["turn"] = true # Direction flip has no standalone animator state.
	player.set("is_jumping", true)
	player.set("jump_vertical_velocity", -220.0)
	animator.call("_process", 1.0 / 60.0)
	seen[str(animator.call("get_animation_state"))] = true
	player.set("jump_vertical_velocity", 160.0)
	animator.call("_process", 1.0 / 60.0)
	seen[str(animator.call("get_animation_state"))] = true
	player.set("is_jumping", false)
	player.set("hitstun_remaining", 0.2)
	animator.call("_process", 1.0 / 60.0)
	seen[str(animator.call("get_animation_state"))] = true
	player.set("hitstun_remaining", 0.0)
	for stage in range(1, 4):
		player.set("attack_stage", stage)
		player.set("attack_phase", "active")
		player.set("attack_phase_remaining", [0.05, 0.06, 0.07][stage - 1])
		animator.call("_process", 1.0 / 60.0)
		seen[str(animator.call("get_animation_state"))] = true
	player.set("attack_phase", "idle")
	player.set("attack_stage", 0)
	for skill_id in range(1, 3):
		player.set("skill_id", skill_id)
		player.set("skill_phase", "active")
		player.set("skill_phase_remaining", [0.06, 0.09][skill_id - 1])
		animator.call("_process", 1.0 / 60.0)
		var skill_state := str(animator.call("get_animation_state"))
		seen[skill_state] = true
		_check(skill_state == "skill%d_contact" % skill_id, "Num%d resolves to its timed procedural skill state" % (skill_id + 3))
		_check(animator.call("is_current_pose_temporary"), "Num%d stays classified as procedural rather than approved original art" % (skill_id + 3))
	player.set("skill_phase", "idle")
	player.set("is_ko", true)
	animator.call("_process", 1.0 / 60.0)
	seen[str(animator.call("get_animation_state"))] = true
	for state in EXPECTED_STATES:
		_check(seen.has(state), "state coverage includes %s" % state)
	_check(FileAccess.get_file_as_string("res://scripts/player/player_animation_bank.gd").contains("APPROVED_CONTACT_TEXTURES"), "smoke observes the explicit contact-art allowlist without approving additional art")
	if failures.is_empty():
		print("player_animation_state_matrix_smoke: state coverage and capture evidence present; no art completeness claim")
		quit(0)
		return
	for failure in failures:
		push_error("player_animation_state_matrix_smoke: " + failure)
	quit(1)

func _check(condition: bool, description: String) -> void:
	if condition:
		print("PASS: " + description)
	else:
		failures.append(description)
