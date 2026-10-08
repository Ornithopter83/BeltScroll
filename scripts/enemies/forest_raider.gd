extends CharacterBody2D
"""A light forest enemy that pursues, attacks in its depth lane, and can be staggered."""

@export var walk_speed: float = 118.0
@export var arena_bounds: Rect2 = Rect2(Vector2(160, 100), Vector2(1600, 880))
@export var max_health: int = 3
@export var notice_range: float = 560.0
@export var attack_range: float = 72.0
@export var attack_depth_tolerance: float = 34.0
@export var separation_radius: float = 42.0
@export var separation_strength: float = 92.0
@export var windup_duration: float = 0.34
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

const BODY_HALF_WIDTH := 15.0
const BODY_TOP_OFFSET := -43.0
const BODY_BOTTOM_OFFSET := 2.0
const MIN_ATTACK_SEPARATION := 36.0
const HIT_COLOR := Color(1.0, 0.78, 0.58, 1.0)
const KNOCKED_OUT_COLOR := Color(0.62, 0.62, 0.62, 0.78)

var health: int
var attack_phase := "idle"
var attack_phase_remaining := 0.0
var hitstun_remaining := 0.0
var hit_flash_remaining := 0.0
var facing_direction := Vector2.LEFT
var _hit_targets: Dictionary = {}

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

func _physics_process(delta: float) -> void:
	_update_hit_flash(delta)
	if health <= 0:
		velocity = Vector2.ZERO
		_cancel_attack()
		return
	var player := _find_player()
	if hitstun_remaining > 0.0:
		hitstun_remaining = maxf(0.0, hitstun_remaining - delta)
		velocity = velocity.move_toward(Vector2.ZERO, 760.0 * delta)
		move_and_slide()
		_apply_arena_bounds()
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
			var close_raider := _has_close_raider()
			if offset.length() <= attack_range and in_depth_lane and not close_raider:
				_begin_attack()
			else:
				var desired := offset.normalized() * walk_speed
				velocity = _separation_velocity() if close_raider else desired
				if absf(offset.x) < attack_range * 0.82 and not in_depth_lane:
					velocity.x = 0.0
				move_and_slide()
				_apply_arena_bounds()
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

func _begin_attack() -> void:
	attack_phase = "windup"
	attack_phase_remaining = windup_duration
	attack_area.position = facing_direction * (attack_range * 0.57) + Vector2(0.0, -20.0)
	attack_flash.position.x = facing_direction.x * 25.0
	attack_flash.visible = true
	attack_area.monitoring = false
	_hit_targets.clear()

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

func _separation_velocity() -> Vector2:
	var separation := Vector2.ZERO
	for candidate in get_tree().get_nodes_in_group("forest_raiders"):
		var other := candidate as Node2D
		if other == self or not is_instance_valid(other):
			continue
		if int(other.get("health")) <= 0:
			continue
		var away: Vector2 = global_position - other.global_position
		var distance: float = away.length()
		if distance < separation_radius:
			if distance <= 0.001:
				away = _coincident_separation_direction(other)
			else:
				away /= distance
			var player := _find_player()
			if player != null:
				var toward_player := (player.global_position - global_position).normalized()
				if away.dot(toward_player) > 0.65:
					away = Vector2(-toward_player.y, toward_player.x)
					if get_instance_id() > other.get_instance_id():
						away = -away
			separation += away * ((separation_radius - distance) / separation_radius)
	return separation * separation_strength

func _has_close_raider() -> bool:
	for candidate in get_tree().get_nodes_in_group("forest_raiders"):
		var other := candidate as Node2D
		if other == self or not is_instance_valid(other):
			continue
		if int(other.get("health")) <= 0:
			continue
		if global_position.distance_to(other.global_position) < minf(separation_radius, MIN_ATTACK_SEPARATION):
			return true
	return false

func _coincident_separation_direction(other: Node2D) -> Vector2:
	var self_id := get_instance_id()
	var other_id := other.get_instance_id()
	var lower_id := mini(self_id, other_id)
	var higher_id := maxi(self_id, other_id)
	var pair_seed := hash("%d:%d" % [lower_id, higher_id]) & 0x7fffffff
	var angle := float(pair_seed) / 2147483647.0 * TAU
	var direction := Vector2(cos(angle), sin(angle))
	return direction if self_id == lower_id else -direction

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
	health = maxi(0, health - maxi(0, int(hit["damage"])))
	if health == 0:
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
	velocity = direction * maxf(0.0, float(hit["knockback"]))
	hitstun_remaining = maxf(hitstun_remaining, maxf(0.0, float(hit["hit_stun"])))
	_cancel_attack()
	hit_flash_remaining = 0.14
	body_visual.modulate = HIT_COLOR

func _update_hit_flash(delta: float) -> void:
	if hit_flash_remaining > 0.0:
		hit_flash_remaining = maxf(0.0, hit_flash_remaining - delta)
		if hit_flash_remaining == 0.0:
			body_visual.modulate = KNOCKED_OUT_COLOR if health <= 0 else Color.WHITE

func _apply_arena_bounds() -> void:
	global_position.x = clampf(global_position.x, arena_bounds.position.x + BODY_HALF_WIDTH, arena_bounds.end.x - BODY_HALF_WIDTH)
	global_position.y = clampf(global_position.y, arena_bounds.position.y - BODY_TOP_OFFSET, arena_bounds.end.y - BODY_BOTTOM_OFFSET)
	if is_on_wall():
		velocity = Vector2.ZERO
