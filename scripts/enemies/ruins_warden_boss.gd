extends CharacterBody2D
"""A heavyweight arena boss with readable melee and ground-slam attacks."""

signal boss_ko
signal boss_hit(stage: int)

@export var max_health: int = 20
@export var display_name: String = "Ruins Warden"
@export var walk_speed: float = 76.0
@export var attack_damage: int = 2
@export var attack_knockback: float = 430.0
@export var attack_hit_stun: float = 0.34
@export var arena_bounds: Rect2 = Rect2(Vector2(160, 100), Vector2(5440, 880))

const BODY_HALF_WIDTH := 36.0
const BODY_TOP_OFFSET := -172.0
const BODY_BOTTOM_OFFSET := 0.0
const SLASH := "slash"
const SLAM := "slam"

@onready var visual_root: Node2D = $VisualRoot
@onready var attack_area: Area2D = $AttackArea
@onready var attack_shape: CollisionShape2D = $AttackArea/CollisionShape2D
@onready var receive_area: Area2D = $ReceiveArea
@onready var attack_telegraph: Polygon2D = $AttackTelegraph
@onready var slam_telegraph: Polygon2D = $SlamTelegraph
@onready var health_bar: ProgressBar = $HealthBar

var health: int
var combat_active := false
var attack_phase := "idle"
var attack_kind := SLASH
var attack_phase_remaining := 0.0
var hitstun_remaining := 0.0
var facing_direction := Vector2.LEFT
var _hit_targets: Dictionary = {}
var _ko_elapsed := 0.0
var _flash_remaining := 0.0

func _ready() -> void:
	add_to_group("hit_receivers")
	add_to_group("boss_units")
	add_to_group("ruins_warden_bosses")
	health = max_health
	health_bar.max_value = max_health
	health_bar.value = health
	attack_area.collision_layer = 0
	attack_area.collision_mask = 1
	attack_area.monitoring = false
	receive_area.collision_layer = 2
	receive_area.monitorable = true
	set_combat_active(false)

func set_combat_active(active: bool) -> void:
	combat_active = active and health > 0
	visible = true
	set_physics_process(combat_active or health <= 0)
	if not combat_active:
		velocity = Vector2.ZERO
		_cancel_attack()
		collision_layer = 0
		collision_mask = 0
		receive_area.monitoring = false
		receive_area.monitorable = false
	else:
		collision_layer = 2
		collision_mask = 1
		receive_area.monitoring = true
		receive_area.monitorable = true

func _physics_process(delta: float) -> void:
	if _flash_remaining > 0.0:
		_flash_remaining = maxf(0.0, _flash_remaining - delta)
		if _flash_remaining == 0.0 and health > 0:
			visual_root.modulate = Color.WHITE
	if health <= 0:
		_ko_elapsed += delta
		visual_root.rotation = lerpf(visual_root.rotation, -1.15, minf(1.0, delta * 5.0))
		visual_root.scale = visual_root.scale.lerp(Vector2(0.82, 0.56), minf(1.0, delta * 2.8))
		return
	if not combat_active:
		return
	if hitstun_remaining > 0.0:
		hitstun_remaining = maxf(0.0, hitstun_remaining - delta)
		velocity = velocity.move_toward(Vector2.ZERO, 520.0 * delta)
		move_and_slide()
		_apply_arena_bounds()
		return
	var player := _find_player()
	if player == null:
		velocity = Vector2.ZERO
		return
	var offset := player.global_position - global_position
	if absf(offset.x) > 1.0:
		facing_direction = Vector2(signf(offset.x), 0.0)
		visual_root.scale.x = absf(visual_root.scale.x) * (-1.0 if facing_direction.x < 0.0 else 1.0)
	if attack_phase == "idle":
		if absf(offset.y) <= 52.0 and absf(offset.x) <= 214.0:
			_begin_attack(SLASH if absf(offset.x) <= 150.0 else SLAM)
		else:
			velocity = Vector2(signf(offset.x) * walk_speed, clampf(offset.y, -1.0, 1.0) * walk_speed * 0.3)
			move_and_slide()
			_apply_arena_bounds()
			return
	elif attack_phase == "windup":
		velocity = Vector2.ZERO
		attack_phase_remaining -= delta
		if attack_phase_remaining <= 0.0:
			attack_phase = "active"
			attack_phase_remaining = 0.24 if attack_kind == SLAM else 0.18
			attack_telegraph.visible = false
			slam_telegraph.visible = false
			attack_area.monitoring = true
			_check_attack_targets()
	elif attack_phase == "active":
		velocity = Vector2.ZERO
		_check_attack_targets()
		attack_phase_remaining -= delta
		if attack_phase_remaining <= 0.0:
			attack_area.monitoring = false
			attack_phase = "recovery"
			attack_phase_remaining = 0.82
	elif attack_phase == "recovery":
		velocity = Vector2.ZERO
		attack_phase_remaining -= delta
		if attack_phase_remaining <= 0.0:
			attack_phase = "idle"
	move_and_slide()
	_apply_arena_bounds()

func _begin_attack(kind: String) -> void:
	attack_kind = kind
	attack_phase = "windup"
	attack_phase_remaining = 0.82 if kind == SLASH else 1.12
	_hit_targets.clear()
	attack_area.monitoring = false
	if kind == SLASH:
		attack_shape.shape = CircleShape2D.new()
		(attack_shape.shape as CircleShape2D).radius = 67.0
		attack_area.position = facing_direction * 86.0 + Vector2(0, -47)
		attack_telegraph.position = Vector2(facing_direction.x * 54.0, -2.0)
		attack_telegraph.scale.x = facing_direction.x
		attack_telegraph.visible = true
		slam_telegraph.visible = false
	else:
		attack_shape.shape = CircleShape2D.new()
		(attack_shape.shape as CircleShape2D).radius = 125.0
		attack_area.position = Vector2(0, -18)
		slam_telegraph.visible = true
		attack_telegraph.visible = false

func _check_attack_targets() -> void:
	for target in attack_area.get_overlapping_bodies():
		_apply_attack_to(target)
	for target in attack_area.get_overlapping_areas():
		if target is Area2D and target.get_parent() is CharacterBody2D:
			_apply_attack_to(target.get_parent())
	var player := _find_player()
	if player != null and attack_area.global_position.distance_to(player.global_position) <= (125.0 if attack_kind == SLAM else 112.0):
		if absf(player.global_position.y - global_position.y) <= (105.0 if attack_kind == SLAM else 66.0):
			_apply_attack_to(player)

func _apply_attack_to(target: Node) -> void:
	if target == self or not target.is_in_group("hit_receivers") or not target.has_method("receive_hit"):
		return
	var target_2d := target as Node2D
	if target_2d == null:
		return
	var id := target.get_instance_id()
	if _hit_targets.has(id):
		return
	_hit_targets[id] = true
	var direction: Vector2 = (target_2d.global_position - global_position).normalized()
	if attack_kind == SLAM:
		direction = Vector2(direction.x, -0.35).normalized()
	target.call("receive_hit", {
		"damage": attack_damage,
		"direction": direction,
		"knockback": attack_knockback if attack_kind == SLAM else attack_knockback * 0.72,
		"hit_stun": attack_hit_stun,
		"attack_stage": 3 if attack_kind == SLAM else 2,
	})

func receive_hit(hit: Dictionary) -> void:
	if health <= 0 or not combat_active or not hit.has_all(["damage", "direction", "knockback", "hit_stun", "attack_stage"]):
		return
	var stage := clampi(int(hit.attack_stage), 1, 3)
	boss_hit.emit(stage)
	health = maxi(0, health - maxi(0, int(hit.damage)))
	health_bar.value = health
	_flash_remaining = 0.18
	visual_root.modulate = Color(1.0, 0.7, 0.55, 1.0)
	_cancel_attack()
	if health <= 0:
		combat_active = false
		velocity = Vector2.ZERO
		collision_layer = 0
		collision_mask = 0
		receive_area.monitoring = false
		receive_area.monitorable = false
		set_physics_process(true)
		boss_ko.emit()
		return
	var direction: Vector2 = hit.direction
	if direction.length_squared() == 0.0:
		direction = facing_direction
	velocity = direction.normalized() * maxf(0.0, float(hit.knockback)) * 0.45
	hitstun_remaining = maxf(hitstun_remaining, maxf(0.0, float(hit.hit_stun)))

func _cancel_attack() -> void:
	attack_phase = "idle"
	attack_phase_remaining = 0.0
	attack_area.monitoring = false
	attack_telegraph.visible = false
	slam_telegraph.visible = false

func _apply_arena_bounds() -> void:
	global_position.x = clampf(global_position.x, arena_bounds.position.x + BODY_HALF_WIDTH, arena_bounds.end.x - BODY_HALF_WIDTH)
	global_position.y = clampf(global_position.y, arena_bounds.position.y - BODY_TOP_OFFSET, arena_bounds.end.y - BODY_BOTTOM_OFFSET)

func _find_player() -> CharacterBody2D:
	var grouped := get_tree().get_first_node_in_group("player") as CharacterBody2D
	if is_instance_valid(grouped):
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
