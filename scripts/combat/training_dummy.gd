extends CharacterBody2D
"""Stationary practice target that implements the shared Dictionary hit contract."""

@export var arena_bounds: Rect2 = Rect2(Vector2(160, 100), Vector2(1600, 880))
@export var return_delay: float = 0.8
@export var return_speed: float = 240.0
@export var flash_duration: float = 0.14
@export var max_health: float = 1000.0

@onready var body_visual: Polygon2D = $VisualRoot/Body

var home_position: Vector2
var health: float
var last_attack_stage: int = 0
var last_hit: Dictionary = {}
var hit_stun_remaining: float = 0.0
var flash_remaining: float = 0.0
var return_delay_remaining: float = 0.0

const BODY_HALF_WIDTH := 18.0
const BODY_TOP_OFFSET := -48.0
const BODY_BOTTOM_OFFSET := 2.0
const BASE_COLOR := Color(0.72, 0.57, 0.29, 1.0)
const HIT_COLOR := Color(1.0, 0.88, 0.72, 1.0)

func _ready() -> void:
	add_to_group("hit_receivers")
	collision_layer = 2
	home_position = global_position
	health = max_health

func _physics_process(delta: float) -> void:
	if flash_remaining > 0.0:
		flash_remaining = maxf(0.0, flash_remaining - delta)
		body_visual.color = HIT_COLOR if flash_remaining > 0.0 else BASE_COLOR

	if hit_stun_remaining > 0.0:
		hit_stun_remaining = maxf(0.0, hit_stun_remaining - delta)
		move_and_slide()
		if hit_stun_remaining == 0.0:
			velocity = Vector2.ZERO
		_apply_arena_bounds()
		return

	if return_delay_remaining > 0.0:
		return_delay_remaining = maxf(0.0, return_delay_remaining - delta)
		velocity = Vector2.ZERO
		return

	var to_home := home_position - global_position
	if to_home.length_squared() > 1.0:
		velocity = to_home.normalized() * minf(return_speed, to_home.length() / maxf(delta, 0.001))
		move_and_slide()
	else:
		global_position = home_position
		velocity = Vector2.ZERO
	_apply_arena_bounds()

func receive_hit(hit_data: Dictionary) -> void:
	last_hit = hit_data.duplicate(true)
	health = maxf(0.0, health - maxf(0.0, float(hit_data.get("damage", 0.0))))
	last_attack_stage = int(hit_data.get("attack_stage", 0))
	var direction: Vector2 = hit_data.get("direction", Vector2.ZERO)
	if direction.length_squared() > 0.0:
		direction = direction.normalized()
	var knockback := maxf(0.0, float(hit_data.get("knockback", 0.0)))
	velocity = direction * knockback
	hit_stun_remaining = maxf(0.0, float(hit_data.get("hit_stun", 0.0)))
	flash_remaining = maxf(0.0, flash_duration)
	return_delay_remaining = maxf(return_delay, hit_stun_remaining)
	body_visual.color = HIT_COLOR

func _apply_arena_bounds() -> void:
	global_position.x = clampf(global_position.x, arena_bounds.position.x + BODY_HALF_WIDTH, arena_bounds.end.x - BODY_HALF_WIDTH)
	global_position.y = clampf(global_position.y, arena_bounds.position.y - BODY_TOP_OFFSET, arena_bounds.end.y - BODY_BOTTOM_OFFSET)
	if is_on_wall():
		velocity = Vector2.ZERO
