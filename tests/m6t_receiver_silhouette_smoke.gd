extends SceneTree
## Reject receivers expanded into empty space to manufacture combat reach.
var failures: Array[String] = []
func _initialize() -> void:
	call_deferred("_run")
func _run() -> void:
	var boss = load("res://scenes/enemies/ruins_warden_boss.tscn").instantiate()
	root.add_child(boss)
	boss.set_combat_active(true)
	boss.set_physics_process(false)
	var receiver: CollisionShape2D = boss.get_node("ReceiveArea/CollisionShape2D")
	var capsule: CapsuleShape2D = receiver.shape
	var half_segment := capsule.height * 0.5 - capsule.radius
	var outside := 0
	for side in [-1.0,1.0]:
		for sample in range(21):
			var point := Vector2(side*capsule.radius,lerpf(-half_segment,half_segment,float(sample)/20.0))
			if not _inside_boss(boss,receiver.to_global(point)):
				outside += 1
	for half in [0,1]:
		for sample in range(33):
			var angle := (-PI if half == 0 else 0.0) + PI * float(sample) / 32.0
			var point := Vector2(cos(angle)*capsule.radius,sin(angle)*capsule.radius + (-half_segment if half == 0 else half_segment))
			if not _inside_boss(boss,receiver.to_global(point)):
				outside += 1
	_check(outside == 0,"Boss upper receiver outline lies inside actual Head/Torso silhouette: %d outside samples" % outside)
	var raider = load("res://scenes/enemies/forest_raider.tscn").instantiate()
	root.add_child(raider)
	raider.set_physics_process(false)
	var art: Sprite2D = raider.get_node("VisualRoot/RaiderArt")
	var image := art.texture.get_image()
	var raider_receiver: CollisionShape2D = raider.get_node("ReceiveArea/CollisionShape2D")
	var radius := (raider_receiver.shape as CircleShape2D).radius
	var covered := 0
	for sample in range(48):
		var angle := TAU*float(sample)/48.0
		var world := raider_receiver.to_global(Vector2(cos(angle),sin(angle))*radius)
		var pixel := Vector2i(art.to_local(world) + Vector2(art.texture.get_size()) * 0.5)
		if Rect2i(Vector2i.ZERO,image.get_size()).has_point(pixel) and image.get_pixelv(pixel).a > 0.1:
			covered += 1
	_check(covered == 48,"Raider receive circle perimeter is covered by actual upper-body alpha: %d/48" % covered)
	print("M6T_RECEIVER_SILHOUETTE|fail=%d" % failures.size())
	quit(0 if failures.is_empty() else 1)
func _inside_boss(boss: Node,point: Vector2) -> bool:
	for path in ["VisualRoot/Head","VisualRoot/Torso"]:
		var drawing: Polygon2D = boss.get_node(path)
		if Geometry2D.is_point_in_polygon(drawing.to_local(point),drawing.polygon):
			return true
	return false
func _check(value: bool,description: String) -> void:
	if value:
		print("PASS: " + description)
	else:
		failures.append(description)
		push_error("FAIL: " + description)
