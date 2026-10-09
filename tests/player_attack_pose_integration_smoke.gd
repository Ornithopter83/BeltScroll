extends SceneTree

const PLAYER_SCENE := "res://scenes/player/player.tscn"
const SAFE_PATH := "res://assets/art/player/elven_fighter_reference_v8_clean_candidate_1254x1254.png"
const ATTACK1_PATH := "res://assets/art/player/elven_fighter_attack1_reference_v1_contour_candidate_1254x1254.png"
const ATTACK2_PATH := "res://assets/art/player/elven_fighter_attack2_reference_v4_ink_final_candidate_1254x1254.png"
const ATTACK3_PATH := "res://assets/art/player/elven_fighter_attack3_reference_v2_contour_candidate_1254x1254.png"
const CAPTURE_SIZE := Vector2i(1920, 1080)
const BASE_SCALE := Vector2(0.1489758, 0.1489758)

var failures: Array[String] = []
var players: Array[CharacterBody2D] = []
var animators: Array[Node] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	if DisplayServer.get_name() == "headless" or OS.has_feature("dedicated_server"):
		push_error("player_attack_pose_integration_smoke requires a Window Viewport")
		quit(1)
		return
	root.size = CAPTURE_SIZE
	var packed := load(PLAYER_SCENE) as PackedScene
	_check(packed != null, "integrated Player scene loads")
	if packed == null:
		_finish()
		return
	var canvas := Node2D.new()
	canvas.name = "PlayerAttackPoseComparison"
	root.add_child(canvas)
	var camera := Camera2D.new()
	camera.position = CAPTURE_SIZE * 0.5
	camera.zoom = Vector2(1.2, 1.2)
	canvas.add_child(camera)
	camera.make_current()
	var backdrop := Polygon2D.new()
	backdrop.polygon = PackedVector2Array([Vector2.ZERO, Vector2(CAPTURE_SIZE.x, 0), Vector2(CAPTURE_SIZE), Vector2(0, CAPTURE_SIZE.y)])
	backdrop.color = Color("#18232a")
	canvas.add_child(backdrop)
	var title := _label("APPROVED CONTACT KEYPOSES  |  SHARED STARTUP / ACTIVE / RECOVERY CROSSFADE", Vector2(180, 150), 24)
	canvas.add_child(title)
	var names := ["ATTACK 1  ·  APPROVED CONTOUR", "ATTACK 2  ·  V4 INK FINAL", "ATTACK 3  ·  APPROVED CONTOUR"]
	for index in range(3):
		var player := packed.instantiate() as CharacterBody2D
		canvas.add_child(player)
		player.set_physics_process(false)
		player.position = Vector2(350.0 + float(index) * 610.0, 545.0)
		(player.get_node("Camera2D") as Camera2D).queue_free()
		(player.get_node("GroundShadow") as Polygon2D).visible = false
		(player.get_node("VisualRoot/AttackFlash") as Polygon2D).visible = false
		players.append(player)
		animators.append(player.get_node("VisualAnimator"))
		var name_label := _label(names[index], Vector2(105.0 + float(index) * 610.0, 800.0), 21)
		name_label.size.x = 500.0
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		canvas.add_child(name_label)
	await process_frame
	for index in range(3):
		var stage := index + 1
		_configure_attack(players[index], stage, "active")
		animators[index].call("_process", 1.0 / 60.0)
	var first_blender := _blender(players[0])
	var second_blender := _blender(players[1])
	var third_blender := _blender(players[2])
	_check(first_blender.visible and _texture_for(first_blender, "attack1_contact") == load(ATTACK1_PATH), "stage one active selects only its approved contour texture")
	_check(players[0].get_node("VisualRoot/PlayerArt").visible == false, "PlayerArt is hidden while the contour blender renders")
	_check(second_blender.visible and _texture_for(second_blender, "attack2_contact") == load(ATTACK2_PATH), "stage two active selects only its approved v4 ink final texture")
	_check(players[1].get_node("VisualRoot/PlayerArt").visible == false, "PlayerArt is hidden while the approved stage two blender renders")
	_check(third_blender.visible and _texture_for(third_blender, "attack3_contact") == load(ATTACK3_PATH), "stage three active selects only its approved contour texture")
	_check(first_blender.get_displayed_textures().size() <= 2 and second_blender.get_displayed_textures().size() <= 2 and third_blender.get_displayed_textures().size() <= 2, "integrated pose transitions render at most two blender layers")
	_check(_approved_pose_bounds(first_blender) and _approved_pose_bounds(second_blender) and _approved_pose_bounds(third_blender), "approved poses retain the common foot anchor and approximately 192 screen-pixel height")

	# Phase selection: startup and recovery resolve to v8; contact resolves to the approved contour.
	_configure_attack(players[0], 1, "startup")
	animators[0].call("_process", 1.0 / 60.0)
	_check(_texture_for(first_blender, "idle") == load(SAFE_PATH), "stage one startup uses the v8 clean still")
	_configure_attack(players[0], 1, "recovery")
	animators[0].call("_process", 1.0 / 60.0)
	_check(_texture_for(first_blender, "idle") == load(SAFE_PATH), "stage one recovery returns to the v8 clean still")
	_configure_attack(players[2], 3, "startup")
	animators[2].call("_process", 1.0 / 60.0)
	_check(_texture_for(third_blender, "idle") == load(SAFE_PATH), "stage three startup uses the v8 clean still")
	_configure_attack(players[2], 3, "recovery")
	animators[2].call("_process", 1.0 / 60.0)
	_check(_texture_for(third_blender, "idle") == load(SAFE_PATH), "stage three recovery returns to the v8 clean still")
	_configure_attack(players[1], 2, "startup")
	animators[1].call("_process", 1.0 / 60.0)
	_check(_texture_for(second_blender, "idle") == load(SAFE_PATH), "stage two startup uses the v8 clean still through the shared transition")
	_configure_attack(players[1], 2, "recovery")
	animators[1].call("_process", 1.0 / 60.0)
	_check(_texture_for(second_blender, "idle") == load(SAFE_PATH), "stage two recovery returns to the v8 clean still through the shared transition")

	# Verify a halfway fade is interrupted cleanly, then settles to the newest request.
	first_blender.set_pose("attack1", "contact")
	first_blender._process(0.02)
	_check(first_blender.get_displayed_textures().size() == 2, "contact transition exposes only the two expected sprites")
	first_blender.interrupt_to_idle()
	_check(first_blender.get_current_pose_key() == "idle" and first_blender.get_displayed_textures().size() == 1, "interrupt discards the partial contour transition immediately")
	_configure_attack(players[0], 1, "active")
	animators[0].call("_process", 1.0 / 60.0)
	first_blender._process(0.06)
	first_blender.set_pose("attack1", "recovery")
	first_blender._process(0.06)
	_check(_texture_for(first_blender, "idle") == load(SAFE_PATH), "recovery after interruption settles back to v8 clean")
	players[0].set("hitstun_remaining", 0.1)
	animators[0].call("_process", 1.0 / 60.0)
	_check(not first_blender.visible and players[0].get_node("VisualRoot/PlayerArt").visible, "hitstun interrupts the blender and restores PlayerArt without double rendering")
	players[0].set("hitstun_remaining", 0.0)
	_configure_attack(players[0], 1, "active")
	players[0].set("facing_direction", Vector2.LEFT)
	animators[0].call("_process", 1.0 / 60.0)
	var first_contact_sprite := first_blender.get_child(0) as Sprite2D
	_check(players[0].get_node("VisualRoot").scale.x < 0.0 and first_contact_sprite != null and not first_contact_sprite.flip_h, "left-facing approved pose inherits exactly one visual-root mirror from the player facing state")

	# Leave the on-screen comparison in the requested three-panel state, then capture the real Window Viewport.
	_configure_attack(players[0], 1, "active")
	_configure_attack(players[1], 2, "active")
	_configure_attack(players[2], 3, "active")
	players[0].set("facing_direction", Vector2.RIGHT)
	players[0].get_node("VisualRoot").scale.x = 1.0
	for index in range(3):
		animators[index].call("_process", 1.0 / 60.0)
	for _frame in range(3):
		await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	_check(image != null and not image.is_empty() and image.get_size() == CAPTURE_SIZE, "Window Viewport returns a real 1920x1080 comparison frame")
	if image != null and not image.is_empty() and image.get_size() == CAPTURE_SIZE:
		_check(_has_visible_variation(image), "rendered comparison remains readable at gameplay scale")
		var capture_dir := OS.get_environment("TEMP").path_join("BeltScrollSmokeCaptures")
		DirAccess.make_dir_recursive_absolute(capture_dir)
		var capture_path := capture_dir.path_join("player_attack_pose_%d.png" % OS.get_process_id())
		var error := image.save_png(capture_path)
		_check(error == OK, "actual Window Viewport comparison PNG is saved")
		if error == OK:
			print("player-attack-pose-capture: saved real Window Viewport comparison to %s" % capture_path)
	canvas.queue_free()
	await process_frame
	_finish()

func _configure_attack(player: CharacterBody2D, stage: int, phase: String) -> void:
	player.velocity = Vector2.ZERO
	player.set("attack_stage", stage)
	player.set("attack_phase", phase)
	player.set("attack_phase_remaining", 0.05)
	player.set("is_ko", false)
	player.set("is_sitting", false)
	player.set("is_jumping", false)
	player.set("hitstun_remaining", 0.0)
	player.set("hit_flash_remaining", 0.0)

func _blender(player: CharacterBody2D) -> PlayerPoseBlender:
	return player.get_node("VisualRoot/PoseBlender") as PlayerPoseBlender

func _texture_for(blender: PlayerPoseBlender, key: String) -> Texture2D:
	if blender.get_current_pose_key() != key:
		print("pose debug: expected=%s current=%s" % [key, blender.get_current_pose_key()])
		return null
	var expected_path := SAFE_PATH
	if key == "attack1_contact":
		expected_path = ATTACK1_PATH
	elif key == "attack2_contact":
		expected_path = ATTACK2_PATH
	elif key == "attack3_contact":
		expected_path = ATTACK3_PATH
	for child in blender.get_children():
		if child is Sprite2D and child.visible and (child as Sprite2D).texture != null \
		and (child as Sprite2D).texture.resource_path == expected_path:
			return (child as Sprite2D).texture
	return null

func _approved_pose_bounds(blender: PlayerPoseBlender) -> bool:
	var key := blender.get_current_pose_key()
	var texture := _texture_for(blender, key)
	if texture == null:
		return false
	var bounds := texture.get_image().get_used_rect()
	var height := float(bounds.size.y) * BASE_SCALE.y * 1.2
	var support_candidate := Vector2(-1.0, -1.0)
	match key:
		"attack1_contact":
			support_candidate = Vector2(0.85, 0.91)
		"attack2_contact":
			support_candidate = Vector2(0.86, 0.91)
		"attack3_contact":
			support_candidate = Vector2(0.80, 0.91)
	var sprite: Sprite2D
	for child in blender.get_children():
		if child is Sprite2D and child.visible and (child as Sprite2D).texture == texture:
			sprite = child as Sprite2D
			break
	if sprite == null or support_candidate.x < 0.0:
		return false
	var foot_x := support_candidate.x * float(texture.get_width())
	if sprite.flip_h:
		foot_x = float(texture.get_width()) - foot_x
	var foot_y := support_candidate.y * float(texture.get_height())
	var foot_from_center := (Vector2(foot_x, foot_y) - Vector2(texture.get_size()) * 0.5) * sprite.scale
	return absf(height - 192.0) <= 2.0 and (sprite.position + foot_from_center).distance_to(blender.common_combat_anchor) < 0.1

func _label(value: String, at: Vector2, font_size: int) -> Label:
	var label := Label.new()
	label.text = value
	label.position = at
	label.size = Vector2(500.0, 42.0)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", Color("#eef3f4"))
	return label

func _has_visible_variation(image: Image) -> bool:
	var count := 0
	var reference := Vector3(Color("#18232a").r, Color("#18232a").g, Color("#18232a").b)
	for center_x in [350, 960, 1570]:
		for y in range(390, 590, 8):
			for x in range(center_x - 105, center_x + 105, 8):
				var color := image.get_pixel(x, y)
				if Vector3(color.r, color.g, color.b).distance_squared_to(reference) > 0.02:
					count += 1
	return count >= 50

func _check(condition: bool, description: String) -> void:
	if condition:
		print("PASS: " + description)
	else:
		failures.append(description)

func _finish() -> void:
	if failures.is_empty():
		print("player_attack_pose_integration_smoke: all checks passed")
		quit(0)
		return
	for failure in failures:
		push_error("player_attack_pose_integration_smoke: " + failure)
	push_error("player_attack_pose_integration_smoke: %d check(s) failed" % failures.size())
	quit(1)
