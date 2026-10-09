extends SceneTree

const MAIN_SCENE := "res://scenes/game/main.tscn"
const CAPTURE_PATH := "res://assets/art/review/m6d_stage_progression.png"
const VIEW_SIZE := Vector2i(1920, 1080)
const SECTION_WIDTH := 1920.0

var failures: Array[String] = []
var captures: Array[Image] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	_check(DisplayServer.get_name() != "headless", "captures are rendered by a real Godot Window viewport")
	root.size = VIEW_SIZE
	var packed := load(MAIN_SCENE) as PackedScene
	var game := packed.instantiate() as Node2D
	root.add_child(game)
	current_scene = game
	await process_frame
	var player := game.get_node("YSortActors/Player") as CharacterBody2D
	var camera := player.get_node("Camera2D") as Camera2D
	var actors := game.get_node("YSortActors") as Node2D
	var boss := game.get_node("YSortActors/RuinsWardenBoss")
	var raiders := get_nodes_in_group("forest_raiders")
	_check(actors.y_sort_enabled, "YSort actor ordering remains enabled")
	_check(camera.limit_left == 0 and camera.limit_right == 5760 and camera.limit_top == 0 and camera.limit_bottom == 1080, "camera limits preserve the three tile continuous world")
	_check(raiders.size() == 3 and not bool(boss.get("combat_active")), "three encounter waves start with the boss locked")
	_check(game.get_node("StageDressing").get_child_count() >= 20, "all three sections receive authored scenic dressing")
	_check(int(player.get("max_health")) == 5 and int(raiders[0].get("max_health")) == 3, "player and raider editor overrides still apply")
	for actor in raiders:
		actor.set_physics_process(false)
		actor.velocity = Vector2.ZERO
		actor.get_node("AttackArea").monitoring = false
	boss.set_physics_process(false)
	player.set_physics_process(false)
	player.global_position = Vector2(1320.0, 780.0)
	await _settle_camera(camera)
	captures.append(await _capture_window_frame())
	_check(player.global_position.x > SECTION_WIDTH * 0.5, "first view uses the opening section of the continuous stage")
	player.global_position.x = SECTION_WIDTH + 120.0
	game.call("_update_raider_waves")
	_check(is_equal_approx(player.global_position.x, SECTION_WIDTH - 38.0), "the active encounter boundary still stops movement into a locked section")
	player.global_position = Vector2(1320.0, 780.0)

	# Raider knockouts are the existing progression gate. Advance that same state
	# machine so the actual rendered views correspond to sections two and three.
	for section in range(1, 3):
		raiders[section - 1].set("health", 0)
		game.call("_update_raider_waves")
		_check(int(game.get("_current_section")) == section, "raider knockout unlocks section %d" % (section + 1))
		_check(not bool(boss.get("combat_active")), "boss remains locked before the final raider is defeated")
		player.global_position = Vector2(float(section) * SECTION_WIDTH + 1320.0, 780.0)
		await _settle_camera(camera)
		captures.append(await _capture_window_frame())

	raiders[2].set("health", 0)
	game.call("_update_raider_waves")
	_check(bool(boss.get("combat_active")), "final raider knockout unlocks the boss")
	_check(captures.size() == 3 and captures[0].get_data() != captures[1].get_data() and captures[1].get_data() != captures[2].get_data(), "each section renders visibly distinct from the previous view")
	_write_triptych()
	var saved := Image.new()
	var load_error := saved.load(ProjectSettings.globalize_path(CAPTURE_PATH))
	_check(load_error == OK and saved.get_size() == Vector2i(VIEW_SIZE.x * 3, VIEW_SIZE.y), "comparison image contains three full resolution Window captures")
	_check(player.get("arena_bounds") == Rect2(Vector2(237, 722), Vector2(5286, 258)), "editor override and continuous player boundary remain in place")

	game.call("_restart_session")
	for _frame in range(4):
		await process_frame
	var restarted := current_scene as Node2D
	var restarted_boss := restarted.get_node_or_null("YSortActors/RuinsWardenBoss") if is_instance_valid(restarted) else null
	var restarted_player := restarted.get_node_or_null("YSortActors/Player") if is_instance_valid(restarted) else null
	_check(is_instance_valid(restarted) and restarted != game, "restart reloads the authored main scene")
	_check(restarted_boss != null and not bool(restarted_boss.get("combat_active")), "restart resets progression and relocks the boss")
	_check(restarted_player != null and int(restarted_player.get("max_health")) == 5 and is_equal_approx((restarted_player as Node2D).global_position.x, 960.0), "restart reapplies editor overrides and authored spawn")
	_finish()

func _settle_camera(camera: Camera2D) -> void:
	var previous := camera.get_screen_center_position()
	var settled := 0
	for _frame in range(120):
		await process_frame
		var current := camera.get_screen_center_position()
		if current.distance_to(previous) < 0.5:
			settled += 1
			if settled >= 3:
				return
		else:
			settled = 0
		previous = current
	_check(false, "camera smoothing settles after moving to a section")

func _capture_window_frame() -> Image:
	# get_image() reads the frame rendered to the running Window viewport.
	await process_frame
	return get_root().get_texture().get_image()

func _write_triptych() -> void:
	if captures.size() != 3:
		return
	var triptych := Image.create(VIEW_SIZE.x * 3, VIEW_SIZE.y, false, Image.FORMAT_RGBA8)
	for index in range(captures.size()):
		triptych.blit_rect(captures[index], Rect2i(Vector2i.ZERO, VIEW_SIZE), Vector2i(index * VIEW_SIZE.x, 0))
	var error := triptych.save_png(ProjectSettings.globalize_path(CAPTURE_PATH))
	_check(error == OK, "three rendered Window frames are saved to the review image")

func _check(condition: bool, description: String) -> void:
	if condition:
		print("PASS: " + description)
	else:
		failures.append(description)

func _finish() -> void:
	if failures.is_empty():
		print("m6d_stage_progression_window_smoke: all checks passed; captures=%d" % captures.size())
		quit(0)
		return
	for failure in failures:
		push_error("m6d_stage_progression_window_smoke: " + failure)
	push_error("m6d_stage_progression_window_smoke: %d check(s) failed" % failures.size())
	quit(1)
