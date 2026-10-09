extends SceneTree

const RAIDER_SCENE := "res://scenes/enemies/forest_raider.tscn"
const FLOOR_TOLERANCE := 0.5
const ART_SCALE := Vector2(0.446928, 0.446928)

var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var packed := load(RAIDER_SCENE) as PackedScene
	_check(packed != null, "integrated ForestRaider scene loads")
	if packed == null:
		_finish()
		return
	var ysort := Node2D.new()
	ysort.name = "YSortActors"
	ysort.y_sort_enabled = true
	root.add_child(ysort)
	var raider := packed.instantiate() as CharacterBody2D
	ysort.add_child(raider)
	await process_frame
	raider.set_physics_process(false)
	var art := raider.get_node("VisualRoot/RaiderArt") as Sprite2D
	var animator := raider.get_node("VisualAnimator")
	_check(animator != null and animator.get_script() != null, "standalone VisualAnimator is attached to the Raider scene")
	_check(ysort.y_sort_enabled and raider.get_parent() == ysort, "Raider remains a direct YSort actor")
	_check(art != null and art.texture != null, "RaiderArt sprite and approved texture remain available")
	if art == null or art.texture == null or animator == null:
		_finish()
		return

	var root_position := raider.position
	var art_position := art.position
	var authored_art_position: Vector2 = animator.get("_base_position")
	var art_scale := art.scale
	var art_rotation := art.rotation
	var body_shape := raider.get_node("CollisionShape2D") as CollisionShape2D
	var attack_shape := raider.get_node("AttackArea/CollisionShape2D") as CollisionShape2D
	var receive_shape := raider.get_node("ReceiveArea/CollisionShape2D") as CollisionShape2D
	var attack_area_position := (raider.get_node("AttackArea") as Area2D).position
	var receive_area_position := (raider.get_node("ReceiveArea") as Area2D).position
	var baseline_foot := _foot_point(art)
	var sprite_parent_position := (art.get_parent() as Node2D).position
	var ysort_enabled := ysort.y_sort_enabled
	_check(authored_art_position.is_equal_approx(Vector2(0.149, -219.2)) and art_scale.is_equal_approx(ART_SCALE), "RaiderArt uses the enlarged scale and adjusted alpha-foot anchor")
	var alpha_bounds := art.texture.get_image().get_used_rect()
	var alpha_foot := Vector2(float(alpha_bounds.position.x) + float(alpha_bounds.size.x) * 0.5, float(alpha_bounds.end.y))
	var centered_foot := alpha_foot - Vector2(art.texture.get_size()) * 0.5
	var local_foot := centered_foot * art.scale
	var authored_ground_anchor := sprite_parent_position + art_position + local_foot
	_check(alpha_bounds.position.x >= 0 and alpha_bounds.position.y >= 0 and alpha_bounds.end.x <= art.texture.get_width() and alpha_bounds.end.y <= art.texture.get_height(), "enlarged Raider texture has an in-bounds alpha silhouette")
	_check(authored_ground_anchor.length() <= FLOOR_TOLERANCE, "enlarged Raider alpha foot stays at the actor floor anchor within subpixel raster tolerance")

	# Idle breath stays subtle and keeps the authored alpha-edge floor anchor fixed.
	animator.call("_process", 1.0 / 60.0)
	_check(art.scale.distance_to(art_scale) < 0.002 and absf(art.rotation - art_rotation) < 0.006, "idle breathing remains a restrained micro-motion")
	_check(_foot_point(art).distance_to(baseline_foot) <= FLOOR_TOLERANCE, "idle motion preserves the alpha-edge foot anchor")
	_check(raider.position == root_position and raider.velocity == Vector2.ZERO, "idle visual motion does not move the physics root")

	raider.velocity = Vector2(118.0, 0.0)
	animator.call("_process", 0.18)
	var walking_pose := art.rotation
	var walking_scale := art.scale
	animator.call("_process", 0.18)
	_check(not is_equal_approx(walking_pose, art.rotation) or not walking_scale.is_equal_approx(art.scale), "tracking speed produces a changing walk rhythm")
	_check(_foot_point(art).distance_to(baseline_foot) <= FLOOR_TOLERANCE, "walk rhythm preserves the foot anchor")
	_check(raider.position == root_position and raider.velocity == Vector2(118.0, 0.0), "walk pose leaves Raider position and velocity untouched")

	raider.velocity = Vector2.ZERO
	raider.set("attack_phase", "windup")
	raider.set("attack_phase_remaining", 0.0)
	animator.call("_process", 0.2)
	var windup_rotation := art.rotation
	var windup_scale := art.scale
	var windup_position := art.position
	_check(not is_equal_approx(windup_rotation, art_rotation) or not windup_scale.is_equal_approx(art_scale) or not windup_position.is_equal_approx(art_position), "windup creates a preparatory pose")
	_check(raider.position == root_position and raider.velocity == Vector2.ZERO, "attack poses leave the physics root and velocity untouched")
	raider.set("attack_phase", "active")
	animator.call("_process", 0.2)
	_check(absf(art.rotation - windup_rotation) > 0.005 or art.scale.distance_to(windup_scale) > 0.005 or art.position.distance_to(windup_position) > 0.005, "active phase changes to a distinct strike pose")
	var active_rotation := art.rotation
	var active_scale := art.scale
	var active_position := art.position
	_check(_foot_point(art).distance_to(baseline_foot) <= FLOOR_TOLERANCE, "attack poses preserve the foot anchor")
	raider.set("attack_phase", "recovery")
	raider.set("attack_phase_remaining", 0.0)
	for _frame in range(45):
		animator.call("_process", 1.0 / 60.0)
	_check(absf(art.rotation - art_rotation) < 0.01 and art.scale.distance_to(art_scale) < 0.004, "recovery smoothly returns to the neutral transform")
	_check(absf(active_rotation - art_rotation) > 0.02 or active_scale.distance_to(art_scale) > 0.02 or active_position.distance_to(art_position) > 0.02, "active strike has a readable transform from neutral")

	raider.set("attack_phase", "idle")
	raider.velocity = Vector2(80.0, 0.0)
	raider.set("hit_flash_remaining", 0.14)
	raider.set("hitstun_remaining", 0.2)
	raider.set("hit_reaction_direction", Vector2.LEFT)
	raider.set("hit_reaction_strength", 0.72)
	animator.call("_process", 1.0 / 60.0)
	_check(absf(art.rotation - art_rotation) > 0.02 or art.scale.distance_to(art_scale) > 0.02, "hit flash and hitstun produce a recoil pose")
	_check(_foot_point(art).distance_to(baseline_foot) <= FLOOR_TOLERANCE, "hit recoil preserves the foot anchor")
	_check(raider.position == root_position and raider.velocity == Vector2(80.0, 0.0), "hit recoil leaves physical knockback velocity to the Raider controller")
	var regular_hit_pose := Vector3(art.rotation, art.scale.x, art.scale.y)
	raider.set("hit_flash_remaining", 0.16)
	raider.set("hitstun_remaining", 0.34)
	raider.set("hit_reaction_strength", 1.32)
	for _frame in range(8):
		animator.call("_process", 1.0 / 60.0)
	var skill_hit_pose := Vector3(art.rotation, art.scale.x, art.scale.y)
	_check(skill_hit_pose.distance_to(regular_hit_pose) > 0.01, "strong skill hit produces a larger visual reaction than a regular hit")
	_check(raider.position == root_position and raider.velocity == Vector2(80.0, 0.0), "stronger hit pose remains visual-only")

	raider.set("health", 0)
	raider.velocity = Vector2.ZERO
	for _frame in range(60):
		animator.call("_process", 1.0 / 60.0)
	var ko_rotation := art.rotation
	var ko_scale := art.scale
	for _frame in range(30):
		animator.call("_process", 1.0 / 60.0)
	_check(is_equal_approx(art.rotation, ko_rotation) and art.scale.is_equal_approx(ko_scale), "KO settles into a still pose without continued idle or stride oscillation")
	_check(_foot_point(art).distance_to(baseline_foot) <= FLOOR_TOLERANCE, "KO pose preserves the foot anchor")

	_check(raider.position == root_position and raider.velocity == Vector2.ZERO, "visual animation leaves the physics root and movement state unchanged")
	_check(body_shape == raider.get_node("CollisionShape2D") and attack_shape == raider.get_node("AttackArea/CollisionShape2D") and receive_shape == raider.get_node("ReceiveArea/CollisionShape2D"), "body, attack, and receive hitboxes retain their nodes")
	var body_capsule := body_shape.shape as CapsuleShape2D
	var attack_rect := attack_shape.shape as RectangleShape2D
	var receive_circle := receive_shape.shape as CircleShape2D
	_check(body_capsule != null and is_equal_approx(body_capsule.radius, 18.0) and is_equal_approx(body_capsule.height, 42.0), "enlarged Raider collision body matches the new footprint")
	_check(attack_rect != null and attack_rect.size.is_equal_approx(Vector2(78.0, 48.0)) and receive_circle != null and is_equal_approx(receive_circle.radius, 30.0), "attack and receive judgment areas grow with the enlarged Raider")
	_check(float(raider.get("separation_radius")) >= 108.0 and float(raider.get("attack_range")) >= 96.0, "larger Raider attack reach and spacing are configured")
	_check((raider.get_node("AttackArea") as Area2D).position == attack_area_position and (raider.get_node("ReceiveArea") as Area2D).position == receive_area_position, "attack and receive hitbox positions remain unchanged")
	_check((art.get_parent() as Node2D).position == sprite_parent_position and ysort.y_sort_enabled == ysort_enabled, "VisualRoot placement and YSort contract remain unchanged")
	ysort.queue_free()
	_finish()

func _foot_point(sprite: Sprite2D) -> Vector2:
	var bounds := sprite.texture.get_image().get_used_rect()
	var texture_size := Vector2(sprite.texture.get_size())
	var alpha_foot := Vector2(float(bounds.position.x) + float(bounds.size.x) * 0.5, float(bounds.end.y))
	var local_offset := (alpha_foot - texture_size * 0.5) * sprite.scale
	return sprite.position + local_offset.rotated(sprite.rotation)

func _check(condition: bool, description: String) -> void:
	if condition:
		print("PASS: " + description)
	else:
		failures.append(description)

func _finish() -> void:
	if failures.is_empty():
		print("raider_visual_animator_smoke: all checks passed")
		quit(0)
		return
	for failure in failures:
		push_error("raider_visual_animator_smoke: " + failure)
	push_error("raider_visual_animator_smoke: %d check(s) failed" % failures.size())
	quit(1)
