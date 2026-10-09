extends CharacterBody2D
"""A light forest enemy that pursues, attacks in its depth lane, and can be staggered."""

signal attack_windup_started
signal raider_hit(stage: int)
signal raider_ko

@export var walk_speed: float = 118.0
@export var arena_bounds: Rect2 = Rect2(Vector2(160, 100), Vector2(1600, 880))
@export var max_health: int = 3
@export var notice_range: float = 560.0
@export var attack_range: float = 96.0
@export var attack_depth_tolerance: float = 34.0
@export var separation_radius: float = 108.0
@export var separation_strength: float = 120.0
@export var windup_duration: float = 0.42
@export var active_duration: float = 0.16
@export var recovery_duration: float = 0.62
@export var attack_damage: int = 1
@export var attack_knockback: float = 230.0
@export var attack_hit_stun: float = 0.22

@onready var visual_root: Node2D = $VisualRoot
@onready var body_visual: Sprite2D = $VisualRoot/RaiderArt
@onready var attack_flash: Polygon2D = $VisualRoot/AttackFlash
@onready var attack_area: Area2D = $AttackArea
@onready var receive_area: Area2D = $ReceiveArea

const BODY_HALF_WIDTH := 18.0
const BODY_BOTTOM_OFFSET := 0.0
const SPACING_TARGET := 320.0
const SPACING_ENTER_RADIUS := 336.0
const SPACING_EXIT_RADIUS := 352.0
const SPACING_ESCAPE_SPEED := 120.0
const HIT_COLOR := Color(1.0, 0.78, 0.58, 1.0)
const KNOCKED_OUT_COLOR := Color(0.62, 0.62, 0.62, 0.78)

var health: int
var attack_phase := "idle"
var attack_phase_remaining := 0.0
var hitstun_remaining := 0.0
var hit_flash_remaining := 0.0
var facing_direction := Vector2.LEFT
var hit_reaction_direction := Vector2.LEFT
var hit_reaction_strength := 0.0
var _hit_targets: Dictionary = {}
var _spacing_engaged := false
var _silhouette_top_offset := -40.0
var _silhouette_bottom_offset := 0.0

func _ready() -> void:
	collision_layer = 2
	collision_mask = 1
	add_to_group("hit_receivers")
	add_to_group("forest_raiders")
	health = max_health
	attack_area.collision_layer = 0
	attack_area.collision_mask = 1
	attack_area.monitoring = false
	attack_area.body_entered.connect(_on_attack_body_entered)
	_measure_silhouette()
	_apply_arena_bounds()

func _measure_silhouette() -> void:
	# Movement bounds follow the visible alpha silhouette at its authored 3x
	# presentation scale, rather than the much smaller collision capsule.
	if body_visual.texture == null:
		return
	var alpha_bounds := body_visual.texture.get_image().get_used_rect()
	var texture_size := Vector2(body_visual.texture.get_size())
	var top_in_visual := (float(alpha_bounds.position.y) - texture_size.y * 0.5) * body_visual.scale.y
	var bottom_in_visual := (float(alpha_bounds.end.y) - texture_size.y * 0.5) * body_visual.scale.y
	_silhouette_top_offset = visual_root.position.y + body_visual.position.y + top_in_visual
	_silhouette_bottom_offset = visual_root.position.y + body_visual.position.y + bottom_in_visual
	# Preserve room for the animator's strongest lean and squash near the top edge.
	_silhouette_top_offset -= 24.0

func _physics_process(delta: float) -> void:
	_update_hit_flash(delta)
	if health <= 0:
		velocity = Vector2.ZERO
		_cancel_attack()
		return
	var player := _find_player()
	if hitstun_remaining > 0.0:
		hitstun_remaining = maxf(0.0, hitstun_remaining - delta)
		# Preserve the initial impact, then bleed momentum smoothly throughout stun.
		velocity = velocity.move_toward(Vector2.ZERO, (520.0 + velocity.length() * 2.8) * delta)
		move_and_slide()
		_apply_arena_bounds()
		_enforce_nearby_raider_spacing(delta)
		if hitstun_remaining == 0.0:
			velocity = Vector2.ZERO
		return

	if player == null or not is_instance_valid(player) or global_position.distance_to(player.global_position) > notice_range:
		attack_phase = "idle"
		attack_area.monitoring = false
		attack_flash.visible = false
		velocity = Vector2.ZERO
		return

	var offset := player.global_position - global_position
	if absf(offset.x) > 0.5:
		facing_direction = Vector2(signf(offset.x), 0.0)
		# The source illustration faces left, so positive scale faces left.
		visual_root.scale.x = -facing_direction.x
	var in_depth_lane := absf(offset.y) <= attack_depth_tolerance
	if attack_phase == "windup" and not in_depth_lane:
		_cancel_attack()

	match attack_phase:
		"idle":
			var desired := offset.normalized() * walk_speed
			if absf(offset.x) < attack_range * 0.82 and not in_depth_lane:
				desired.x = 0.0
			var spacing := _spacing_adjustment(desired)
			if offset.length() <= attack_range and in_depth_lane and spacing.minimum_gap >= SPACING_TARGET - 0.5:
				_begin_attack()
			else:
				velocity = spacing.velocity
				move_and_slide()
				_apply_arena_bounds()
				_enforce_nearby_raider_spacing(delta)
				return
		"windup":
			velocity = Vector2.ZERO
			attack_phase_remaining -= delta
			if attack_phase_remaining <= 0.0:
				if not in_depth_lane:
					_cancel_attack()
				else:
					attack_phase = "active"
					attack_phase_remaining = active_duration
					_hit_targets.clear()
					attack_area.monitoring = true
					_check_attack_targets()
		"active":
			velocity = Vector2.ZERO
			if not in_depth_lane:
				attack_area.monitoring = false
				attack_flash.visible = false
				attack_phase = "recovery"
				attack_phase_remaining = recovery_duration
			else:
				_check_attack_targets()
				attack_phase_remaining -= delta
				if attack_phase_remaining <= 0.0:
					attack_area.monitoring = false
					attack_flash.visible = false
					attack_phase = "recovery"
					attack_phase_remaining = recovery_duration
		"recovery":
			velocity = Vector2.ZERO
			attack_phase_remaining -= delta
			if attack_phase_remaining <= 0.0:
				attack_phase = "idle"
	move_and_slide()
	_apply_arena_bounds()
	_enforce_nearby_raider_spacing(delta)

func _begin_attack() -> void:
	attack_phase = "windup"
	attack_phase_remaining = windup_duration
	attack_area.position = facing_direction * (attack_range * 0.57) + Vector2(0.0, -30.0)
	attack_flash.position.x = facing_direction.x * 25.0
	attack_flash.visible = true
	attack_area.monitoring = false
	_hit_targets.clear()
	attack_windup_started.emit()

func _cancel_attack() -> void:
	attack_phase = "idle"
	attack_phase_remaining = 0.0
	attack_area.monitoring = false
	attack_flash.visible = false

func _check_attack_targets() -> void:
	for target in attack_area.get_overlapping_bodies():
		_on_attack_body_entered(target)

func _on_attack_body_entered(target: Node2D) -> void:
	if target == self or not target.is_in_group("hit_receivers") or not target.has_method("receive_hit"):
		return
	if absf(target.global_position.y - global_position.y) > attack_depth_tolerance:
		return
	var target_id := target.get_instance_id()
	if _hit_targets.has(target_id):
		return
	_hit_targets[target_id] = true
	var direction := (target.global_position - global_position).normalized()
	if direction == Vector2.ZERO:
		direction = facing_direction
	target.receive_hit({
		"damage": attack_damage,
		"direction": direction,
		"knockback": attack_knockback,
		"hit_stun": attack_hit_stun,
		"attack_stage": 1,
	})
func _spacing_adjustment(desired: Vector2) -> Dictionary:
	var adjusted := desired
	var was_engaged := _spacing_engaged
	var remains_engaged := false
	var minimum_gap := INF
	var enter_radius := maxf(SPACING_ENTER_RADIUS, separation_radius)
	var exit_radius := maxf(SPACING_EXIT_RADIUS, enter_radius + 8.0)
	var escape_speed := maxf(SPACING_ESCAPE_SPEED, separation_strength * 0.4)
	for candidate in get_tree().get_nodes_in_group("forest_raiders"):
		var other := candidate as Node2D
		if other == self or not is_instance_valid(other) or int(other.get("health")) <= 0:
			continue
		var away: Vector2 = global_position - other.global_position
		var distance := away.length()
		minimum_gap = minf(minimum_gap, distance)
		var active_radius := exit_radius if was_engaged else enter_radius
		if distance >= active_radius:
			continue
		remains_engaged = true
		if distance < SPACING_TARGET:
			away = _coincident_separation_direction(other)
		else:
			away /= distance
		away = _horizontal_separation_direction(away)

		# Remove any steering component that closes this pair. Below the target
		# gap, add an outward component so coincident groups split promptly.
		var inward_speed := adjusted.dot(-away)
		var outward_speed := escape_speed if distance < SPACING_TARGET else 0.0
		var correction := maxf(0.0, inward_speed + outward_speed)
		adjusted += away * correction
	_spacing_engaged = remains_engaged
	return {"velocity": adjusted.limit_length(walk_speed), "minimum_gap": minimum_gap}

func _coincident_separation_direction(other: Node2D) -> Vector2:
	var self_id := get_instance_id()
	var other_id := other.get_instance_id()
	var lower_id := mini(self_id, other_id)
	var higher_id := maxi(self_id, other_id)
	var pair_seed := hash("%d:%d" % [lower_id, higher_id]) & 0x7fffffff
	var angle := float(pair_seed) / 2147483647.0 * TAU
	var direction := Vector2(cos(angle), sin(angle))
	return direction if self_id == lower_id else -direction

func _enforce_nearby_raider_spacing(delta: float) -> void:
	# Steering alone can be clipped by arena bounds when several Raiders start
	# together. Resolve a small pairwise positional correction after movement so
	# every live Raider gets a clear escape path without changing collision masks.
	var live_raiders: Array[Node2D] = []
	for candidate in get_tree().get_nodes_in_group("forest_raiders"):
		var raider := candidate as Node2D
		if raider != null and is_instance_valid(raider) and raider != self and int(raider.get("health")) > 0:
			live_raiders.append(raider)
	var max_step := SPACING_ESCAPE_SPEED * delta
	for _iteration in range(2):
		for other in live_raiders:
			var away := global_position - other.global_position
			var distance := away.length()
			if distance >= SPACING_TARGET:
				continue
			if distance <= 0.001:
				away = _coincident_separation_direction(other)
			else:
				away /= distance
			away = _horizontal_separation_direction(away)
			var step := minf(max_step, (SPACING_TARGET - distance) * 0.5)
			var best_self := global_position
			var best_other := other.global_position
			var best_gap := distance
			var candidate_gap := distance
			var other_body := other as CharacterBody2D
			if other_body == null:
				continue
			for direction_index in range(16):
				var direction := away.rotated(TAU * float(direction_index) / 16.0)
				var candidate_self := _clamp_to_arena(global_position + direction * step)
				var candidate_other := _clamp_to_arena(other.global_position - direction * step)
				if not test_move(global_transform, candidate_self - global_position) \
						and not other_body.test_move(other_body.global_transform, candidate_other - other_body.global_position):
					candidate_gap = candidate_self.distance_to(candidate_other)
					if candidate_gap > best_gap:
						best_gap = candidate_gap
						best_self = candidate_self
						best_other = candidate_other
				candidate_self = _clamp_to_arena(global_position + direction * (step * 2.0))
				candidate_gap = candidate_self.distance_to(other.global_position)
				if candidate_gap > best_gap and not test_move(global_transform, candidate_self - global_position):
					best_gap = candidate_gap
					best_self = candidate_self
					best_other = other.global_position
				candidate_other = _clamp_to_arena(other.global_position - direction * (step * 2.0))
				candidate_gap = global_position.distance_to(candidate_other)
				if candidate_gap > best_gap and not other_body.test_move(other_body.global_transform, candidate_other - other_body.global_position):
					best_gap = candidate_gap
					best_self = global_position
					best_other = candidate_other
			if best_gap > distance:
				global_position = best_self
				other.global_position = best_other

func _horizontal_separation_direction(direction: Vector2) -> Vector2:
	var horizontal := Vector2(direction.x, direction.y * 0.28)
	if horizontal.length_squared() <= 0.0001:
		return Vector2(signf(direction.x), 0.0)
	return horizontal.normalized()

func _clamp_to_arena(position: Vector2) -> Vector2:
	return Vector2(
		clampf(position.x, arena_bounds.position.x + BODY_HALF_WIDTH, arena_bounds.end.x - BODY_HALF_WIDTH),
		clampf(position.y, arena_bounds.position.y - _silhouette_top_offset, arena_bounds.end.y - _silhouette_bottom_offset)
	)

func _find_player() -> CharacterBody2D:
	var grouped := get_tree().get_first_node_in_group("player") as CharacterBody2D
	if grouped != null:
		return grouped
	return _find_named_player(get_tree().root)

func _find_named_player(node: Node) -> CharacterBody2D:
	if node is CharacterBody2D and node.name == "Player":
		return node as CharacterBody2D
	for child in node.get_children():
		var found := _find_named_player(child)
		if found != null:
			return found
	return null

func receive_hit(hit: Dictionary) -> void:
	if health <= 0:
		return
	if not hit.has_all(["damage", "direction", "knockback", "hit_stun", "attack_stage"]):
		return
	raider_hit.emit(int(hit["attack_stage"]))
	health = maxi(0, health - maxi(0, int(hit["damage"])))
	if health == 0:
		raider_ko.emit()
		velocity = Vector2.ZERO
		hitstun_remaining = 0.0
		collision_layer = 0
		collision_mask = 0
		receive_area.collision_layer = 0
		receive_area.monitorable = false
		_cancel_attack()
		hit_flash_remaining = 0.14
		body_visual.modulate = HIT_COLOR
		return
	var direction: Vector2 = hit["direction"]
	if direction.length_squared() > 0.0:
		direction = direction.normalized()
	else:
		direction = facing_direction
	hit_reaction_direction = direction
	# Stages 1/2/3 cover a regular hit through progressively heavier skills.
	# Keep damage and physics impulses authored by the attack, while exposing an
	# independent strength value for a clearly graded visual reaction.
	var stage := clampi(int(hit["attack_stage"]), 1, 3)
	hit_reaction_strength = [0.72, 1.0, 1.32][stage - 1]
	velocity = direction * maxf(0.0, float(hit["knockback"]))
	hitstun_remaining = maxf(hitstun_remaining, maxf(0.0, float(hit["hit_stun"])))
	_cancel_attack()
	hit_flash_remaining = 0.14 + 0.025 * float(stage - 1)
	body_visual.modulate = HIT_COLOR

func _update_hit_flash(delta: float) -> void:
	if hit_flash_remaining > 0.0:
		hit_flash_remaining = maxf(0.0, hit_flash_remaining - delta)
		if hit_flash_remaining == 0.0:
			body_visual.modulate = KNOCKED_OUT_COLOR if health <= 0 else Color.WHITE

func _apply_arena_bounds() -> void:
	global_position.x = clampf(global_position.x, arena_bounds.position.x + BODY_HALF_WIDTH, arena_bounds.end.x - BODY_HALF_WIDTH)
	global_position.y = clampf(global_position.y, arena_bounds.position.y - _silhouette_top_offset, arena_bounds.end.y - _silhouette_bottom_offset)
	if is_on_wall():
		velocity = Vector2.ZERO
