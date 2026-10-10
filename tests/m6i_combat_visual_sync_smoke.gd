extends SceneTree
"""Window smoke for combat-state priority, live hit windows, and motion labels."""

const PLAYER_SCENE := preload("res://scenes/player/player.tscn")
const ATTACK_ACTIVE := [0.105, 0.12, 0.14]
const SKILL_ACTIVE := [0.12, 0.18]

var failures: Array[String] = []
var sample_rows: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	if DisplayServer.get_name() == "headless" or OS.has_feature("dedicated_server"):
		push_error("m6i_combat_visual_sync_smoke requires an actual Window Viewport")
		quit(1)
		return
	root.size = Vector2i(960, 540)
	var player := PLAYER_SCENE.instantiate() as CharacterBody2D
	root.add_child(player)
	player.set_physics_process(false)
	await process_frame
	var animator: Node = player.get_node("VisualAnimator")
	var blender: PlayerPoseBlender = player.get_node("VisualRoot/PoseBlender") as PlayerPoseBlender
	var art: Sprite2D = player.get_node("VisualRoot/PlayerArt") as Sprite2D

	# Check all three real active-window durations against the visual phase clock.
	for stage in range(1, 4):
		player.set("attack_stage", stage)
		player.set("attack_phase", "active")
		player.set("attack_phase_remaining", ATTACK_ACTIVE[stage - 1])
		player.set("skill_phase", "idle")
		player.set("hitstun_remaining", 0.0)
		player.set("hit_flash_remaining", 0.0)
		player.get_node("Hitboxes/Hitbox%d" % stage).monitoring = true
		animator.call("_process", 0.0)
		var state := str(animator.call("get_animation_state"))
		var progress := float(animator.call("get_state_phase_progress"))
		_check(state == "attack%d_contact" % stage, "Attack %d contact pose follows its live active window" % stage)
		_check(absf(progress) < 0.001, "Attack %d visual phase begins at the controller's active-window boundary" % stage)
		_check(player.get_node("Hitboxes/Hitbox%d" % stage).monitoring, "Attack %d hitbox is active during the sampled contact pose" % stage)
		_sample("attack%d_active_start" % stage, player, animator, blender)
		player.get_node("Hitboxes/Hitbox%d" % stage).monitoring = false
		await process_frame

	# When raw fields overlap during cancellation, displayed poses follow the same
	# resolved priority as the gameplay state: KO > hit > skill > basic attack.
	player.set("attack_stage", 3)
	player.set("attack_phase", "active")
	player.set("attack_phase_remaining", ATTACK_ACTIVE[2] * 0.5)
	player.set("skill_id", 2)
	player.set("skill_phase", "active")
	player.set("skill_phase_remaining", SKILL_ACTIVE[1] * 0.5)
	player.set("hitstun_remaining", 0.0)
	player.set("hit_flash_remaining", 0.08)
	animator.call("_process", 0.0)
	_check(animator.call("get_animation_state") == "hit", "hit flash takes priority over stale skill and attack phase fields")
	_check(not blender.visible and art.visible, "interrupted attack art is hidden during hit flash")
	_sample("hit_flash_over_stale_actions", player, animator, blender)
	player.set("hit_flash_remaining", 0.0)
	player.set("hitstun_remaining", 0.18)
	animator.call("_process", 0.0)
	_check(animator.call("get_animation_state") == "hit", "hitstun retains hit priority after hit flash ends")
	_check(not blender.visible and art.visible, "attack pose does not reappear during hitstun")
	_sample("hitstun", player, animator, blender)

	player.set("hitstun_remaining", 0.0)
	player.set("attack_phase", "idle")
	player.set("attack_stage", 0)
	for skill_id in range(1, 3):
		player.set("skill_id", skill_id)
		player.set("skill_phase", "active")
		player.set("skill_phase_remaining", SKILL_ACTIVE[skill_id - 1])
		var skill_hitbox := player.get_node("Hitboxes/Skill%dHitbox" % skill_id) as Area2D
		skill_hitbox.monitoring = true
		animator.call("_process", 0.0)
		var skill_state := str(animator.call("get_animation_state"))
		_check(skill_state == "skill%d_contact" % skill_id, "Num%d active phase resolves to its timed skill state" % (skill_id + 3))
		_check(animator.call("is_current_pose_temporary"), "Num%d remains explicitly procedural without approved animation art" % (skill_id + 3))
		_check(absf(float(animator.call("get_state_phase_progress"))) < 0.001 and skill_hitbox.monitoring, "Num%d contact starts at the active hitbox boundary" % (skill_id + 3))
		_sample("num%d_active" % (skill_id + 3), player, animator, blender)
		skill_hitbox.monitoring = false
		await process_frame
	# Use the controller's hit receiver to verify interruption clears the active
	# skill, its hitbox, and its procedural pose in the real cancellation path.
	player.receive_hit({"damage": 1, "direction": Vector2.LEFT, "knockback": 100.0, "hit_stun": 0.2, "attack_stage": 2})
	animator.call("_process", 0.0)
	_check(player.get("skill_phase") == "idle" and player.get("skill_id") == 0, "real incoming hit cancels the active Num5 skill")
	_check(not (player.get_node("Hitboxes/Skill2Hitbox") as Area2D).monitoring, "skill interruption disables the Num5 active hitbox")
	_check(animator.call("get_animation_state") == "hit" and not blender.visible and art.visible, "interrupted skill effects and pose do not survive the hit frame")
	_sample("num5_interrupted_by_hit", player, animator, blender)
	player.set("hitstun_remaining", 0.0)
	player.set("hit_flash_remaining", 0.0)

	# The contact drawing is an approved keypose, while its added transform steps
	# remain explicitly temporary and are never reported as approved frames.
	player.set("skill_id", 0)
	player.set("attack_stage", 1)
	player.set("attack_phase", "active")
	player.set("attack_phase_remaining", ATTACK_ACTIVE[0] * 0.5)
	animator.call("_process", 0.0)
	var frame_status := str(animator.call("get_state_frame_status"))
	_check(frame_status.contains("temporary procedural transform") and not frame_status.begins_with("approved frame"), "procedural contact motion is not represented as an approved frame sequence")
	_sample("attack1_contact_midpoint", player, animator, blender)

	player.set("attack_phase", "idle")
	player.set("attack_stage", 0)
	player.velocity = Vector2(180.0, 0.0)
	player.set("facing_direction", Vector2.RIGHT)
	player.get_node("VisualRoot").scale.x = 1.0
	animator.call("_process", 1.0 / 60.0)
	player.set("facing_direction", Vector2.LEFT)
	player.get_node("VisualRoot").scale.x = -1.0 # Mirrors the controller's immediate input-facing update.
	animator.call("_process", 1.0 / 60.0)
	_check(player.get_node("VisualRoot").scale.x > 0.0 and animator.call("is_turning"), "left-right change holds the old mirror through turn windup instead of popping")
	_sample("turn_windup_left", player, animator, blender)
	for _frame in range(5):
		animator.call("_process", 1.0 / 60.0)
	_check(player.get_node("VisualRoot").scale.x < 0.0, "facing mirror changes at the authored turn compression boundary")
	_sample("turn_flip_left", player, animator, blender)

	player.set("health", 1)
	player.receive_hit({"damage": 1, "direction": Vector2.LEFT, "knockback": 100.0, "hit_stun": 0.2, "attack_stage": 3})
	animator.call("_process", 0.0)
	_check(animator.call("get_animation_state") == "ko" and player.get("is_ko"), "lethal hit enters final-down over every combat pose")
	animator.call("_update_animation_clock", "ko", 1.10)
	_check(animator.call("is_final_down_settled"), "final-down settles on its terminal state")
	_sample("final_down_settled", player, animator, blender)
	await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	_check(image != null and not image.is_empty() and image.get_size() == Vector2i(960, 540), "sample frame comes from the actual Window Viewport")
	for row in sample_rows:
		print("m6i-window-sample: " + row)
	_finish()

func _sample(label: String, player: CharacterBody2D, animator: Node, blender: PlayerPoseBlender) -> void:
	var hitbox_state := {}
	for hitbox_name in ["Hitbox1", "Hitbox2", "Hitbox3", "Skill1Hitbox", "Skill2Hitbox"]:
		var hitbox := player.get_node("Hitboxes/" + hitbox_name) as Area2D
		hitbox_state[hitbox_name] = hitbox.monitoring
	var row := {
		"window_frame": Engine.get_process_frames(),
		"sample": label,
		"state": animator.call("get_animation_state"),
		"attack_phase": player.get("attack_phase"),
		"attack_remaining_s": player.get("attack_phase_remaining"),
		"attack_phase_progress": animator.call("get_state_phase_progress") if str(animator.call("get_animation_state")).begins_with("attack") else null,
		"hitboxes_monitoring": hitbox_state,
		"skill_phase": player.get("skill_phase"),
		"skill_remaining_s": player.get("skill_phase_remaining"),
		"hitstun_s": player.get("hitstun_remaining"),
		"hit_flash_s": player.get("hit_flash_remaining"),
		"pose_key": blender.get_current_pose_key() if blender.visible else "PlayerArt",
		"frame_status": animator.call("get_state_frame_status"),
	}
	sample_rows.append(JSON.stringify(row))

func _check(condition: bool, description: String) -> void:
	if condition:
		print("PASS: " + description)
	else:
		failures.append(description)

func _finish() -> void:
	if failures.is_empty():
		print("m6i_combat_visual_sync_smoke: Window states and combat windows stayed synchronized")
		quit(0)
		return
	for failure in failures:
		push_error("m6i_combat_visual_sync_smoke: " + failure)
	quit(1)
