extends SceneTree
"""Window smoke for real gameplay input and rendered locomotion/combat handoffs."""

const GAME_SCENE := "res://scenes/game/main.tscn"
const PLAYER_PATH := "YSortActors/Player"
const MAX_FRAME_DISPLACEMENT := 30.0
const MAX_MESH_EDGE := 150.0

var _failures: Array[String] = []
var _walk_phases: Dictionary = {}
var _support_sides: Dictionary = {}
var _max_support_residual := 0.0
var _support_sample_count := 0
var _max_frame_displacement := 0.0
var _max_mesh_edge := 0.0
var _max_transparent_mesh_edge := 0.0
var _texture_images: Dictionary = {}
var _visible_uv_edges: Dictionary = {}
var _max_pelvis_lift := 0.0
var _previous_position := Vector2.ZERO
var _has_previous_position := false
var _sample_player: CharacterBody2D
var _sample_animator: Node
var _frame_rows := PackedStringArray(["render_frame,physics_frame,state,attack_phase,skill_phase,x,y,displacement,full_body_sources,gait_phase,support_side,support_residual_world_px,pelvis_lift_source_px"])
var _render_frame := 0
var _last_physics_frame := -1
var _max_physics_gap := 0
var _captured_states: Dictionary = {}

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	Engine.physics_ticks_per_second = 60
	Engine.max_fps = 60
	root.size = Vector2i(1280, 720)
	_check(DisplayServer.get_name() != "headless", "Window renderer is active")
	var packed := load(GAME_SCENE) as PackedScene
	_check(packed != null, "main gameplay scene loads")
	if packed == null:
		_finish()
		return
	var game := packed.instantiate()
	root.add_child(game)
	await _ticks(2)
	var player := game.get_node_or_null(PLAYER_PATH) as CharacterBody2D
	_check(player != null, "test runs the production Player in the main gameplay scene")
	if player == null:
		_finish()
		return
	for actor in game.get_node("YSortActors").get_children():
		if actor != player and actor is CharacterBody2D:
			(actor as CharacterBody2D).set_physics_process(false)
	var animator: Node = player.get_node("VisualAnimator")
	var mesh_script: RefCounted = animator.get("_body_mesh")
	_check(player.is_physics_processing(), "production Player physics remains enabled")
	_sample_player = player
	_sample_animator = animator
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://temp/m6u_high_motion"))
	RenderingServer.frame_post_draw.connect(_on_rendered_frame)

	# Actual movement input drives physics, stride phase, and the visible mesh.
	Input.action_press("move_right")
	await _ticks(3)
	await _ticks(150)
	await _ticks(2)
	_check(float(player.global_position.x) > 960.0, "right input moved the Player through production physics")
	_check(_walk_phases.size() == 4, "actual movement rendered all four gait phases: %s" % str(_walk_phases.keys()))
	_check(_support_sides.has("left") and _support_sides.has("right"), "actual gait alternated left and right support")
	_check(_support_sample_count > 0, "rendered support point samples were available during gait")
	_check(_max_support_residual <= 1.5, "rendered support foot residual stayed within 1.5 px (%.3f)" % _max_support_residual)
	_check(_max_pelvis_lift > 10.0, "passing phases lifted the actual pelvis mesh (%.2f px)" % _max_pelvis_lift)
	_check(_max_frame_displacement <= MAX_FRAME_DISPLACEMENT, "no frame-to-frame position jump exceeded %.1f px (%.2f)" % [MAX_FRAME_DISPLACEMENT, _max_frame_displacement])
	_check(_max_mesh_edge <= MAX_MESH_EDGE, "deformed mesh edges stayed continuous (max %.2f source px)" % _max_mesh_edge)
	_check_single_body(player, "walking")

	# Begin J from a real input press while moving, then tap J in each link hold.
	Input.action_press("move_right")
	Input.action_press("attack")
	await _ticks(2)
	Input.action_release("attack")
	await _ticks(2)
	_check(int(player.get("attack_stage")) == 1 and str(player.get("attack_phase")) != "idle", "J starts combo hit 1 from live input (phase=%s)" % str(player.get("attack_phase")))
	for stage in [1, 2, 3]:
		await _wait_for_attack_phase(player, "combo_hold" if stage < 3 else "recovery", 60)
		_check(int(player.get("attack_stage")) == stage, "combo stage %d owns the body" % stage)
		_check(str(player.get("attack_phase")) == ("combo_hold" if stage < 3 else "recovery"), "combo stage %d reaches its expected link/contact phase" % stage)
		_check(animator.call("get_animation_state").begins_with("attack%d_" % stage), "hit %d has no IDLE animation interruption" % stage)
		_check_single_body(player, "attack%d" % stage)
		if stage < 3:
			Input.action_press("attack")
			await _ticks(1)
			Input.action_release("attack")
			await _ticks(1)
	await _wait_for_attack_idle(player, 90)
	await _ticks(2)
	_check(animator.call("get_animation_state") == "walk", "held real movement resumes walking immediately after the combo")
	await _ticks(8)

	# Num4 and Num5 action mappings are the real skill_1 and skill_2 inputs.
	for skill_id in [1, 2]:
		Input.action_press("move_right")
		await _ticks(8)
		var action := "skill_%d" % skill_id
		Input.action_press(action)
		await _ticks(1)
		Input.action_release(action)
		_check(int(player.get("skill_id")) == skill_id and str(player.get("skill_phase")) != "idle", "Num%d input activates its production skill state" % (skill_id + 3))
		await _wait_for_skill_idle(player, 100)
		_check(animator.call("get_animation_state").begins_with("skill%d_" % skill_id) or animator.call("get_animation_state") in ["idle", "walk"], "Num%d skill handoff has no stray animation state" % (skill_id + 3))
		_check_single_body(player, "Num%d skill" % (skill_id + 3))
		_check_transition_continuity(player, animator)
		await _ticks(4)

	_check(mesh_script != null, "production body deformation helper is present")
	_check_transition_continuity(player, animator)
	await RenderingServer.frame_post_draw
	RenderingServer.frame_post_draw.disconnect(_on_rendered_frame)
	_check(_max_frame_displacement <= MAX_FRAME_DISPLACEMENT, "entire walk/combo/skill sequence stays within the unchanged 30px consecutive-frame bound (%.2f)" % _max_frame_displacement)
	_check(_max_mesh_edge <= MAX_MESH_EDGE, "entire sequence mesh remains within the unchanged edge bound (%.2f)" % _max_mesh_edge)
	# Window frames are continuous even when several physics ticks elapse between
	# draws. Record that gap; never describe this as every-physics-tick telemetry.
	_check(_max_support_residual <= 1.5, "entire sequence rendered support residual stays within 1.5px")
	for stage in [1, 2, 3]:
		for phase in ["startup", "active", "recovery"]:
			_check(_captured_states.has("attack%d_%s" % [stage, phase]), "continuous Window sequence includes J%d %s" % [stage, phase])
		if stage < 3:
			_check(_captured_states.has("attack%d_combo_hold" % stage), "continuous Window sequence includes J%d combo_hold" % stage)
	for skill_id in [1, 2]:
		for phase in ["startup", "active", "recovery"]:
			_check(_captured_states.has("skill%d_%s" % [skill_id, phase]), "continuous Window sequence includes Num%d %s" % [skill_id + 3, phase])
	for capture_key in _captured_states:
		var captured: Image = _captured_states[capture_key]
		_check(captured.save_png("res://temp/m6u_high_motion/%s.png" % capture_key) == OK, "rendered state screenshot is saved")
	var trace := FileAccess.open("res://temp/m6u_high_motion/frames.csv", FileAccess.WRITE)
	_check(trace != null, "continuous Window telemetry file opens")
	if trace != null:
		trace.store_string("\n".join(_frame_rows) + "\n")
	var frame := root.get_texture().get_image()
	_check(frame != null and not frame.is_empty(), "main gameplay renders a readable Window frame")
	print("M6U_ACTUAL_MOTION_SUMMARY|fail=%d|phases=%d|support_samples=%d|support_residual=%.3f|pelvis_lift=%.2f|frame_jump=%.2f|mesh_edge=%.2f|transparent_edge=%.2f|render_frames=%d|physics_gap=%d" % [_failures.size(), _walk_phases.size(), _support_sample_count, _max_support_residual, _max_pelvis_lift, _max_frame_displacement, _max_mesh_edge, _max_transparent_mesh_edge, _render_frame, _max_physics_gap])
	_finish()

func _on_rendered_frame() -> void:
	_capture_frame(_sample_player, _sample_animator)

func _capture_frame(player: CharacterBody2D, animator: Node) -> void:
	# Every frame_post_draw is sampled once, including input presses/releases and
	# startup/recovery waits. Manual spot checks must not advance this history.
	var physics_index := Engine.get_physics_frames()
	if _last_physics_frame >= 0:
		_max_physics_gap = maxi(_max_physics_gap, physics_index - _last_physics_frame)
	_last_physics_frame = physics_index
	_render_frame += 1
	var displacement := 0.0
	if _has_previous_position:
		displacement = player.global_position.distance_to(_previous_position)
		_max_frame_displacement = maxf(_max_frame_displacement, displacement)
	_previous_position = player.global_position
	_has_previous_position = true
	var visible := _visible_full_body_count(player)
	_check(visible == 1, "one full-body source is visible in each sampled Window frame (got %d)" % visible)
	var state := str(animator.call("get_animation_state"))
	var capture_key := state
	var gait_phase := ""
	var support_side := ""
	var support_residual := -1.0
	var pelvis_lift := -1.0
	if state == "walk":
		var sample: Dictionary = animator.call("get_walk_motion_sample")
		gait_phase = str(sample["phase"])
		support_side = str(sample["support_side"])
		support_residual = float(sample["support_residual"])
		pelvis_lift = float(sample["pelvis_lift"])
		_walk_phases[str(sample["phase"])] = true
		_support_sides[str(sample["support_side"])] = true
		var residual := float(sample["support_residual"])
		_check(residual >= 0.0, "walk state exposes an actual rendered support point")
		if residual >= 0.0:
			_support_sample_count += 1
			_max_support_residual = maxf(_max_support_residual, residual)
		_max_pelvis_lift = maxf(_max_pelvis_lift, float(sample["pelvis_lift"]))
		capture_key += "_" + str(sample["phase"])
	elif str(player.get("attack_phase")) != "idle":
		capture_key = "attack%d_%s" % [int(player.get("attack_stage")), str(player.get("attack_phase"))]
	elif str(player.get("skill_phase")) != "idle":
		capture_key = "skill%d_%s" % [int(player.get("skill_id")), str(player.get("skill_phase"))]
	_frame_rows.append("%d,%d,%s,%s,%s,%.3f,%.3f,%.3f,%d,%s,%s,%.6f,%.6f" % [_render_frame, physics_index, state, str(player.get("attack_phase")), str(player.get("skill_phase")), player.global_position.x, player.global_position.y, displacement, visible, gait_phase, support_side, support_residual, pelvis_lift])
	if not _captured_states.has(capture_key):
		_captured_states[capture_key] = root.get_texture().get_image()
	if str(player.get("attack_phase")) != "idle":
		_check(state.begins_with("attack%d_" % int(player.get("attack_stage"))), "no IDLE or unrelated pose intrudes during attack phases")
	elif str(player.get("skill_phase")) != "idle":
		_check(state.begins_with("skill%d_" % int(player.get("skill_id"))), "no IDLE or unrelated pose intrudes during skill phases")
	elif player.velocity.length() > 10.0 and not player.get("is_jumping"):
		_check(state == "walk", "actual movement does not fall through to IDLE (state=%s velocity=%s hitstun=%.3f)" % [state, str(player.velocity), float(player.get("hitstun_remaining"))])
	if state == "walk" or state.begins_with("attack") or state.begins_with("skill"):
		var sprite := _visible_body_sprite(player)
		var mesh := sprite.get_node_or_null("ArticulatedBody") as Polygon2D if sprite != null else null
		if mesh != null and mesh.visible:
			if mesh.polygon.size() == mesh.uv.size():
				for index in range(mesh.polygon.size()):
					_check(mesh.polygon[index].is_finite() and mesh.uv[index].is_finite(), "mesh vertex and UV remain finite")
				var width := 64
				for y in range(width + 1):
					for x in range(width):
						var a := y * (width + 1) + x
						_record_mesh_edge(mesh.polygon[a].distance_to(mesh.polygon[a + 1]), state, sprite, mesh.uv[a], mesh.uv[a + 1])
				for y in range(width):
					for x in range(width + 1):
						var a := y * (width + 1) + x
						var b := (y + 1) * (width + 1) + x
						_record_mesh_edge(mesh.polygon[a].distance_to(mesh.polygon[b]), state, sprite, mesh.uv[a], mesh.uv[b])

func _record_mesh_edge(length: float, state: String, sprite: Sprite2D, uv_a: Vector2, uv_b: Vector2) -> void:
	if length <= _max_mesh_edge and length <= _max_transparent_mesh_edge:
		return
	# Deformed transparent corners cannot tear visible artwork. Keep their maximum
	# explicitly in the report rather than conflating it with rendered body edges.
	if not _edge_has_visible_texel(sprite.texture, uv_a, uv_b):
		_max_transparent_mesh_edge = maxf(_max_transparent_mesh_edge, length)
		return
	if length > _max_mesh_edge:
		_max_mesh_edge = length
		if length > MAX_MESH_EDGE:
			print("M6U_MESH_BOUND|state=%s|edge=%.2f|texture=%s|size=%s" % [state, length, sprite.texture.resource_path, sprite.texture.get_size()])

func _edge_has_visible_texel(texture: Texture2D, uv_a: Vector2, uv_b: Vector2) -> bool:
	var key := texture.get_instance_id()
	if not _texture_images.has(key):
		_texture_images[key] = texture.get_image()
		_visible_uv_edges[key] = {}
	var edge := Vector4(uv_a.x, uv_a.y, uv_b.x, uv_b.y)
	var edge_cache: Dictionary = _visible_uv_edges[key]
	if edge_cache.has(edge):
		return bool(edge_cache[edge])
	var source: Image = _texture_images[key]
	# Check every source texel along the actual UV edge, with a one-texel halo
	# for bilinear filtering. Alpha elsewhere is not evidence this edge is drawn.
	var steps := maxi(1, int(ceil(uv_a.distance_to(uv_b))))
	for index in range(steps + 1):
		var uv := uv_a.lerp(uv_b, float(index) / steps)
		for offset in [Vector2i.ZERO, Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var texel: Vector2i = Vector2i(uv) + offset
			texel.x = clampi(texel.x, 0, source.get_width() - 1)
			texel.y = clampi(texel.y, 0, source.get_height() - 1)
			if source.get_pixelv(texel).a > 0.001:
				edge_cache[edge] = true
				return true
	edge_cache[edge] = false
	return false

func _visible_full_body_count(player: CharacterBody2D) -> int:
	var count := 0
	var art := player.get_node("VisualRoot/PlayerArt") as Sprite2D
	var sources: Array[Sprite2D] = [art]
	var walk := player.get_node_or_null("WalkMotion")
	if walk != null:
		sources.append(walk.call("get_candidate_sprite") as Sprite2D)
	for sprite_node in player.get_node("VisualRoot/PoseBlender").find_children("PoseSprite*", "Sprite2D", false, false):
		sources.append(sprite_node as Sprite2D)
	for sprite in sources:
		if sprite == null or sprite.texture == null:
			continue
		var mesh := sprite.get_node_or_null("ArticulatedBody") as Polygon2D
		var source: CanvasItem = mesh if mesh != null and mesh.visible else sprite
		var alpha := source.self_modulate.a
		var cursor: Node = source
		while cursor is CanvasItem:
			var item := cursor as CanvasItem
			if not item.visible:
				alpha = 0.0
				break
			alpha *= item.modulate.a
			cursor = cursor.get_parent()
		if alpha > 0.001:
			count += 1
	return count

func _visible_body_sprite(player: CharacterBody2D) -> Sprite2D:
	var art := player.get_node("VisualRoot/PlayerArt") as Sprite2D
	if art.visible:
		return art
	var pose_blender := player.get_node("VisualRoot/PoseBlender")
	if pose_blender.visible:
		return pose_blender.call("get_current_sprite") as Sprite2D
	return null

func _check_single_body(player: CharacterBody2D, label: String) -> void:
	_check(_visible_full_body_count(player) == 1, "%s does not duplicate the full-body silhouette" % label)

func _check_transition_continuity(player: CharacterBody2D, animator: Node) -> void:
	var state := str(animator.call("get_animation_state"))
	_check(state not in ["walk", "idle"] or player.velocity.length() <= 10.0 or state == "walk", "IDLE does not intrude during actual movement")

func _wait_for_attack_phase(player: CharacterBody2D, phase: String, limit: int) -> void:
	for _index in range(limit):
		await physics_frame
		await process_frame
		await RenderingServer.frame_post_draw
		if str(player.get("attack_phase")) == phase:
			return
	_check(false, "attack reached phase %s" % phase)

func _wait_for_attack_idle(player: CharacterBody2D, limit: int) -> void:
	for _index in range(limit):
		await physics_frame
		await process_frame
		await RenderingServer.frame_post_draw
		if str(player.get("attack_phase")) == "idle":
			return
	_check(false, "combo returns to idle phase")

func _wait_for_skill_idle(player: CharacterBody2D, limit: int) -> void:
	for _index in range(limit):
		await physics_frame
		await process_frame
		await RenderingServer.frame_post_draw
		if str(player.get("skill_phase")) == "idle":
			return
	_check(false, "skill completes all phases")

func _ticks(count: int) -> void:
	for _index in range(count):
		await physics_frame
		await process_frame
		await RenderingServer.frame_post_draw

func _check(condition: bool, description: String) -> void:
	if condition:
		return
	_failures.append(description)
	push_error("FAIL: " + description)

func _finish() -> void:
	Input.action_release("move_right")
	Input.action_release("attack")
	Input.action_release("skill_1")
	Input.action_release("skill_2")
	if _failures.is_empty():
		quit(0)
	else:
		quit(1)
