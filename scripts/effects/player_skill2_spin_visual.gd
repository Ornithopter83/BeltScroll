extends Node2D
"""Temporary procedural Num5 spin telegraph and contact VFX."""

const STARTUP_DURATION := 0.22
const ACTIVE_DURATION := 0.18
const RECOVERY_DURATION := 0.55
const VIOLET := Color("#e8a4ff")
const PINK := Color("#ff76bc")
const WHITE := Color("#fff4ff")
const IMPACT := Color("#ffd58a")
const HIT_FLASH_DURATION := 0.20

var _player: CharacterBody2D
var _hit_flash_remaining := 0.0

func _ready() -> void:
	_player = get_parent() as CharacterBody2D
	z_index = 4
	visible = false

func _process(delta: float) -> void:
	if not is_instance_valid(_player):
		clear_effects()
		return
	var phase := str(_player.get("skill_phase"))
	var interrupted: bool = _player.get("is_ko") == true or float(_player.get("hitstun_remaining")) > 0.0
	var valid_phase := int(_player.get("skill_id")) == 2 and phase in ["startup", "active", "recovery"]
	if interrupted or not valid_phase:
		clear_effects()
		return
	_hit_flash_remaining = maxf(0.0, _hit_flash_remaining - maxf(delta, 0.0))
	visible = true
	queue_redraw()

func on_skill_hit(skill_id: int) -> void:
	if skill_id != 2 or not is_instance_valid(_player):
		return
	var actual_hitbox := _player.get_node_or_null("Hitboxes/Skill2Hitbox") as Area2D
	if actual_hitbox == null or not actual_hitbox.monitoring:
		return
	_hit_flash_remaining = HIT_FLASH_DURATION
	queue_redraw()

func clear_effects(_unused: Variant = null) -> void:
	_hit_flash_remaining = 0.0
	visible = false
	queue_redraw()

func _draw() -> void:
	if not visible or not is_instance_valid(_player):
		return
	var phase := str(_player.get("skill_phase"))
	var facing := -1.0 if float(_player.get("facing_direction").x) < 0.0 else 1.0
	var duration := STARTUP_DURATION if phase == "startup" else (ACTIVE_DURATION if phase == "active" else RECOVERY_DURATION)
	var progress := clampf((duration - maxf(0.0, float(_player.get("skill_phase_remaining")))) / duration, 0.0, 1.0)
	match phase:
		"startup":
			_draw_startup(facing, progress)
		"active":
			_draw_active(facing, progress)
		"recovery":
			_draw_recovery(facing, progress)
	if _hit_flash_remaining > 0.0:
		_draw_contact_impact()

func _draw_startup(facing: float, progress: float) -> void:
	var load := _smooth(progress)
	var center := Vector2(0.0, -205.0)
	var radius := 44.0 + 18.0 * load
	_draw_arc(center, radius, -facing * 0.18 * PI, facing * (0.30 + 0.72 * load) * PI, Color(VIOLET, 0.30 + load * 0.48), 3.0)
	_draw_arc(center, radius - 9.0, -facing * 0.13 * PI, facing * 0.15 * PI, Color(WHITE, 0.22 + load * 0.30), 1.5)
	var tip_angle := facing * (0.30 + 0.72 * load) * PI
	var tip := center + Vector2(cos(tip_angle), sin(tip_angle)) * radius
	var tangent := Vector2(-sin(tip_angle), cos(tip_angle)) * facing
	draw_line(tip - tangent * 8.0, tip + tangent * 8.0, Color(PINK, 0.72), 2.5, true)
	# Circular ground cue contrasts with Num4's paired horizontal dash streaks.
	draw_arc(Vector2(0.0, -8.0), 28.0 + 10.0 * load, 0.0, TAU, 28, Color(VIOLET, 0.22 + load * 0.35), 2.0, true)

func _draw_active(facing: float, progress: float) -> void:
	var center := Vector2(0.0, -205.0)
	var radius := 82.0
	var sweep := lerpf(0.40 * PI, 1.48 * PI, _ease_out(progress))
	var rotation := facing * (0.15 * PI + progress * 0.95 * PI)
	_draw_arc(center, radius + 9.0, rotation - facing * sweep * 0.82, rotation, Color(VIOLET, 0.24), 2.2)
	_draw_arc(center, radius, rotation - facing * sweep, rotation, Color(PINK, 0.86), 5.0)
	_draw_arc(center, radius - 8.0, rotation - facing * sweep * 0.62, rotation, Color(WHITE, 0.74), 1.8)
	var tip := center + Vector2(cos(rotation), sin(rotation)) * radius
	var tangent := Vector2(-sin(rotation), cos(rotation)) * facing
	draw_line(tip - tangent * 10.0, tip + tangent * 10.0, Color(WHITE, 0.95), 2.8, true)
	# Tangent knuckles and a short cuff read as a rotating backfist, while the
	# broad arc continues to communicate the radial hitbox's circular coverage.
	var fist_center := tip + tangent * 5.0
	draw_circle(fist_center, 6.5, Color(WHITE, 0.92))
	draw_line(fist_center - tangent * 15.0, fist_center - tangent * 7.0, Color(PINK, 0.98), 4.0, true)
	draw_line(fist_center - tangent * 11.0 + Vector2(0.0, -3.0), fist_center - tangent * 5.0 + Vector2(0.0, -3.0), Color(WHITE, 0.82), 1.4, true)
	# Rotating ground ring makes the radial axis legible from a side-on silhouette.
	draw_arc(Vector2(0.0, -7.0), 48.0 + 12.0 * sin(progress * PI), -facing * 0.15 * PI, facing * 1.85 * PI, 32, Color(VIOLET, 0.42), 2.8, true)

func _draw_recovery(facing: float, progress: float) -> void:
	var ease := _smooth(progress)
	var fade := 1.0 - ease
	var center := Vector2(0.0, -205.0)
	# Counter-rotating short arcs visibly slow and return toward the ready axis.
	var unwind := facing * (1.10 - ease * 0.88) * PI
	_draw_arc(center, 72.0 - 12.0 * ease, unwind - facing * (0.84 - ease * 0.50) * PI, unwind, Color(PINK, 0.70 * fade), 3.8 * fade + 0.5)
	_draw_arc(center, 59.0 - 10.0 * ease, unwind - facing * 0.42 * PI, unwind, Color(WHITE, 0.48 * fade), 1.8 * fade + 0.4)
	var ring_radius := 22.0 + 38.0 * ease
	draw_arc(Vector2(0.0, -7.0), ring_radius, 0.0, TAU, 32, Color(VIOLET, 0.54 * fade), 2.5 * fade + 0.35, true)
	draw_arc(Vector2(0.0, -7.0), ring_radius + 7.0, -facing * 0.12 * PI, facing * 1.35 * PI, 24, Color(PINK, 0.25 * fade), 1.5 * fade + 0.3, true)

func _draw_contact_impact() -> void:
	var fade := clampf(_hit_flash_remaining / HIT_FLASH_DURATION, 0.0, 1.0)
	var progress := 1.0 - fade
	var center := Vector2(0.0, -205.0)
	var radius := 18.0 + progress * 37.0
	draw_arc(center, radius, 0.0, TAU, 32, Color(IMPACT, fade * 0.95), 3.5 * fade + 0.5, true)
	draw_arc(center, radius * 0.68, 0.0, TAU, 28, Color(WHITE, fade * 0.72), 1.7 * fade + 0.4, true)
	for index in range(8):
		var angle := TAU * float(index) / 8.0
		var direction := Vector2(cos(angle), sin(angle))
		draw_line(center + direction * (radius + 3.0), center + direction * (radius + 10.0), Color(IMPACT, fade), 2.0, true)

func _draw_arc(center: Vector2, radius: float, start_angle: float, end_angle: float, color: Color, width: float) -> void:
	var points := PackedVector2Array()
	var segment_count := 28
	for index in range(segment_count + 1):
		var ratio := float(index) / float(segment_count)
		var angle := lerpf(start_angle, end_angle, ratio)
		points.append(center + Vector2(cos(angle), sin(angle)) * radius)
	draw_polyline(points, color, width, true)

func _smooth(value: float) -> float:
	var t := clampf(value, 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)

func _ease_out(value: float) -> float:
	var t := clampf(value, 0.0, 1.0)
	return 1.0 - (1.0 - t) * (1.0 - t)
