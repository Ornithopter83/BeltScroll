extends SceneTree

const BLENDER_SCRIPT := preload("res://scripts/player/player_pose_blender.gd")
const BANK_SCRIPT := preload("res://scripts/player/player_animation_bank.gd")
const CONTROLLER_SCRIPT := preload("res://scripts/player/player_controller.gd")
const PLAYER_SCENE := preload("res://scenes/player/player.tscn")
const CONTACT_TEXTURES := {
	"attack1": "res://assets/art/player/elven_fighter_attack1_reference_v1_contour_candidate_1254x1254.png",
	"attack2": "res://assets/art/player/elven_fighter_attack2_reference_v4_ink_final_candidate_1254x1254.png",
	"attack3": "res://assets/art/player/elven_fighter_attack3_reference_v2_contour_candidate_1254x1254.png",
}
const EXPECTED_ACTIVE := [0.105, 0.12, 0.14]

var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var blender: PlayerPoseBlender = BLENDER_SCRIPT.new()
	root.add_child(blender)
	await process_frame
	var bank: RefCounted = BANK_SCRIPT.new()
	_check(bank.call("load_and_register", blender), "schema_version 1 manifest loads without contract errors")
	_check(blender.get_current_texture_path() == "res://assets/art/player/elven_fighter_reference_v8_clean_candidate_1254x1254.png", "v8 remains the idle fallback texture")
	var controller_script: Script = load("res://scripts/player/player_controller.gd") as Script
	var controller_constants: Dictionary = controller_script.get_script_constant_map()
	var hitbox_active: Array = controller_constants["ACTIVE"]
	var controller_startup: Array = controller_constants["STARTUP"]
	var controller_recovery: Array = controller_constants["RECOVERY"]
	for stage in range(1, 4):
		var action := "attack%d" % stage
		var expected_path: String = CONTACT_TEXTURES[action]
		_check(blender.get_registered_frame_count(action, "contact") == 1, "%s has exactly one approved contact frame" % action)
		_check(blender.get_registered_frame_count(action, "startup") == 0 and blender.get_registered_frame_count(action, "recovery") == 0, "%s startup and recovery remain temporary" % action)
		var duration: float = bank.call("get_phase_duration", action, "contact", -1.0)
		var startup_duration: float = bank.call("get_phase_duration", action, "startup", -1.0)
		var recovery_duration: float = bank.call("get_phase_duration", action, "recovery", -1.0)
		_check(is_equal_approx(startup_duration, float(controller_startup[stage - 1])) and is_equal_approx(recovery_duration, float(controller_recovery[stage - 1])), "%s preparation and recovery use their gameplay clock durations" % action)
		_check(is_equal_approx(duration, EXPECTED_ACTIVE[stage - 1]) and is_equal_approx(duration, float(hitbox_active[stage - 1])), "%s contact frame duration matches the live hitbox window" % action)
		_check(blender.set_timed_pose(action, "contact", 0.0, duration, 0.0), "%s contact is selected by the timed pose API" % action)
		_check(blender.get_current_texture_path() == expected_path and is_equal_approx(blender.get_current_registered_frame_duration(), duration), "%s selects its approved texture for the hitbox interval" % action)
		blender.set_facing_left(false)
		var pose_sprite := _visible_sprite(blender)
		_check(pose_sprite != null and not pose_sprite.flip_h, "%s right-facing registration is unflipped" % action)
		_check(_foot_anchor_is_common(blender, pose_sprite), "%s right-facing alpha foot anchor is aligned" % action)
		blender.set_facing_left(true)
		pose_sprite = _visible_sprite(blender)
		_check(pose_sprite != null and pose_sprite.flip_h, "%s left-facing registration mirrors exactly once" % action)
		_check(_foot_anchor_is_common(blender, pose_sprite), "%s left-facing alpha foot anchor is aligned" % action)
	_check(blender.get_registered_frame_count("attack2", "inbetween") == 0, "unapproved inbetween art is not registered")
	_check(blender.get_current_texture_path() != "res://assets/art/player/elven_fighter_attack2_contact_v5_identity_candidate_1254x1254.png", "existing v5 candidate stays unloaded")
	_check(bank.call("get_phase_duration", "attack2", "contact", -1.0) == 0.12, "unapproved v5/v6 candidates cannot replace approved contact timing")
	await _check_editor_export_contract()
	var player: CharacterBody2D = PLAYER_SCENE.instantiate() as CharacterBody2D
	root.add_child(player)
	await process_frame
	var animator: Node = player.get_node("VisualAnimator")
	var integrated_blender: PlayerPoseBlender = player.get_node("VisualRoot/PoseBlender") as PlayerPoseBlender
	for stage in range(1, 4):
		var duration: float = EXPECTED_ACTIVE[stage - 1]
		_check(is_equal_approx(float(animator.call("_attack_phase_duration", stage - 1, "active")), duration), "integrated attack %d reads contact timing from the bank" % stage)
		player.set("attack_stage", stage)
		player.set("attack_phase", "active")
		player.set("attack_phase_remaining", duration * 0.5)
		animator.call("_process", 0.0)
		_check(integrated_blender.visible and integrated_blender.get_current_texture_path() == CONTACT_TEXTURES["attack%d" % stage], "integrated attack %d displays its approved frame during the hitbox window" % stage)
	if failures.is_empty():
		print("player_animation_bank_smoke: all checks passed")
		quit(0)
		return
	for failure in failures:
		push_error("player_animation_bank_smoke: " + failure)
	quit(1)

func _check_editor_export_contract() -> void:
	var absolute_root := OS.get_temp_dir().path_join("BeltScrollAnimationContractSmoke")
	DirAccess.make_dir_recursive_absolute(absolute_root.path_join("textures"))
	var approved_source: String = CONTACT_TEXTURES["attack2"]
	var approved_file := absolute_root.path_join("textures/approved-contact.png")
	var review_file := absolute_root.path_join("textures/review-v6.png")
	_check(DirAccess.copy_absolute(ProjectSettings.globalize_path(approved_source), approved_file) == OK, "editor contract fixture copies existing approved art")
	_check(DirAccess.copy_absolute(ProjectSettings.globalize_path("res://assets/art/player/elven_fighter_reference_v6_clean_1254x1254.png"), review_file) == OK, "editor contract fixture includes v6 review art")
	var document := {
		"schema_version": 1,
		"clips": [{"id": "attack2", "frames": [
			{"texture": "textures/approved-contact.png", "phase": "contact", "duration": 0.12, "foot_anchor": {"x": 0.53, "y": 0.92}, "approval_state": "approved"},
			{"texture": "textures/review-v6.png", "phase": "contact", "duration": 0.3, "foot_anchor": {"x": 0.5, "y": 0.9}, "approval_state": "review"}
		]}]
	}
	var manifest_path := absolute_root.path_join("animation.json")
	var manifest := FileAccess.open(manifest_path, FileAccess.WRITE)
	manifest.store_string(JSON.stringify(document))
	manifest.close()
	var editor_blender: PlayerPoseBlender = BLENDER_SCRIPT.new()
	root.add_child(editor_blender)
	await process_frame
	var editor_bank: RefCounted = BANK_SCRIPT.new()
	var editor_loaded: bool = editor_bank.call("load_and_register", editor_blender, manifest_path)
	if not editor_loaded:
		print("editor contract bank errors: ", editor_bank.last_errors)
	_check(editor_loaded, "editor schema v1 id/object-anchor/review export loads")
	_check(editor_blender.get_registered_frame_count("attack2", "contact") == 1, "external approved allowlisted art registers while review v6 remains excluded")
	_check(is_equal_approx(editor_bank.call("get_phase_duration", "attack2", "contact", -1.0), 0.12), "review frame cannot override approved contact timing")
	_check(editor_blender.set_timed_pose("attack2", "contact", 0.0, 0.12, 0.0), "editor-exported contact is selectable through existing PoseBlender API")
	var sprite := _visible_sprite(editor_blender)
	var expected_foot := Vector2(0.53 * sprite.texture.get_width(), 0.92 * sprite.texture.get_height())
	var actual_foot := sprite.position + (expected_foot - Vector2(sprite.texture.get_size()) * 0.5) * sprite.scale
	_check(actual_foot.distance_to(editor_blender.common_foot_anchor) < 0.1, "editor foot_anchor object controls runtime anchor placement")
	var bad_blender: PlayerPoseBlender = BLENDER_SCRIPT.new()
	root.add_child(bad_blender)
	await process_frame
	var bad_doc := {"schema_version": 1, "clips": [{"id": "attack2", "frames": [{"texture": "textures/review-v6.png", "phase": "contact", "duration": 0.12, "foot_anchor": {"x": 0.5, "y": 0.9}, "approval_state": "approved"}]}]}
	var bad_path := absolute_root.path_join("bypass.json")
	var bad_file := FileAccess.open(bad_path, FileAccess.WRITE)
	bad_file.store_string(JSON.stringify(bad_doc))
	bad_file.close()
	var bad_bank: RefCounted = BANK_SCRIPT.new()
	_check(not bad_bank.call("load_and_register", bad_blender, bad_path), "editor approval cannot bypass pixel allowlist for v6 candidate")
	_check(bad_blender.get_registered_frame_count("attack2", "contact") == 1 and bad_bank.last_registered.is_empty(), "rejected v6 cannot replace built-in approved contact registration")

func _visible_sprite(blender: Node) -> Sprite2D:
	for child in blender.get_children():
		if child is Sprite2D and (child as Sprite2D).visible:
			return child as Sprite2D
	return null

func _foot_anchor_is_common(blender: PlayerPoseBlender, sprite: Sprite2D) -> bool:
	if sprite == null or sprite.texture == null:
		return false
	var bounds := sprite.texture.get_image().get_used_rect()
	var foot_x := float(bounds.position.x) + float(bounds.size.x) * 0.5
	if sprite.flip_h:
		foot_x = float(sprite.texture.get_width()) - foot_x
	var foot_from_center := (Vector2(foot_x, float(bounds.end.y)) - Vector2(sprite.texture.get_size()) * 0.5) * sprite.scale
	return (sprite.position + foot_from_center).distance_to(blender.common_foot_anchor) < 0.1

func _check(condition: bool, description: String) -> void:
	if condition:
		print("PASS: " + description)
	else:
		failures.append(description)
