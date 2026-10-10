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
		if side != _support_side:
			_support_global = sprite.to_global((foot - Vector2(627, 627)) * size / 1254.0)
			_support_side = side
		_support_offset = sprite.to_local(_support_global) * 1254.0 / size + Vector2(627, 627) - foot
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
		# Independent ankle and knee movement; the support half is stationary in
		# local combat space while the other leg lifts and passes it.
		var left_support := _stride < PI
		var passing := sin(fposmod(_stride, PI))
		var leg := smoothstep(640.0, 1030.0, pixel.y)
		var left_weight := 1.0 - smoothstep(610.0, 710.0, pixel.x)
		var swing_weight := 1.0 - left_weight if left_support else left_weight
		result += _support_offset * leg * (1.0 - swing_weight)
		result.x += (-1.0 if left_support else 1.0) * passing * 225.0 * leg * swing_weight
		result.y -= passing * 90.0 * leg * swing_weight
		# Pelvis and shoulders rise while the planted ankle remains at its anchor.
		result.y -= passing * 18.0 * (1.0 - leg)
	elif _state.begins_with("attack"):
		var extension := _progress if _phase == "startup" else (0.65 if _phase == "combo_hold" else (1.0 if _phase == "active" else 1.0 - 0.35 * _progress))
		if _stage == 1:
			var weight := smoothstep(790.0, 1080.0, pixel.x) * (1.0 - smoothstep(490.0, 570.0, pixel.y))
			var contact_shift := Vector2(-95.0 + (25.0 * _progress if _phase == "active" else 25.0), 55.0)
			result += (contact_shift + Vector2(-160.0, 35.0) * (1.0 - extension)) * weight
		elif _stage == 2:
			var weight := smoothstep(840.0, 1040.0, pixel.x) * (1.0 - smoothstep(510.0, 580.0, pixel.y))
			result += Vector2(-110.0, -55.0) * (1.0 - extension) * weight
			if _phase == "active":
				result += Vector2(15.0 * _progress, 20.0 * sin(_progress * PI)) * weight
		else:
			var angle := 1.08 * (1.0 - _progress) if _phase == "active" else (1.08 if _phase == "startup" else 0.0)
			if _phase == "recovery":
				angle = 1.08 * _progress
			elif _phase == "combo_hold":
				angle = 1.08
			var shoulder := Vector2(780.0, 410.0)
			var weight := smoothstep(770.0, 900.0, pixel.x) * (1.0 - smoothstep(350.0, 460.0, pixel.y))
			result += ((pixel - shoulder).rotated(angle) - (pixel - shoulder)) * weight
	elif _state.begins_with("skill"):
		var weight := smoothstep(730.0, 805.0, pixel.x) * smoothstep(330.0, 350.0, pixel.y) * (1.0 - smoothstep(450.0, 530.0, pixel.y))
		var extension := _progress if _phase == "startup" else (1.0 if _phase == "active" else 1.0 - _progress)
		if _stage == 1:
			result += Vector2(65.0 + (20.0 * _progress if _phase == "active" else 0.0), 24.0) * extension * weight
		else:
			var arc := sin(_progress * PI) if _phase == "active" else 0.0
			var elbow := Vector2(850.0, 490.0)
			var angle := 0.9 * arc + 0.2 * _progress if _phase == "active" else (-0.25 * _progress if _phase == "startup" else 0.2 * (1.0 - _progress))
			result += ((pixel - elbow).rotated(angle) - (pixel - elbow)) * weight
			var torso_weight := smoothstep(390.0,450.0,pixel.y) * (1.0-smoothstep(610.0,670.0,pixel.y)) * smoothstep(450.0,560.0,pixel.x) * (1.0-smoothstep(800.0,890.0,pixel.x))
			var waist := Vector2(660.0,600.0)
			result += ((pixel-waist).rotated(-0.12*arc)-(pixel-waist)) * torso_weight
	return result
