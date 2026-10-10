extends SceneTree
## Main-scene Window frames, limb deformation and moving support-foot checks.

const STEP := 1.0 / 60.0
var failures: Array[String] = []
var before := false

func _initialize() -> void:
	before = OS.get_cmdline_user_args().has("--before")
	call_deferred("_run")

func _run() -> void:
	_check(DisplayServer.get_name() == "Windows", "actual Windows renderer")
	root.size = Vector2i(1280, 720)
	var game = load("res://scenes/game/main.tscn").instantiate()
	var player = game.get_node("YSortActors/Player")
	if before:
		player.get_node("VisualAnimator").set_script(load("res://temp/high_baseline_visual.gd"))
	root.add_child(game)
	current_scene = game
	game.set_physics_process(false)
	game.set_process(false)
	for actor in game.get_node("YSortActors").get_children():
		actor.set_physics_process(false)
		if actor != player:
			actor.visible = false
	player.global_position = Vector2(900, 850)
	player.get_node("Camera2D").enabled = false
	var animator = player.get_node("VisualAnimator")
	animator.set_process(false)
	player.get_node("WalkMotion").set_process(false)
	player.get_node("VisualRoot/PoseBlender").set_process(false)
	await process_frame
	for effect_name in ["Skill1DashVisual","Skill2SpinVisual"]:
		var effect = player.get_node_or_null(effect_name)
		if effect != null:
			effect.set_process(false)
			effect.visible = false
	var sheet := Image.create(1700, 1410, false, Image.FORMAT_RGBA8)
	var rows := ["walk", "attack1", "attack2", "attack3", "skill1", "skill2"]
	for row in range(rows.size()):
		player.velocity = Vector2(280, 0) if row == 0 else Vector2.ZERO
		player.attack_phase = "idle"
		player.skill_phase = "idle"
		for column in range(5):
			if row in [1,2,3]:
				player.attack_stage = row
				player.attack_phase = ["startup", "active", "active", "combo_hold", "recovery"][column]
				var duration = [[0.075,0.085,0.10],[0.105,0.12,0.14],[0.105,0.12,0.14],[0.105,0.12,0.14],[0.20,0.22,0.28]][column][row - 1]
				player.attack_phase_remaining = duration * [0.5,0.85,0.15,0.0,0.5][column]
			elif row in [4,5]:
				player.skill_id = row - 3
				player.skill_phase = ["startup", "active", "active", "recovery", "recovery"][column]
				var durations = [0.16,0.12,0.12,0.42,0.42] if row == 4 else [0.22,0.18,0.18,0.55,0.55]
				player.skill_phase_remaining = durations[column] * [0.5,0.85,0.15,0.85,0.15][column]
			animator.call("_process", 0.19 if row == 0 else STEP)
			await process_frame
			await RenderingServer.frame_post_draw
			var frame := root.get_texture().get_image().get_region(Rect2i(240,180,680,470))
			frame.resize(340,235)
			sheet.blit_rect(frame, Rect2i(0,0,340,235), Vector2i(column*340,row*235))
	var suffix := "before" if before else "after"
	sheet.save_png("res://temp/high_body_%s.png" % suffix)
	if not before:
		# This half uses the live physics/input path, including root movement.
		player.attack_phase = "idle"
		player.attack_stage = 0
		player.skill_phase = "idle"
		player.skill_id = 0
		animator.set("_stride_phase", 0.0)
		animator.set_process(true)
		player.set_physics_process(true)
		Input.action_press("move_right")
		var last_side := -1
		var anchor := Vector2.ZERO
		var max_drift := 0.0
		var switches := 0
		var mesh_changed := false
		var pelvis_min := INF
		var pelvis_max := -INF
		var phases := {}
		for tick in range(65):
			await physics_frame
			await process_frame
			await RenderingServer.frame_post_draw
			var phase := float(animator.get("_stride_phase"))
			var side := 0 if phase < PI else 1
			phases[int(floor(phase / (PI * 0.5)))] = true
			var pelvis: Vector2 = animator.call("get_articulated_point_global", Vector2(670,620))
			pelvis_min = minf(pelvis_min,pelvis.y)
			pelvis_max = maxf(pelvis_max,pelvis.y)
			var point: Vector2 = animator.call("get_articulated_point_global", Vector2(395,1040) if side == 0 else Vector2(945,1090))
			if side != last_side:
				anchor = point
				last_side = side
				switches += 1
			else:
				max_drift = maxf(max_drift, point.distance_to(anchor))
			var art = player.get_node("VisualRoot/PlayerArt")
			var mesh = art.get_node_or_null("ArticulatedBody")
			mesh_changed = mesh_changed or (mesh != null and mesh.visible and mesh.polygon[600].distance_to(mesh.uv[600] - Vector2(627,627)) > 1.0)
		Input.action_release("move_right")
		_check(switches >= 3, "main gameplay left/right contacts alternate over live input frames")
		_check(max_drift < 1.0, "rendered shoe triangle stays at its world anchor while Player moves: %.4fpx" % max_drift)
		_check(phases.size() == 4 and pelvis_max - pelvis_min > 3.0, "all four gameplay gait phases include visible pelvis lift: %.2fpx" % (pelvis_max-pelvis_min))
		_check(mesh_changed, "visible body uses local limb deformation beyond whole-sprite rotation/scale")
		_check(not player.get_node("WalkMotion").is_candidate_active(), "unapproved PNG candidates never own normal gameplay")
	print("M6T_BODY_WINDOW|before=%s|fail=%d|capture=temp/high_body_%s.png" % [before, failures.size(), suffix])
	quit(0 if failures.is_empty() else 1)

func _check(value: bool, description: String) -> void:
	if value:
		print("PASS: " + description)
	else:
		failures.append(description)
		push_error("FAIL: " + description)
