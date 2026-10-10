extends CanvasLayer
"""Global, read-only collision-shape visualizer toggled with F10."""

const PLAYER_SCRIPT := "res://scripts/player/player_controller.gd"
const RAIDER_SCRIPT := "res://scripts/enemies/forest_raider.gd"
const BOSS_SCRIPT := "res://scripts/enemies/ruins_warden_boss.gd"
const FONT_SIZE := 14
const ARC_STEPS := 20

var enabled := false
var _font: Font
var _drawing: Node2D

func _ready() -> void:
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS
	_font = ThemeDB.fallback_font
	_drawing = Node2D.new()
	_drawing.name = "CollisionShapes"
	add_child(_drawing)
	_drawing.draw.connect(_draw_shapes)
	get_tree().scene_changed.connect(_on_scene_changed)

func _process(_delta: float) -> void:
	if enabled:
		_drawing.queue_redraw()

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F10:
		enabled = not enabled
		_drawing.visible = enabled
		_drawing.queue_redraw()
		get_viewport().set_input_as_handled()

func _on_scene_changed() -> void:
	# Every scene launch/restart starts with a clean, hidden diagnostic view.
	enabled = false
	_drawing.visible = false

func _draw_shapes() -> void:
	if not enabled:
		return
	# Discover combat roots directly so the visualizer does not depend on gameplay
	# scripts adding debug groups or changing collision state.
	var scene := get_tree().current_scene
	if scene != null:
		_visit(scene)

func _visit(node: Node) -> void:
	if node is CollisionShape2D:
		_draw_candidate(node as CollisionShape2D)
	for child in node.get_children():
		_visit(child)

func _draw_candidate(shape_node: CollisionShape2D) -> void:
	if not is_instance_valid(shape_node) or shape_node.shape == null or not shape_node.is_inside_tree():
		return
	var owner := _combat_owner(shape_node)
	if owner == null:
		return
	var collider := shape_node.get_parent() as CollisionObject2D
	if collider == null:
		return
	var kind := _shape_kind(shape_node.shape)
	if kind.is_empty():
		return
	var area := collider as Area2D
	var role := _role(owner, collider)
	var active := area != null and area.monitoring
	var color := _color_for(role, active)
	# draw_set_transform_matrix is local to this CanvasLayer's canvas. Shape
	# transforms already include the world canvas/camera, so convert between the
	# two canvas bases instead of applying the world transform twice.
	var drawing_canvas := _drawing.get_global_transform_with_canvas()
	var shape_canvas := shape_node.get_global_transform_with_canvas()
	var drawing_transform := drawing_canvas.affine_inverse() * shape_canvas
	_drawing.draw_set_transform_matrix(drawing_transform)
	_draw_shape_geometry(shape_node.shape, color)
	_drawing.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	var layer_bits := collider.collision_layer
	var mask_bits := collider.collision_mask
	var state := "MON:on" if active else ("MON:off" if area != null else "MON:body")
	if area != null:
		state += " MONABLE:%s" % ("on" if area.monitorable else "off")
	var disabled := " disabled" if shape_node.disabled else ""
	var owner_name := str(owner.name)
	var label := "%s / %s %s %s %s Layer:%d Mask:%d%s" % [owner_name, role, shape_node.name, kind, state, layer_bits, mask_bits, disabled]
	var label_position := drawing_transform * Vector2(7, -8)
	_drawing.draw_string(_font, label_position, label, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, color)

func _combat_owner(shape_node: CollisionShape2D) -> Node:
	var cursor := shape_node.get_parent()
	while cursor != null:
		if cursor is CharacterBody2D:
			var script := cursor.get_script() as Script
			if script != null and script.resource_path in [PLAYER_SCRIPT, RAIDER_SCRIPT, BOSS_SCRIPT]:
				return cursor
		cursor = cursor.get_parent()
	return null

func _role(owner: Node, collider: CollisionObject2D) -> String:
	if collider is CharacterBody2D:
		return "몸체"
	match str(collider.name):
		"AttackArea": return "공격"
		"ReceiveArea": return "피격"
		"Hitbox1": return "기본1타"
		"Hitbox2": return "기본2타"
		"Hitbox3": return "기본3타"
		"Skill1Hitbox": return "Num4"
		"Skill2Hitbox": return "Num5"
	return "영역"

func _shape_kind(shape: Shape2D) -> String:
	if shape is RectangleShape2D:
		return "사각형"
	if shape is CircleShape2D:
		return "원"
	if shape is CapsuleShape2D:
		return "캡슐"
	return ""

func _color_for(role: String, active: bool) -> Color:
	if role == "몸체":
		return Color(0.25, 0.78, 1.0, 0.95)
	if role == "피격":
		return Color(0.45, 0.85, 1.0, 0.9)
	if active:
		return Color(0.25, 1.0, 0.38, 0.98)
	return Color(1.0, 0.35, 0.28, 0.82)

func _draw_shape_geometry(shape: Shape2D, color: Color) -> void:
	if shape is RectangleShape2D:
		var rectangle := shape as RectangleShape2D
		_drawing.draw_rect(Rect2(-rectangle.size * 0.5, rectangle.size), color, false, 2.0)
	elif shape is CircleShape2D:
		_drawing.draw_arc(Vector2.ZERO, (shape as CircleShape2D).radius, 0.0, TAU, 48, color, 2.0, true)
	elif shape is CapsuleShape2D:
		_draw_capsule(shape as CapsuleShape2D, color)

func _draw_capsule(shape: CapsuleShape2D, color: Color) -> void:
	var radius := shape.radius
	var half_segment := maxf(0.0, shape.height * 0.5 - radius)
	var points := PackedVector2Array()
	for i in range(ARC_STEPS + 1):
		var angle := -PI * 0.5 + PI * float(i) / ARC_STEPS
		points.append(Vector2(cos(angle) * radius, -half_segment + sin(angle) * radius))
	for i in range(ARC_STEPS + 1):
		var angle := PI * 0.5 + PI * float(i) / ARC_STEPS
		points.append(Vector2(cos(angle) * radius, half_segment + sin(angle) * radius))
	_drawing.draw_polyline(points, color, 2.0, true)
