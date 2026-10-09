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
	var user_args := OS.get_cmdline_user_args()
	var export_arg_index := user_args.find("--exported-manifest")
	if export_arg_index >= 0:
		await _load_actual_editor_export(user_args, export_arg_index)
		return
	var blender: PlayerPoseBlender = BLENDER_SCRIPT.new()
	root.add_child(blender)
	await process_frame
	var bank: RefCounted = BANK_SCRIPT.new()
	_check(bank.call("load_and_register", blender), "schema_version 1 manifest loads without contract errors")
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/art/animation_manifest.json"))
	var registry: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/art/reviewed_frame_allowlist.json"))
	_check(registry.get("schema_version") == 1 and registry.get("entries") is Array and registry["entries"].is_empty(), "reviewed-frame registry starts with zero new approvals")
	_check(not bank.call("_sha256_matches_file", ProjectSettings.globalize_path(CONTACT_TEXTURES["attack2"]), "0000000000000000000000000000000000000000000000000000000000000000"), "syntactically valid but fake PNG SHA-256 is rejected against file bytes")
	_check(not bank.call("_review_record_exists", "res://docs/review/records/missing-manual-review.md"), "promotion without an existing manual review record is rejected")
	_check(bank.call("_is_reviewed_png_path", CONTACT_TEXTURES["attack2"]), "reviewed artwork must use a project PNG path under assets/art/player")
	_check(not bank.call("_is_reviewed_png_path", "res://assets/art/player/forged.jpg"), "non-PNG registry payloads are rejected")
	_check(not bank.call("_is_reviewed_png_path", "res://assets/art/player/../../outside.png"), "registry texture path traversal is rejected")
	_check(not bank.call("_is_review_record_path", "res://docs/review/records/../missing.md"), "manual review record path traversal is rejected")
	_check(bank.call("_promotion_identity", "run", "stride", "res://assets/art/player/a.png") != bank.call("_promotion_identity", "run", "stride", "res://assets/art/player/b.png"), "same run phase keeps reviewed frames distinct by texture identity")
	var forged_run := {"phase": "stride", "duration": 0.1, "texture": CONTACT_TEXTURES["attack1"], "foot_anchor": {"x": 0.5, "y": 0.9}, "approval_state": "approved"}
	_check(not bank.call("_validate_frame", "run", forged_run, "res://data/art/animation_manifest.json"), "extended approved art without a reviewed-frame entry is rejected")
	var duplicate_bank: RefCounted = BANK_SCRIPT.new()
	var reviewed_run_path := "res://assets/art/player/elven_fighter_attack1_reference_v1_safe_1254x1254.png"
	var reviewed_run_frame := {"phase": "stride", "duration": 0.1, "texture": reviewed_run_path, "foot_anchor": {"x": 0.5, "y": 0.9}, "approval_state": "approved"}
	var reviewed_run_identity: String = duplicate_bank.call("_promotion_identity", "run", "stride", reviewed_run_path)
	var reviewed_run_entry := {"clip": "run", "phase": "stride", "texture": reviewed_run_path, "sha256": duplicate_bank.call("_sha256_file", ProjectSettings.globalize_path(reviewed_run_path)), "manifest_sha256": duplicate_bank.call("_sha256_file", ProjectSettings.globalize_path("res://data/art/animation_manifest.json")), "duration": 0.1, "foot_anchor": {"x": 0.5, "y": 0.9}, "review_record": "res://docs/review/records/manual.md"}
	duplicate_bank.set("_promotion_entries", {reviewed_run_identity: reviewed_run_entry})
	_check(duplicate_bank.call("_promotion_frame_matches", "res://data/art/animation_manifest.json", "run", "stride", reviewed_run_frame), "reviewed texture and manifest hashes match the exact approved frame")
	_check(not duplicate_bank.call("_promotion_frame_matches", "res://data/art/animation_manifest.json", "run", "stride", reviewed_run_frame), "a duplicate approved manifest frame cannot reuse one reviewed registry identity")
	_check(blender.get_current_texture_path() == "res://assets/art/player/elven_fighter_reference_v8_clean_candidate_1254x1254.png", "v8 remains the idle fallback texture")
	var run_texture_a := "res://assets/art/player/elven_fighter_attack1_reference_v1_safe_1254x1254.png"
	var run_texture_b := "res://assets/art/player/elven_fighter_attack2_reference_v1_safe_1254x1254.png"
	var run_a: Texture2D = load(run_texture_a)
	var run_b: Texture2D = load(run_texture_b)
	_check(blender.register_pose_frame("run", "stride", run_a, 0.1, "approved manifest frame", "stride 1", Vector2(0.5, 0.9)), "PoseBlender accepts the first explicitly registered stride drawing")
	_check(blender.register_pose_frame("run", "stride", run_b, 0.1, "approved manifest frame", "stride 2", Vector2(0.5, 0.9)), "PoseBlender accepts ordered frames for the same run phase")
	_check(blender.get_registered_frame_count("run", "stride") == 2, "same-phase run frames remain separate texture registrations")
	_check(blender.set_timed_pose("run", "stride", 0.0, 0.2, 0.0, true) and blender.get_current_texture_path() == run_texture_a, "run stride clock begins with the first registered texture")
	_check(blender.set_timed_pose("run", "stride", 0.12, 0.2, 0.0, true) and blender.get_current_texture_path() == run_texture_b, "run stride clock advances to the second registered texture in order")
	_check(blender.set_timed_pose("run", "stride", 0.21, 0.2, 0.0, true) and blender.get_current_texture_path() == run_texture_a, "run stride clock loops on its registered phase duration")
	_check(blender.get_current_registered_frame_label() == "stride 1", "texture-specific frame labels survive same-phase registration")
	var replacement_blender: PlayerPoseBlender = BLENDER_SCRIPT.new()
	root.add_child(replacement_blender)
	await process_frame
	_check(replacement_blender.register_pose_frame("run", "stride", run_a, 0.1, "approved manifest frame", "manifest frame 1", Vector2(-1.0, -1.0), true), "bank replacement batch starts by replacing stale phase art")
	_check(replacement_blender.register_pose_frame("run", "stride", run_b, 0.1, "approved manifest frame", "manifest frame 2", Vector2(-1.0, -1.0), true), "bank replacement batch retains subsequent ordered frames")
	_check(replacement_blender.get_registered_frame_count("run", "stride") == 2, "replacement batch preserves all approved frames for timed playback")
	_check(replacement_blender.set_timed_pose("run", "stride", 0.12, 0.2, 0.0, true) and replacement_blender.get_current_texture_path() == run_texture_b, "replacement-batched frame order is visible on the runtime movement clock")
	var run_reject_blender: PlayerPoseBlender = BLENDER_SCRIPT.new()
	root.add_child(run_reject_blender)
	await process_frame
	var run_reject_bank: RefCounted = BANK_SCRIPT.new()
	var traversal_run := {"schema_version": 1, "clips": [{"id": "run", "frames": [{"phase": "stride", "duration": 0.1, "texture": "../outside.png", "foot_anchor": {"x": 0.5, "y": 0.9}, "approval_state": "review"}]}]}
	var traversal_run_path := OS.get_temp_dir().path_join("BeltScrollRunTraversalSmoke.json")
	_write_json(traversal_run_path, traversal_run)
	_check(not run_reject_bank.call("load_and_register", run_reject_blender, traversal_run_path), "extended frame path traversal is rejected before registration")
	_check(run_reject_blender.get_registered_frame_count("run", "stride") == 0, "rejected extended path cannot leave a partial runtime registration")
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
	for clip_value in manifest["clips"]:
		var clip: Dictionary = clip_value
		for frame_value in clip["frames"]:
			var frame: Dictionary = frame_value
			var action: String = clip["id"]
			var phase: String = frame["phase"]
			var legacy_approved: bool = (action == "idle" and phase == "idle") or (phase == "contact" and action in ["attack1", "attack2", "attack3"] and frame["approval_state"] == "approved")
			if not legacy_approved:
				_check(frame["approval_state"] != "approved", "%s/%s candidate remains unapproved in the main manifest" % [action, phase])
				if phase == "contact" and CONTACT_TEXTURES.has(action):
					_check(blender.get_registered_frame_count(action, phase) == 1 and str(frame["texture"]) != CONTACT_TEXTURES[action], "%s/%s candidate remains unapplied beside its preserved legacy frame" % [action, phase])
				else:
					_check(blender.get_registered_frame_count(action, phase) == 0, "%s/%s candidate remains unapplied in the runtime bank" % [action, phase])
	await _check_editor_export_contract()
	var player: CharacterBody2D = PLAYER_SCENE.instantiate() as CharacterBody2D
	root.add_child(player)
	await process_frame
	var animator: Node = player.get_node("VisualAnimator")
	var integrated_blender: PlayerPoseBlender = player.get_node("VisualRoot/PoseBlender") as PlayerPoseBlender
	for stage in range(1, 4):
		var duration: float = EXPECTED_ACTIVE[stage - 1]
		bank.set("_phase_durations", {"attack%d_contact" % stage: duration * 2.0})
		animator.set("_animation_bank", bank)
		_check(is_equal_approx(float(animator.call("_attack_phase_duration", stage - 1, "active")), duration), "integrated attack %d keeps its hitbox clock when registered art duration differs" % stage)
		player.set("attack_stage", stage)
		player.set("attack_phase", "active")
		player.set("attack_phase_remaining", duration * 0.5)
		animator.call("_process", 0.0)
		_check(integrated_blender.visible and integrated_blender.get_current_texture_path() == CONTACT_TEXTURES["attack%d" % stage], "integrated attack %d displays its approved frame during the hitbox window" % stage)
	var stride_a := "res://assets/art/player/elven_fighter_attack1_reference_v1_safe_1254x1254.png"
	var stride_b := "res://assets/art/player/elven_fighter_attack2_reference_v1_safe_1254x1254.png"
	integrated_blender.register_pose_frame("run", "stride", load(stride_a), 0.1, "approved manifest frame", "stride 1")
	integrated_blender.register_pose_frame("run", "stride", load(stride_b), 0.1, "approved manifest frame", "stride 2")
	player.set("attack_phase", "idle")
	player.set("attack_stage", 0)
	player.velocity = Vector2(280.0, 0.0)
	animator.call("_process", 0.0)
	animator.call("_process", 0.11)
	_check(animator.get_animation_state() == "walk" and integrated_blender.visible and integrated_blender.get_current_texture_path() == stride_b, "integrated run art advances by the live movement state clock")
	player.velocity = Vector2.ZERO
	animator.call("_process", 0.0)
	_check(not integrated_blender.visible and player.get_node("VisualRoot/PlayerArt").visible, "missing run art falls back to the existing procedural PlayerArt")
	var skill_contact := "res://assets/art/player/elven_fighter_attack3_reference_v2_safe_1254x1254.png"
	integrated_blender.register_pose_frame("skill1", "contact", load(skill_contact), 0.12, "approved manifest frame", "skill contact")
	player.set("skill_id", 1)
	player.set("skill_phase", "active")
	player.set("skill_phase_remaining", 0.06)
	animator.call("_process", 0.0)
	_check(animator.get_animation_state() == "skill1_contact" and is_equal_approx(animator.get_state_elapsed(), 0.06), "integrated skill contact keeps the controller phase clock")
	_check(integrated_blender.visible and integrated_blender.get_current_texture_path() == skill_contact, "integrated skill phase selects its reviewed contact texture")
	player.set("skill_phase", "idle")
	player.set("skill_id", 0)
	animator.call("_process", 0.0)
	_check(not integrated_blender.visible, "skill interruption returns to procedural art when the next phase has no frame")
	var rise_texture := "res://assets/art/player/elven_fighter_jump_rise_v1_safe_candidate_1254x1254.png"
	var fall_texture := "res://assets/art/player/elven_fighter_reference_v8_clean_candidate_1254x1254.png"
	integrated_blender.register_pose_frame("jump_rise", "rise", load(rise_texture), 0.16, "approved manifest frame", "jump rise")
	integrated_blender.register_pose_frame("jump_fall", "fall", load(fall_texture), 0.16, "approved manifest frame", "jump fall")
	player.set("is_jumping", true)
	player.set("jump_vertical_velocity", -100.0)
	animator.call("_process", 0.02)
	_check(animator.get_animation_state() == "jump_rise" and integrated_blender.get_current_texture_path() == rise_texture, "integrated jump rise uses the vertical movement state")
	player.set("jump_vertical_velocity", 100.0)
	animator.call("_process", 0.02)
	_check(animator.get_animation_state() == "jump_fall" and integrated_blender.get_current_pose_key() == "jump_fall_fall", "integrated jump fall uses the vertical movement state")
	animator.call("_process", 0.06)
	_check(integrated_blender.get_current_texture_path() == fall_texture, "jump fall transition resolves to its registered texture")
	player.set("is_jumping", false)
	player.set("jump_vertical_velocity", 0.0)
	player.set("hitstun_remaining", 0.1)
	player.set("hit_flash_remaining", 0.05)
	var hit_texture := "res://assets/art/player/elven_fighter_reference_v7_safe_1254x1254.png"
	integrated_blender.register_pose_frame("hit", "reaction", load(hit_texture), 0.12, "approved manifest frame", "hit reaction")
	animator.call("_process", 0.02)
	_check(animator.get_animation_state() == "hit" and integrated_blender.get_current_texture_path() == hit_texture, "integrated hit reaction interrupts jump art and selects its phase")
	player.set("hitstun_remaining", 0.0)
	player.set("hit_flash_remaining", 0.0)
	for _frame in range(8):
		animator.call("_process", 0.02)
	player.set("facing_direction", Vector2.LEFT)
	integrated_blender.register_pose_frame("turn", "turn", load(stride_a), 0.13, "approved manifest frame", "turn")
	animator.call("_process", 0.02)
	_check(animator.call("is_turning") and integrated_blender.get_current_pose_key() == "turn_turn", "integrated turn art follows the facing transition clock")
	player.set("is_ko", true)
	animator.call("_process", 0.02)
	_check(animator.get_animation_state() == "ko" and not integrated_blender.visible, "KO interrupts extended registered art")
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
	_check(DirAccess.copy_absolute(ProjectSettings.globalize_path("res://assets/art/player/elven_fighter_attack2_contact_v6_candidate_1254x1254.png"), review_file) == OK, "editor contract fixture includes the real v6 contact review art")
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
	var traversal_path := absolute_root.path_join("traversal.json")
	var traversal_doc := {"schema_version": 1, "clips": [{"id": "attack2", "frames": [{"texture": "../outside.png", "phase": "contact", "duration": 0.12, "foot_anchor": {"x": 0.5, "y": 0.9}, "approval_state": "review"}]}]}
	_write_json(traversal_path, traversal_doc)
	var traversal_bank: RefCounted = BANK_SCRIPT.new()
	_check(not traversal_bank.call("load_and_register", bad_blender, traversal_path), "relative path traversal is rejected even for review frames")
	var malformed_path := absolute_root.path_join("malformed.json")
	var malformed_doc := {"schema_version": 1, "clips": [{"id": "attack2", "frames": [{"texture": null, "phase": "contact", "duration": "0.12", "foot_anchor": "alpha_bottom_center", "approval_state": "approved"}]}]}
	_write_json(malformed_path, malformed_doc)
	var malformed_bank: RefCounted = BANK_SCRIPT.new()
	_check(not malformed_bank.call("load_and_register", bad_blender, malformed_path), "string duration and legacy string anchor are rejected by schema v1")
	var alias_path := absolute_root.path_join("legacy-alias.json")
	_write_json(alias_path, {"schema_version": 1, "clips": [{"action": "attack2", "frames": []}]})
	var alias_bank: RefCounted = BANK_SCRIPT.new()
	_check(not alias_bank.call("load_and_register", bad_blender, alias_path), "legacy action alias is rejected; clip id is required")

func _load_actual_editor_export(user_args: PackedStringArray, argument_index: int) -> void:
	if argument_index + 1 >= user_args.size():
		push_error("player_animation_bank_smoke: missing --exported-manifest path")
		quit(1)
		return
	var manifest_path: String = user_args[argument_index + 1]
	var blender: PlayerPoseBlender = BLENDER_SCRIPT.new()
	root.add_child(blender)
	await process_frame
	var bank: RefCounted = BANK_SCRIPT.new()
	var loaded: bool = bank.call("load_and_register", blender, manifest_path)
	# The editor acceptance export deliberately marks a generated test contact image
	# approved. Parsing/schema validation must succeed, then the runtime pixel allowlist
	# must reject it without registering any exported art.
	var errors: Array = bank.get("last_errors")
	var passed := not loaded and not errors.is_empty() and blender.get_registered_frame_count("attack1", "contact") == 1
	if passed:
		print("player_animation_bank_smoke: actual editor export parsed and unsafe approval rejected")
		quit(0)
	else:
		push_error("player_animation_bank_smoke: actual editor export did not fail closed: " + str(errors))
		quit(1)

func _write_json(path: String, value: Dictionary) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(value))
	file.close()

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
