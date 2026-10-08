extends SceneTree

const PLAYER_SCENE := "res://scenes/player/player.tscn"
const CAPTURE_PATH := "res://assets/art/review/player_motion_states_capture.png"
const CAPTURE_SIZE := Vector2i(1920, 1080)
const FLOOR_TOLERANCE := 0.08
const POSE_NAMES := ["idle", "walk", "crouch", "jump rise", "jump fall", "landing", "1 startup", "1 active", "2 active", "3 startup", "3 active", "3 recovery", "hit", "KO"]
const POSE_COUNT := 14

var failures: Array[String] = []
var players: Array[CharacterBody2D] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	if DisplayServer.get_name() == "headless" or OS.has_feature("dedicated_server"):
		push_error("player_visual_animator_smoke requires a Window Viewport")
		quit(1)
		return
	root.size = CAPTURE_SIZE
	var packed := load(PLAYER_SCENE) as PackedScene
	_check(packed != null, "Player scene loads with the independent VisualAnimator")
	if packed == null:
		_finish()
		return
	var canvas := Node2D.new()
	canvas.name = "MotionStateCapture"
	root.add_child(canvas)
	var capture_camera := Camera2D.new()
	capture_camera.position = CAPTURE_SIZE * 0.5
	capture_camera.enabled = true
	canvas.add_child(capture_camera)
	capture_camera.make_current()
	var captions := CanvasLayer.new()
	root.add_child(captions)
	for index in range(POSE_COUNT):
		var label := Label.new()
		label.text = POSE_NAMES[index]
		label.position = Vector2(150.0 + float(index % 4) * 480.0, 188.0 + float(index / 4) * 260.0)
		label.size = Vector2(180.0, 32.0)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.add_theme_font_size_override("font_size", 22)
		label.add_theme_color_override("font_color", Color(0.9, 0.92, 0.96, 1.0))
		captions.add_child(label)

	var poses: Array[CharacterBody2D] = []
	var animator_nodes: Array[Node] = []
	for index in range(POSE_COUNT):
		var player := packed.instantiate() as CharacterBody2D
		canvas.add_child(player)
		player.set_physics_process(false)
		player.position = Vector2(240.0 + float(index % 4) * 480.0, 180.0 + float(index / 4) * 260.0)
		(player.get_node("Camera2D") as Camera2D).queue_free()
		(player.get_node("GroundShadow") as Polygon2D).visible = false
		(player.get_node("VisualRoot/AttackFlash") as Polygon2D).visible = false
		poses.append(player)
		animator_nodes.append(player.get_node("VisualAnimator"))
		players.append(player)
	await process_frame
	for index in range(POSE_COUNT):
		_configure_pose(poses[index], index)
		var animator := animator_nodes[index]
		if index == 5:
			animator.set("_was_jumping", true)
		var pose_frames := 3 if index == 5 else 36
		for _frame in range(pose_frames):
			animator.call("_process", 1.0 / 60.0)
		_check(poses[index].position.y == 180.0 + float(index / 4) * 260.0, POSE_NAMES[index] + " leaves Player root position unchanged")
		_check(_foot_point(poses[index]).distance_to(_baseline_foot(poses[index])) <= FLOOR_TOLERANCE, POSE_NAMES[index] + " keeps the alpha foot anchor stable")
		if index > 0:
			var pose_art := poses[index].get_node("VisualRoot/PlayerArt") as Sprite2D
			var pose_is_distinct := absf(pose_art.rotation) > 0.008 or pose_art.scale.distance_to(Vector2(0.1489758, 0.1489758)) > 0.0015
			_check(pose_is_distinct, POSE_NAMES[index] + " differs visibly from the neutral still pose")

	var idle := poses[0]
	var idle_art := idle.get_node("VisualRoot/PlayerArt") as Sprite2D
	var idle_transform := idle_art.transform
	var idle_foot := _foot_point(idle)
	var idle_animator := animator_nodes[0]
	idle.set("attack_phase", "idle")
	idle.set("is_ko", false)
	idle.set("hitstun_remaining", 0.0)
	idle.set("hit_flash_remaining", 0.0)
	idle.velocity = Vector2.ZERO
	for _frame in range(90):
		idle_animator.call("_process", 1.0 / 60.0)
	_check(idle_art.transform.origin.distance_to(idle_transform.origin) < 1.5 and absf(idle_art.rotation) < 0.01 and idle_art.scale.distance_to(Vector2(0.1489758, 0.1489758)) < 0.002, "idle transform remains neutral and restrained")
	_check(_foot_point(idle).distance_to(idle_foot) <= FLOOR_TOLERANCE, "idle return retains the same foot anchor")

	var third_start := poses[9].get_node("VisualRoot/PlayerArt") as Sprite2D
	var third_active := poses[10].get_node("VisualRoot/PlayerArt") as Sprite2D
	var second_active := poses[8].get_node("VisualRoot/PlayerArt") as Sprite2D
	var stage_one_active := poses[7].get_node("VisualRoot/PlayerArt") as Sprite2D
	var authored_scale := Vector2(0.1489758, 0.1489758)
	_check(absf(third_active.rotation) > absf(second_active.rotation) + 0.04 and third_active.scale.y / authored_scale.y < second_active.scale.y / authored_scale.y - 0.025, "third combo active pose has clearly stronger rotation and compression than stage two")
	_check(absf(second_active.rotation) > absf(stage_one_active.rotation) + 0.04 and second_active.scale.x > stage_one_active.scale.x, "second combo strike reads stronger than the first")
	_check(third_start.scale.y > third_active.scale.y and absf(third_active.rotation) > absf(third_start.rotation), "third combo startup and active poses are distinct")
	var left_player := poses[10]
	var left_animator := animator_nodes[10]
	var right_player := packed.instantiate() as CharacterBody2D
	canvas.add_child(right_player)
	right_player.set_physics_process(false)
	(right_player.get_node("Camera2D") as Camera2D).queue_free()
	var right_animator := right_player.get_node("VisualAnimator")
	await process_frame
	left_player.get_node("VisualRoot").scale.x = -1.0
	right_player.get_node("VisualRoot").scale.x = 1.0
	left_player.set("attack_stage", 3)
	left_player.set("attack_phase", "active")
	right_player.set("attack_stage", 3)
	right_player.set("attack_phase", "active")
	for _frame in range(36):
		left_animator.call("_process", 1.0 / 60.0)
		right_animator.call("_process", 1.0 / 60.0)
	var left_rotation := (left_player.get_node("VisualRoot/PlayerArt") as Sprite2D).rotation
	var right_rotation := (right_player.get_node("VisualRoot/PlayerArt") as Sprite2D).rotation
	_check(left_rotation * right_rotation < 0.0 and absf(absf(left_rotation) - absf(right_rotation)) < 0.01, "left and right facing mirror the stage three strike")
	_check(_foot_point(left_player).distance_to(_baseline_foot(left_player)) <= FLOOR_TOLERANCE and _foot_point(right_player).distance_to(_baseline_foot(right_player)) <= FLOOR_TOLERANCE, "both mirrored poses keep the foot anchor stable")
	left_player.get_node("VisualRoot").scale.x = 1.0
	left_player.set("attack_phase", "idle")
	left_player.set("attack_stage", 0)
	left_player.velocity = Vector2.ZERO
	var recovery_foot := _foot_point(left_player)
	for _frame in range(90):
		left_animator.call("_process", 1.0 / 60.0)
	var recovered_art := left_player.get_node("VisualRoot/PlayerArt") as Sprite2D
	_check(absf(recovered_art.rotation) < 0.01 and recovered_art.scale.distance_to(authored_scale) < 0.002, "stage three recovery transitions smoothly back to neutral")
	_check(_foot_point(left_player).distance_to(recovery_foot) <= FLOOR_TOLERANCE, "recovery return keeps its original foot anchor")

	await process_frame
	await RenderingServer.frame_post_draw
	var rendered := root.get_texture().get_image()
	_check(rendered != null and not rendered.is_empty() and rendered.get_size() == CAPTURE_SIZE, "Window Viewport renders a 1920x1080 pose comparison")
	if rendered != null and not rendered.is_empty() and rendered.get_size() == CAPTURE_SIZE:
		var error := rendered.save_png(ProjectSettings.globalize_path(CAPTURE_PATH))
		_check(error == OK, "actual Window Viewport pose comparison PNG is saved")
		if error == OK:
			print("player-motion-capture: saved rendered state comparison to %s" % CAPTURE_PATH)
	_check(not FileAccess.get_file_as_string(PLAYER_SCENE).contains("SpriteFrames"), "approved still artwork is not represented as completed frame animation")
	canvas.queue_free()
	captions.queue_free()
	await process_frame
	_finish()

func _configure_pose(player: CharacterBody2D, index: int) -> void:
	player.velocity = Vector2.ZERO
	player.set("is_ko", false)
	player.set("is_sitting", false)
	player.set("is_jumping", false)
	player.set("jump_vertical_velocity", 0.0)
	player.set("attack_phase", "idle")
	player.set("attack_stage", 0)
	player.set("attack_phase_remaining", 0.0)
	player.set("hitstun_remaining", 0.0)
	player.set("hit_flash_remaining", 0.0)
	var visual_root := player.get_node("VisualRoot") as Node2D
	visual_root.scale = Vector2.ONE
	match index:
		1:
			player.velocity = Vector2(280.0, 0.0)
		2:
			player.set("is_sitting", true)
			visual_root.scale.y = 0.78
			visual_root.position.y = -18.0 + 0.22 * 15.0
		3:
			player.set("is_jumping", true)
			player.set("jump_vertical_velocity", -220.0)
		4:
			player.set("is_jumping", true)
			player.set("jump_vertical_velocity", 160.0)
		5:
			pass
		6:
			_set_attack(player, 1, "startup", 0.02)
		7:
			_set_attack(player, 1, "active", 0.05)
		8:
			_set_attack(player, 2, "active", 0.06)
		9:
			_set_attack(player, 3, "startup", 0.025)
		10:
			_set_attack(player, 3, "active", 0.07)
		11:
			_set_attack(player, 3, "recovery", 0.14)
		12:
			player.velocity = Vector2(-80.0, 0.0)
			player.set("hitstun_remaining", 0.2)
			player.set("hit_flash_remaining", 0.08)
		13:
			player.set("is_ko", true)

func _set_attack(player: CharacterBody2D, stage: int, phase: String, remaining: float) -> void:
	player.set("attack_stage", stage)
	player.set("attack_phase", phase)
	player.set("attack_phase_remaining", remaining)

func _baseline_foot(player: CharacterBody2D) -> Vector2:
	var sprite := player.get_node("VisualRoot/PlayerArt") as Sprite2D
	var bounds := sprite.texture.get_image().get_used_rect()
	var size := Vector2(sprite.texture.get_size())
	var local_foot := (Vector2(float(bounds.position.x) + float(bounds.size.x) * 0.5, float(bounds.end.y)) - size * 0.5) * Vector2(0.1489758, 0.1489758)
	return Vector2(0.0, -62.0) + local_foot

func _foot_point(player: CharacterBody2D) -> Vector2:
	var sprite := player.get_node("VisualRoot/PlayerArt") as Sprite2D
	var bounds := sprite.texture.get_image().get_used_rect()
	var size := Vector2(sprite.texture.get_size())
	var local_foot := (Vector2(float(bounds.position.x) + float(bounds.size.x) * 0.5, float(bounds.end.y)) - size * 0.5) * sprite.scale
	return sprite.position + local_foot.rotated(sprite.rotation)

func _check(condition: bool, description: String) -> void:
	if condition:
		print("PASS: " + description)
	else:
		failures.append(description)

func _finish() -> void:
	if failures.is_empty():
		print("player_visual_animator_smoke: all checks passed")
		quit(0)
		return
	for failure in failures:
		push_error("player_visual_animator_smoke: " + failure)
	push_error("player_visual_animator_smoke: %d check(s) failed" % failures.size())
	quit(1)
