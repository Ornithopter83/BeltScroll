extends SceneTree
## Window-rendered visual quality checks for the GRID 64 body skin.

const MESH_SCRIPT := preload("res://scripts/player/player_body_mesh.gd")
const TEXTURE := preload("res://assets/art/player/elven_fighter_reference_v8_clean_candidate_1254x1254.png")
const STEP_15 := 1.0 / 15.0
const STEP_60 := 1.0 / 60.0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	root.size = Vector2i(1280, 720)
	var sprite := Sprite2D.new()
	sprite.texture = TEXTURE
	sprite.scale = Vector2.ONE * 0.4469274
	sprite.position = Vector2(640, 390)
	root.add_child(sprite)
	var rig: RefCounted = MESH_SCRIPT.new()
	var sampled_15: Array[Vector2] = []
	var sampled_60: Array[Vector2] = []
	var probes := [Vector2(650,700), Vector2(395,1040), Vector2(945,1090), Vector2(720,410), Vector2(660,325), Vector2(430,250)]
	var gait_phases := {}
	var pelvis_min := INF
	var pelvis_max := -INF
	var arm_travel := 0.0
	var head_hair_travel := 0.0
	for frame in range(16):
		var t := float(frame) * STEP_15
		var stride := fposmod(t * TAU / 0.92, TAU)
		rig.apply(sprite, "walk", "", 0, 0.0, stride)
		gait_phases[int(floor(stride / (PI * 0.5)))] = true
		var pelvis_lift: float = rig.get_walk_pelvis_lift()
		pelvis_min = minf(pelvis_min, pelvis_lift)
		pelvis_max = maxf(pelvis_max, pelvis_lift)
		arm_travel = maxf(arm_travel, maxf(rig.sample_rendered_point(Vector2(1000,400)).distance_to(Vector2(1000,400)), rig.sample_rendered_point(Vector2(490,500)).distance_to(Vector2(490,500))))
		head_hair_travel = maxf(head_hair_travel, maxf(rig.sample_rendered_point(Vector2(700,260)).distance_to(Vector2(700,260)), rig.sample_rendered_point(Vector2(430,250)).distance_to(Vector2(430,250))))
		if frame == 6:
			for point in probes:
				sampled_15.append(rig.sample_rendered_point(point))
	for frame in range(61):
		var t := float(frame) * STEP_60
		rig.apply(sprite, "walk", "", 0, 0.0, fposmod(t * TAU / 0.92, TAU))
		if frame == 24:
			for point in probes:
				sampled_60.append(rig.sample_rendered_point(point))
	_check(sampled_15.size() == sampled_60.size(), "matched 15/60 fps pose samples collected")
	_check(gait_phases.size() == 4, "15 fps playback visits all four contact and passing phases")
	_check(pelvis_max - pelvis_min > 4.0 and arm_travel > 1.0 and head_hair_travel > 0.1, "pelvis, opposite arm swing and head/ponytail follow through the gait (pelvis %.2f, arm %.2f, head/hair %.2f source px)" % [pelvis_max - pelvis_min, arm_travel, head_hair_travel])
	var cadence_delta := 0.0
	for i in range(mini(sampled_15.size(), sampled_60.size())):
		cadence_delta = maxf(cadence_delta, sampled_15[i].distance_to(sampled_60[i]))
	_check(cadence_delta < 0.01, "walk pose is frame-rate invariant at 15/60 fps (%.4f source px)" % cadence_delta)
	var min_area := INF
	var max_edge := 0.0
	var worst_pose := "none"
	for stage in range(1, 4):
		for phase in ["startup", "active", "recovery"]:
			for progress in [0.0, 0.5, 1.0]:
				rig.apply(sprite, "attack%d" % stage, phase, stage, progress, 0.0)
				var polygon: PackedVector2Array = (sprite.get_node("ArticulatedBody") as Polygon2D).polygon
				var pose_min := INF
				var pose_edge := 0.0
				for y in range(64):
					for x in range(64):
						var a := y * 65 + x
						var ab := polygon[a + 1] - polygon[a]
						var ac := polygon[a + 66] - polygon[a]
						pose_min = minf(pose_min, ab.cross(ac))
						pose_edge = maxf(pose_edge, maxf(ab.length(), ac.length()))
				if pose_min < min_area or pose_edge > max_edge:
					worst_pose = "attack%d_%s_%.2f" % [stage, phase, progress]
				min_area = minf(min_area, pose_min)
				max_edge = maxf(max_edge, pose_edge)
	_check(min_area > 0.01, "attack 1-3 triangles preserve winding without mesh fold (%.3f min area; %s)" % [min_area, worst_pose])
	_check(max_edge < 45.0, "combat deformation has no one-cell spike (%.2f source px; %s)" % [max_edge, worst_pose])
	var skill_min_area := INF
	var skill_max_edge := 0.0
	var skill_worst := "none"
	for skill in range(1, 3):
		for phase in ["startup", "active", "recovery"]:
			for progress in [0.0, 0.5, 1.0]:
				rig.apply(sprite, "skill%d" % skill, phase, skill, progress, 0.0)
				var polygon: PackedVector2Array = (sprite.get_node("ArticulatedBody") as Polygon2D).polygon
				var pose_min := INF
				var pose_edge := 0.0
				for y in range(64):
					for x in range(64):
						var a := y * 65 + x
						var ab := polygon[a + 1] - polygon[a]
						var ac := polygon[a + 66] - polygon[a]
						pose_min = minf(pose_min, ab.cross(ac))
						pose_edge = maxf(pose_edge, maxf(ab.length(), ac.length()))
				if pose_min < skill_min_area or pose_edge > skill_max_edge:
					skill_worst = "skill%d_%s_%.2f" % [skill, phase, progress]
				skill_min_area = minf(skill_min_area, pose_min)
				skill_max_edge = maxf(skill_max_edge, pose_edge)
	_check(skill_min_area > 0.01 and skill_max_edge < 45.0, "Num4/5 limb skins stay unfolded and locally smooth (min %.3f, edge %.2f; %s)" % [skill_min_area, skill_max_edge, skill_worst])
	var live_mesh := sprite.get_node("ArticulatedBody") as Polygon2D
	var uv_error := 0.0
	for y in range(65):
		for x in range(65):
			var index := y * 65 + x
			var expected_uv := Vector2(x, y) * 1254.0 / 64.0 * Vector2(TEXTURE.get_size()) / 1254.0
			uv_error = maxf(uv_error, live_mesh.uv[index].distance_to(expected_uv))
	_check(uv_error < 0.001, "source UV grid stays continuous at every vertex (%.5f px max error)" % uv_error)
	# Exercise the mesh in the Window at the actual gameplay display scale.
	rig.apply(sprite, "walk", "", 0, 0.0, PI * 0.5)
	await process_frame
	_check(sprite.is_visible_in_tree() and sprite.scale.distance_to(Vector2.ONE * 0.4469274) < 0.001 and root.size == Vector2i(1280, 720), "GRID 64 body reaches Window rendering at 1280x720 and 0.447 gameplay scale")
	# API contracts: sampling remains in 1254px authored space, and planted shoe
	# telemetry stays near zero after each transition to the opposite support side.
	var sampled_contact: Vector2 = rig.sample_rendered_point(Vector2(395, 1040))
	var worst_support_residual := 0.0
	for stride in [PI * 0.5, PI * 1.5]:
		rig.apply(sprite, "walk", "", 0, 0.0, stride)
		worst_support_residual = maxf(worst_support_residual, rig.get_walk_support_residual())
	_check(sampled_contact != Vector2.ZERO and worst_support_residual < 1.0, "sampled contact and both support-foot getter contracts remain valid (%.4f px)" % worst_support_residual)
	# The old test held the sprite still and missed the sliding/elongated shoe.
	# Exercise real translation and a mirror change with both planted sides.
	var moving_residual := 0.0
	var calf_stretch := 0.0
	for direction in [1.0, -1.0]:
		sprite.scale.x = absf(sprite.scale.x) * direction
		for frame in range(102):
			sprite.position.x += direction * 280.0 / 60.0
			var stride := fposmod(float(frame) * 280.0 / 60.0 / 235.2 * TAU, TAU)
			rig.apply(sprite, "walk", "", 0, 0.0, stride)
			moving_residual = maxf(moving_residual, rig.get_walk_support_residual())
			var ankle := Vector2(395, 1040) if stride < PI else Vector2(945, 1090)
			var calf := Vector2(430, 970) if stride < PI else Vector2(930, 1010)
			calf_stretch = maxf(calf_stretch, rig.sample_rendered_point(ankle).distance_to(rig.sample_rendered_point(calf)) / ankle.distance_to(calf))
	_check(moving_residual < 0.02, "translated and mirrored support remains on its rendered triangle (%.5f px)" % moving_residual)
	_check(calf_stretch < 1.12, "plant correction preserves calf/boot length under movement (max %.4fx)" % calf_stretch)
	if failures.is_empty():
		print("M6V_BODY_QUALITY|fail=0|fps=15,60|display=1280x720@0.447|fold_min=%.3f|edge_max=%.2f" % [min_area, max_edge])
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		print("M6V_BODY_QUALITY|fail=%d" % failures.size())
		quit(1)

func _check(condition: bool, label: String) -> void:
	if condition:
		print("PASS: " + label)
	else:
		failures.append(label)
		push_error("FAIL: " + label)
