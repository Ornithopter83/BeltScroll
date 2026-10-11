extends RefCounted
## Deforms the existing approved drawing locally. No candidate art is registered.
## The same mapping supplies the glove point and the rendered texture vertices.

const GRID := 64
var _meshes: Dictionary = {}
var _sprite: Sprite2D
var _state := "idle"
var _phase := "idle"
var _stage := 0
var _progress := 0.0
var _stride := 0.0
var _support_side := -1
var _support_global := Vector2.ZERO
var _support_offset := Vector2.ZERO
var _support_facing := 0.0

func apply(sprite: Sprite2D, state: String, phase: String, stage: int, progress: float, stride: float) -> void:
	_sprite = sprite
	_state = state
	_phase = phase
	_stage = stage
	_progress = progress
	_stride = stride
	if sprite != null and state == "walk":
		var side := 0 if stride < PI else 1
		var foot := Vector2(395, 1040) if side == 0 else Vector2(945, 1090)
		var size := Vector2(sprite.texture.get_size())
		var facing := signf(sprite.global_transform.x.x)
		if side != _support_side or facing != _support_facing:
			_support_global = sprite.to_global((foot - Vector2(627, 627)) * size / 1254.0)
			_support_side = side
			_support_facing = facing
		_support_offset = sprite.to_local(_support_global) * 1254.0 / size + Vector2(627, 627) - foot
		# Solve against the same triangle interpolation used for rendering. A fade
		# that only reaches 1 below the left shoe leaves a visible sliding residual.
		var desired := foot + _support_offset
		_support_offset = Vector2.ZERO
		var unplanted := _sample_walk_mapping(foot)
		_support_offset = Vector2.ONE
		var influence := _sample_walk_mapping(foot) - unplanted
		_support_offset = (desired - unplanted) / influence
	else:
		_support_side = -1
		_support_offset = Vector2.ZERO
	for key in _meshes:
		var old_sprite := instance_from_id(key) as Sprite2D
		if old_sprite != null:
			old_sprite.self_modulate.a = 1.0
			(_meshes[key] as Polygon2D).visible = false
	if sprite == null or sprite.texture == null or not (state == "walk" or state.begins_with("attack") or state.begins_with("skill")):
		return
	var key := sprite.get_instance_id()
	if not _meshes.has(key):
		var mesh := Polygon2D.new()
		mesh.name = "ArticulatedBody"
		sprite.add_child(mesh)
		var triangles: Array[PackedInt32Array] = []
		for y in range(GRID):
			for x in range(GRID):
				var a := y * (GRID + 1) + x
				triangles.append(PackedInt32Array([a, a + 1, a + GRID + 2]))
				triangles.append(PackedInt32Array([a, a + GRID + 2, a + GRID + 1]))
		mesh.polygons = triangles
		_meshes[key] = mesh
	var mesh: Polygon2D = _meshes[key]
	mesh.texture = sprite.texture
	var vertices := PackedVector2Array()
	var uvs := PackedVector2Array()
	var size := Vector2(sprite.texture.get_size())
	for y in range(GRID + 1):
		for x in range(GRID + 1):
			var pixel := Vector2(x, y) * 1254.0 / GRID
			vertices.append((map_point(pixel) - Vector2(627, 627)) * size / 1254.0)
			uvs.append(pixel * size / 1254.0)
	mesh.polygon = vertices
	mesh.uv = uvs
	mesh.visible = true
	sprite.self_modulate.a = 0.0

func _sample_walk_mapping(pixel: Vector2) -> Vector2:
	var cell := pixel / 1254.0 * GRID
	var origin := cell.floor()
	var fraction := cell - origin
	var a := origin * 1254.0 / GRID
	var step := 1254.0 / GRID
	if fraction.x >= fraction.y:
		return map_point(a) * (1.0 - fraction.x) + map_point(a + Vector2(step, 0)) * (fraction.x - fraction.y) + map_point(a + Vector2(step, step)) * fraction.y
	return map_point(a) * (1.0 - fraction.y) + map_point(a + Vector2(step, step)) * fraction.x + map_point(a + Vector2(0, step)) * (fraction.y - fraction.x)

func sample_rendered_point(pixel: Vector2) -> Vector2:
	if _sprite == null or not _meshes.has(_sprite.get_instance_id()):
		return pixel
	var mesh: Polygon2D = _meshes[_sprite.get_instance_id()]
	if not mesh.visible:
		return pixel
	# Interpolate the actual rendered triangle, rather than trusting the analytic
	# deformation at a non-vertex point. Contact therefore follows raster geometry.
	var cell := (pixel / 1254.0 * GRID).clamp(Vector2.ZERO, Vector2(GRID - 0.001, GRID - 0.001))
	var x := int(floor(cell.x))
	var y := int(floor(cell.y))
	var fraction := cell - Vector2(x,y)
	var a := y * (GRID + 1) + x
	var point: Vector2
	if fraction.x >= fraction.y:
		point = mesh.polygon[a] * (1.0 - fraction.x) + mesh.polygon[a+1] * (fraction.x - fraction.y) + mesh.polygon[a+GRID+2] * fraction.y
	else:
		point = mesh.polygon[a] * (1.0 - fraction.y) + mesh.polygon[a+GRID+2] * fraction.x + mesh.polygon[a+GRID+1] * (fraction.y - fraction.x)
	return point * 1254.0 / Vector2(_sprite.texture.get_size()) + Vector2(627,627)

func get_walk_support_residual() -> float:
	if _state != "walk" or _sprite == null or not is_instance_valid(_sprite) or _support_side < 0:
		return -1.0
	var foot := Vector2(395, 1040) if _support_side == 0 else Vector2(945, 1090)
	var rendered := sample_rendered_point(foot)
	var size := Vector2(_sprite.texture.get_size())
	var rendered_global := _sprite.to_global((rendered - Vector2(627, 627)) * size / 1254.0)
	return rendered_global.distance_to(_support_global)

func get_walk_pelvis_lift() -> float:
	if _state != "walk":
		return 0.0
	# Measure the interpolated rendered triangle, not the intended sine amplitude.
	var pelvis := Vector2(660, 600)
	return pelvis.y - sample_rendered_point(pelvis).y

func map_point(pixel: Vector2) -> Vector2:
	var result := pixel
	if _state == "walk":
		# Keep the support shoe fixed. The free leg swings from the hip and bends
		# at the knee; a broad, smooth falloff keeps the 64x64 skin from creasing.
		var left_support := _stride < PI
		var cycle := fposmod(_stride, TAU)
		var swing := sin(cycle)
		var lift := absf(swing)
		var leg_weight := smoothstep(640.0, 760.0, pixel.y)
		var upper_body_weight := 1.0 - smoothstep(570.0, 735.0, pixel.y)
		var swing_side_weight := _smooth_capsule_weight(pixel, Vector2(500.0, 840.0), Vector2(395.0, 1040.0), 150.0)
		var opposite_side_weight := _smooth_capsule_weight(pixel, Vector2(790.0, 850.0), Vector2(945.0, 1090.0), 155.0)
		var free_weight := (opposite_side_weight if left_support else swing_side_weight) * leg_weight
		var foot_sign := -1.0 if left_support else 1.0
		var hip := Vector2(760.0, 700.0) if left_support else Vector2(650.0, 700.0)
		var knee := Vector2(900.0, 910.0) if left_support else Vector2(330.0, 900.0)
		var ankle := Vector2(945.0, 1090.0) if left_support else Vector2(395.0, 1040.0)
		var hip_turn := swing * 0.20
		var knee_turn := lift * 0.26
		var leg_pose := _rotate_delta(pixel, hip, hip_turn) * _segment_weight(pixel, hip, knee, 135.0)
		leg_pose += _rotate_delta(pixel, knee, knee_turn) * _segment_weight(pixel, knee, ankle, 125.0)
		result += leg_pose * free_weight
		result += Vector2(foot_sign * 28.0 * swing, -42.0 * lift) * free_weight
		# The other leg counter-swings from the hip while retaining a quiet ankle.
		var support_hip := Vector2(650.0, 700.0) if left_support else Vector2(760.0, 700.0)
		var support_knee := Vector2(330.0, 900.0) if left_support else Vector2(900.0, 910.0)
		var support_weight := (1.0 - free_weight) * leg_weight
		result += _rotate_delta(pixel, support_hip, -swing * 0.035) * _segment_weight(pixel, support_hip, support_knee, 145.0) * support_weight
		# Carry the knee, calf and boot together. Concentrating the correction at
		# the ankle stretches the shoe and pinches the trouser hem into a spike.
		result += _support_offset * smoothstep(600.0, 850.0, pixel.y) * (1.0 - free_weight)
		# Hip bounce, shoulder counter-roll, and head/hair lag read at game scale.
		result.y -= 12.0 * absf(swing) * upper_body_weight
		var waist := Vector2(650.0, 650.0)
		var torso_weight := smoothstep(430.0, 510.0, pixel.y) * (1.0 - smoothstep(690.0, 775.0, pixel.y))
		result += _rotate_delta(pixel, waist, -swing * 0.018) * torso_weight
		# Arms counter-swing across the shoulder line to balance the free leg.
		var lead_shoulder := Vector2(720.0, 410.0)
		var guard_shoulder := Vector2(555.0, 440.0)
		result += _rotate_delta(pixel, lead_shoulder, -swing * 0.035) * _smooth_capsule_weight(pixel, lead_shoulder, Vector2(1035.0, 395.0), 105.0)
		result += _rotate_delta(pixel, guard_shoulder, swing * 0.045) * _smooth_capsule_weight(pixel, guard_shoulder, Vector2(490.0, 505.0), 100.0)
		var head_weight := 1.0 - smoothstep(220.0, 370.0, pixel.y)
		var head_pivot := Vector2(660.0, 325.0)
		result += _rotate_delta(pixel, head_pivot, -swing * 0.025) * head_weight
		# Ponytail mass sits behind the skull; it trails by a small delayed arc.
		var pony_weight := _smooth_capsule_weight(pixel, Vector2(555.0, 215.0), Vector2(390.0, 300.0), 105.0)
		result += Vector2(-swing * 11.0, swing * 7.0) * pony_weight
	elif _state.begins_with("attack"):
		var extension := _progress if _phase == "startup" else (0.78 if _phase == "combo_hold" else (1.0 if _phase == "active" else 1.0 - 0.28 * _progress))
		var torso_weight := smoothstep(430.0, 500.0, pixel.y) * (1.0 - smoothstep(625.0, 710.0, pixel.y)) * smoothstep(470.0, 560.0, pixel.x) * (1.0 - smoothstep(820.0, 930.0, pixel.x))
		var waist := Vector2(650.0, 610.0)
		var lean := 0.0
		if _stage == 1:
			# Straight punch: shoulder advances first, elbow opens on the hit.
			var shoulder := Vector2(720.0, 410.0)
			var elbow := Vector2(875.0, 452.0)
			var arm_weight := _smooth_capsule_weight(pixel, shoulder, Vector2(1040.0, 395.0), 122.0)
			var cock := (1.0 - extension) * 0.075
			var drive := extension * (0.045 if _phase == "active" else 0.035)
			result += _rotate_delta(pixel, shoulder, cock - drive) * arm_weight
			result += _rotate_delta(pixel, elbow, -0.045 * (1.0 - extension) + 0.035 * extension) * _smooth_capsule_weight(pixel, elbow, Vector2(1040.0, 395.0), 120.0)
			result += Vector2(16.0 * extension, 2.0) * arm_weight
			lean = -0.035 * extension
		elif _stage == 2:
			# Cross-body second strike folds at the elbow on windup, then opens.
			var shoulder := Vector2(715.0, 420.0)
			var elbow := Vector2(830.0, 465.0)
			var arm_weight := _smooth_capsule_weight(pixel, shoulder, Vector2(1000.0, 375.0), 130.0)
			result += _rotate_delta(pixel, shoulder, 0.04 * (1.0 - extension) - 0.035 * extension) * arm_weight
			result += _rotate_delta(pixel, elbow, 0.04 * (1.0 - extension) - 0.025 * extension) * _smooth_capsule_weight(pixel, elbow, Vector2(1000.0, 375.0), 135.0)
			result += Vector2(-18.0 * (1.0 - extension), -5.0 * (1.0 - extension)) * arm_weight
			lean = -0.045 * extension
		else:
			# Overhead third strike rotates through the shoulder with a separate
			# forearm arc; the chest only counter-turns a few degrees.
			var swing := 0.06 * (1.0 - _progress) if _phase == "active" else (0.06 if _phase in ["startup", "combo_hold"] else 0.06 * _progress)
			var shoulder := Vector2(720.0, 410.0)
			var elbow := Vector2(860.0, 365.0)
			result += _rotate_delta(pixel, shoulder, -swing) * _smooth_capsule_weight(pixel, shoulder, Vector2(1040.0, 390.0), 138.0)
			result += _rotate_delta(pixel, elbow, swing * 0.025) * _smooth_capsule_weight(pixel, elbow, Vector2(1040.0, 390.0), 140.0)
			lean = 0.04 * swing
		result += _rotate_delta(pixel, waist, lean) * torso_weight
		result += Vector2(12.0 * extension, -5.0 * extension) * torso_weight
	elif _state.begins_with("skill"):
		var weight := _smooth_capsule_weight(pixel, Vector2(850.0, 490.0), Vector2(1000.0, 390.0), 165.0)
		var extension := _progress if _phase == "startup" else (1.0 if _phase == "active" else 1.0 - _progress)
		if _stage == 1:
			result += Vector2(24.0 + (8.0 * _progress if _phase == "active" else 0.0), 8.0) * extension * weight
		else:
			var arc := sin(_progress * PI) if _phase == "active" else 0.0
			var elbow := Vector2(850.0, 490.0)
			var angle := 0.10 * arc + 0.025 * _progress if _phase == "active" else (-0.045 * _progress if _phase == "startup" else 0.025 * (1.0 - _progress))
			result += ((pixel - elbow).rotated(angle) - (pixel - elbow)) * weight
			var torso_weight := smoothstep(390.0,450.0,pixel.y) * (1.0-smoothstep(610.0,670.0,pixel.y)) * smoothstep(450.0,560.0,pixel.x) * (1.0-smoothstep(800.0,890.0,pixel.x))
			var waist := Vector2(660.0,600.0)
			result += ((pixel-waist).rotated(-0.05*arc)-(pixel-waist)) * torso_weight
	return result

func _rotate_delta(point: Vector2, pivot: Vector2, angle: float) -> Vector2:
	return (point - pivot).rotated(angle) - (point - pivot)

func _segment_weight(point: Vector2, start: Vector2, finish: Vector2, radius: float) -> float:
	return _smooth_capsule_weight(point, start, finish, radius)

func _smooth_capsule_weight(point: Vector2, start: Vector2, finish: Vector2, radius: float) -> float:
	var segment := finish - start
	var t := clampf((point - start).dot(segment) / maxf(segment.length_squared(), 0.001), 0.0, 1.0)
	var distance := point.distance_to(start + segment * t)
	return 1.0 - smoothstep(radius * 0.55, radius, distance)
