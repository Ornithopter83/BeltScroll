extends SceneTree

const RAIDER_SCENE := "res://scenes/enemies/forest_raider.tscn"
const MIN_REQUIRED_GAP := 35.0
const ARENA_MAX_X := 1745.0
const ARENA_MIN_X := 175.0
const ARENA_MIN_Y := 143.0
const ARENA_MAX_Y := 978.0

class TestPlayer:
	extends CharacterBody2D
	func _init() -> void:
		name = "Player"
		collision_layer = 1
		collision_mask = 0
		add_to_group("player")
		var shape := CollisionShape2D.new()
		var circle := CircleShape2D.new()
		circle.radius = 10.0
		shape.shape = circle
		add_child(shape)

var failures: Array[String] = []
var player: TestPlayer
var raiders: Array[CharacterBody2D] = []
var attack_observed_during_exercise := false

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var packed := load(RAIDER_SCENE) as PackedScene
	player = TestPlayer.new()
	player.position = Vector2(1748.0, 410.0)
	root.add_child(player)
	await _spawn_group(packed, 2, Vector2(1728.0, 410.0))
	await _exercise_group("two Raiders at the arena edge", 90)

	# Move the target away, let pursuit restart, then return it for another attack cycle.
	var pair_before := _center_x()
	player.global_position = Vector2(1540.0, 410.0)
	await _observe_spacing(55)
	_check(_center_x() < pair_before, "two Raiders resume pursuit after the player retreats from the boundary")
	player.global_position = Vector2(1748.0, 410.0)
	await _exercise_group("two Raiders after pursuit resumes", 75)
	_check(attack_observed_during_exercise, "two Raider attack cycles resume after spacing and pursuit")
	await _clear_group()

	# Three coincident bodies exercise pairwise steering while the player crosses lanes and edges.
	player.global_position = Vector2(1748.0, 410.0)
	await _spawn_group(packed, 3, Vector2(1728.0, 410.0))
	await _exercise_group("three Raiders at the arena edge", 100)
	var center_at_right := _center_x()
	player.global_position = Vector2(1510.0, 490.0)
	await _observe_spacing(65)
	_check(_center_x() < center_at_right, "three Raiders resume pursuit after the player changes position and depth")
	player.global_position = Vector2(1748.0, 410.0)
	await _exercise_group("three Raiders on the return attack cycle", 100)
	_check(attack_observed_during_exercise, "three Raider attack cycles resume after repeated separation")
	_check(_all_inside_arena(), "spacing and knock-free pursuit keep Raiders inside arena bounds")

	if failures.is_empty():
		print("raider_spacing_stress_smoke: all checks passed")
		quit(0)
	else:
		for failure in failures:
			push_error("raider_spacing_stress_smoke: " + failure)
		push_error("raider_spacing_stress_smoke: %d check(s) failed" % failures.size())
		quit(1)

func _spawn_group(packed: PackedScene, count: int, at: Vector2) -> void:
	for _index in range(count):
		var raider := packed.instantiate() as CharacterBody2D
		raider.position = at
		root.add_child(raider)
		raiders.append(raider)
	await _frames(1)

func _clear_group() -> void:
	for raider in raiders:
		raider.queue_free()
	raiders.clear()
	await _frames(2)

func _exercise_group(label: String, frame_count: int) -> void:
	# Give the exact-overlap spawn a brief split window before measuring combat spacing.
	attack_observed_during_exercise = false
	await _frames(35)
	attack_observed_during_exercise = _any_attacking()
	var observed_min := INF
	var observed_min_frame := -1
	var observed_min_positions := ""
	for _frame in range(frame_count):
		await physics_frame
		attack_observed_during_exercise = attack_observed_during_exercise or _any_attacking()
		var gap := _minimum_pair_gap()
		if gap < observed_min:
			observed_min = gap
			observed_min_frame = _frame
			observed_min_positions = _positions_text()
		_check(gap > MIN_REQUIRED_GAP, "%s keeps every live pair above 35px" % label)
		if not _all_inside_arena():
			_check(false, "%s keeps each Raider inside the arena" % label)
			break
	print("%s minimum gap %.2fpx at sample %d; positions: %s" % [label, observed_min, observed_min_frame, observed_min_positions])
	_check(observed_min > MIN_REQUIRED_GAP, "%s never collapses Raider spacing" % label)

func _positions_text() -> String:
	var positions: Array[String] = []
	for raider in raiders:
		if is_instance_valid(raider):
			positions.append("(%.1f, %.1f)" % [raider.global_position.x, raider.global_position.y])
	return ", ".join(positions)

func _observe_spacing(frame_count: int) -> void:
	for _frame in range(frame_count):
		await physics_frame
		_check(_minimum_pair_gap() > MIN_REQUIRED_GAP, "Raider spacing remains above 35px while pursuing a moving player")

func _minimum_pair_gap() -> float:
	var minimum := INF
	for left_index in range(raiders.size()):
		for right_index in range(left_index + 1, raiders.size()):
			var left := raiders[left_index]
			var right := raiders[right_index]
			if is_instance_valid(left) and is_instance_valid(right):
				minimum = minf(minimum, left.global_position.distance_to(right.global_position))
	return minimum

func _center_x() -> float:
	var total := 0.0
	for raider in raiders:
		total += raider.global_position.x
	return total / maxf(1.0, float(raiders.size()))

func _any_attacking() -> bool:
	for raider in raiders:
		if raider.get("attack_phase") == "windup" or raider.get("attack_phase") == "active":
			return true
	return false

func _all_inside_arena() -> bool:
	for raider in raiders:
		if raider.global_position.x < ARENA_MIN_X - 0.2 or raider.global_position.x > ARENA_MAX_X + 0.2:
			return false
		if raider.global_position.y < ARENA_MIN_Y - 0.2 or raider.global_position.y > ARENA_MAX_Y + 0.2:
			return false
	return true

func _frames(count: int) -> void:
	for _frame in range(count):
		await physics_frame

func _check(condition: bool, description: String) -> void:
	if condition:
		return
	if failures.has(description):
		return
	failures.append(description)
