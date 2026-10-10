extends SceneTree
"""Window smoke for the one-full-body-source rendering contract."""

const PLAYER_SCENE := "res://scenes/player/player.tscn"

var _failures: Array[String] = []
var _player: CharacterBody2D
var _art: Sprite2D
var _blender: PlayerPoseBlender
var _walk_sprite: Sprite2D
var _animator: Node

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	_check(DisplayServer.get_name() != "headless", "Godot renders a Window")
	var packed := load(PLAYER_SCENE) as PackedScene
	_check(packed != null, "player scene loads")
	if packed == null:
		_finish()
		return
	_player = packed.instantiate() as CharacterBody2D
	_player.position = Vector2(640.0, 520.0)
	root.add_child(_player)
	_player.set_physics_process(false)
	var camera := _player.get_node_or_null("Camera2D")
	if camera != null:
		camera.queue_free()
	_art = _player.get_node("VisualRoot/PlayerArt") as Sprite2D
	_blender = _player.get_node("VisualRoot/PoseBlender") as PlayerPoseBlender
	_animator = _player.get_node("VisualAnimator")
	_walk_sprite = _player.get_node("WalkMotion").call("get_candidate_sprite") as Sprite2D
	await process_frame
	await RenderingServer.frame_post_draw
	_check(_art != null and _blender != null and _animator != null, "all full-body visual sources exist")
	if _art == null or _blender == null or _animator == null:
		_finish()
		return
	_check_one_body("initial idle")

	# Exercise the controller phase names directly so every transition is sampled
	# independently of input timing. Gameplay phase durations are left untouched.
	_player.velocity = Vector2(145.0, 0.0)
	for phase in ["startup", "active", "recovery", "combo_hold"]:
		_player.set("attack_stage", 1)
		_player.set("attack_phase", phase)
		_player.set("attack_phase_remaining", 0.06)
		await _capture("attack1_" + phase)
	_player.set("attack_stage", 0)
	_player.set("attack_phase", "idle")
	_player.set("attack_phase_remaining", 0.0)
	await _capture("walk_return")
	_player.velocity = Vector2.ZERO
	await _capture("idle_return")

	# The PoseBlender exposes one contour even while registrations and frame
	# scheduling change. Frame timing and the controller hitbox table stay intact.
	_check(_blender.get_displayed_textures().size() <= 1, "PoseBlender never exposes two full-body textures")
	var blender_source := FileAccess.get_file_as_string("res://scripts/player/player_pose_blender.gd")
	var animator_source := FileAccess.get_file_as_string("res://scripts/player/player_visual_animator.gd")
	var controller_source := FileAccess.get_file_as_string("res://scripts/player/player_controller.gd")
	_check(not animator_source.contains("POSE_SOURCE_BLEND_DURATION") and not animator_source.contains("art_modulate.a *= 1.0 - weight"), "source handoff does not fade or overlap silhouettes")
	_check(blender_source.contains("_sprites[target].visible = true") and blender_source.contains("_sprites[source].visible = false"), "pose selection swaps the single visible sprite atomically")
	_check(controller_source.contains("const ACTIVE := [0.105, 0.12, 0.14]"), "attack hitbox active windows remain unchanged")
	_finish()

func _capture(label: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	_check_one_body(label)

func _check_one_body(label: String) -> void:
	var visible_count := 0
	if _has_effective_body_alpha(_art):
		visible_count += 1
	for sprite in _blender.find_children("PoseSprite*", "Sprite2D", false, false):
		if _has_effective_body_alpha(sprite as Sprite2D):
			visible_count += 1
	if _has_effective_body_alpha(_walk_sprite):
		visible_count += 1
	_check(visible_count == 1, "%s renders exactly one full-body source (got %d)" % [label, visible_count])

func _has_effective_body_alpha(sprite: Sprite2D) -> bool:
	if sprite == null or sprite.texture == null:
		return false
	var alpha := 1.0
	var cursor: Node = sprite
	while cursor is CanvasItem:
		var item := cursor as CanvasItem
		if not item.visible:
			return false
		alpha *= item.modulate.a * item.self_modulate.a
		cursor = cursor.get_parent()
	return alpha > 0.001

func _check(condition: bool, message: String) -> void:
	if condition:
		print("PASS: " + message)
	else:
		_failures.append(message)
		push_error("m6q_visual_layer_exclusivity_window_smoke: " + message)

func _finish() -> void:
	if _failures.is_empty():
		print("m6q_visual_layer_exclusivity_window_smoke: PASS")
		quit(0)
	else:
		quit(1)
