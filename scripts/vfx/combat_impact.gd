extends Node2D
"""Compact directional hit burst, timed against the opening of hit-stun."""

const MAX_SCREEN_RADIUS := 44.0
const BASE_COLORS := [
	Color(1.0, 0.94, 0.72, 1.0),
	Color(1.0, 0.70, 0.36, 1.0),
	Color(1.0, 0.40, 0.22, 1.0),
]
const SKILL_COLORS := [Color(0.35, 0.94, 1.0, 1.0), Color(0.88, 0.48, 1.0, 1.0)]
const STAGE_RADII := [16.0, 24.0, 35.0]
const STAGE_WIDTHS := [2.2, 3.2, 4.5]
const STAGE_STREAKS := [11.0, 19.0, 29.0]
const STAGE_SHARDS := [2, 4, 6]
const STAGE_LIFETIMES := [0.105, 0.14, 0.19]

var attack_stage: int = 1
var skill_id: int = 0
var attack_direction := Vector2.DOWN
var lifetime: float = STAGE_LIFETIMES[0]
var arc_radius: float = STAGE_RADII[0]
var arc_width: float = STAGE_WIDTHS[0]
var streak_length: float = STAGE_STREAKS[0]
var shard_count: int = STAGE_SHARDS[0]
var impact_color := BASE_COLORS[0]
var hit_stun_duration := 0.2
var elapsed_real: float = 0.0
var _start_ticks_usec: int = 0
var _phase_offset := 0.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	z_index = 3
	add_to_group("combat_impacts")
	_start_ticks_usec = Time.get_ticks_usec()
	queue_redraw()

func configure(stage: int, direction: Vector2, selected_skill: int = 0, hit_stun: float = 0.2) -> void:
	attack_stage = clampi(stage, 1, 3)
	skill_id = clampi(selected_skill, 0, 2)
	attack_direction = direction.normalized() if direction.length_squared() > 0.0001 else Vector2.DOWN
	rotation = attack_direction.angle() + PI * 0.5
	_phase_offset = float((attack_stage * 2 + skill_id) % 7) * 0.16
	var index := attack_stage - 1
	arc_radius = minf(STAGE_RADII[index], MAX_SCREEN_RADIUS)
	arc_width = STAGE_WIDTHS[index]
	streak_length = STAGE_STREAKS[index]
	shard_count = STAGE_SHARDS[index]
	impact_color = BASE_COLORS[index]
	# The burst resolves in the first slice of target hit-stun, so it reads as
	# the cause of the recoil instead of a late, detached decoration.
	lifetime = minf(STAGE_LIFETIMES[index], maxf(0.075, hit_stun * 0.72))
	hit_stun_duration = maxf(hit_stun, 0.001)
	if skill_id == 1:
		impact_color = SKILL_COLORS[0]
		arc_radius = minf(42.0, MAX_SCREEN_RADIUS)
		arc_width = 5.0
		streak_length = 33.0
		shard_count = 7
		lifetime = minf(0.22, maxf(0.10, hit_stun_duration * 0.60))
	elif skill_id == 2:
		impact_color = SKILL_COLORS[1]
		arc_radius = minf(38.0, MAX_SCREEN_RADIUS)
		arc_width = 4.2
		streak_length = 25.0
		shard_count = 8
		lifetime = minf(0.19, maxf(0.09, hit_stun_duration * 0.62))
	queue_redraw()

func streak_direction_local() -> Vector2:
	return Vector2.UP

func streak_perpendicular_local() -> Vector2:
	return streak_direction_local().orthogonal()

func visual_state_at(progress: float) -> Dictionary:
	var normalized_progress := clampf(progress, 0.0, 1.0)
	var fade := 1.0 - normalized_progress
	var radius := minf(arc_radius * (0.52 + normalized_progress * 0.55), MAX_SCREEN_RADIUS)
	return {
		"progress": normalized_progress,
		"fade": fade,
		"radius": radius,
		"streak_length": fade * streak_length,
		"shard_travel": normalized_progress * (9.0 + float(shard_count) * 1.1),
		"arc_alpha": fade * (0.82 if attack_stage == 1 and skill_id == 0 else 1.0),
	}

func _process(_delta: float) -> void:
	if not is_instance_valid(get_parent()) or get_parent().is_queued_for_deletion():
		queue_free()
		return
	var receiver := get_parent()
	if _has_property(receiver, "is_ko") and bool(receiver.get("is_ko")):
		queue_free()
		return
	if _has_property(receiver, "health") and int(receiver.get("health")) <= 0:
		queue_free()
		return
	elapsed_real = float(Time.get_ticks_usec() - _start_ticks_usec) / 1000000.0
	if elapsed_real >= lifetime:
		queue_free()
		return
	queue_redraw()

func _has_property(object: Object, property_name: StringName) -> bool:
	for property_info in object.get_property_list():
		if StringName(property_info["name"]) == property_name:
			return true
	return false

func _draw() -> void:
	var state := visual_state_at(elapsed_real / maxf(lifetime, 0.001))
	var progress: float = state["progress"]
	var fade: float = state["fade"]
	var radius: float = state["radius"]
	var arc_color := impact_color
	arc_color.a *= float(state["arc_alpha"])
	var sweep := TAU * 0.30 if skill_id == 2 else PI * (0.54 + float(attack_stage) * 0.04)
	var start_angle := -PI * 0.73 + _phase_offset
	if attack_stage == 3 and skill_id == 0:
		start_angle = PI * 0.12 + _phase_offset
	draw_arc(Vector2.ZERO, radius, start_angle, start_angle + sweep, 24, arc_color, arc_width * fade, true)

	# A small contact flash keeps the effect visibly anchored to the hit point.
	var core_radius := maxf(1.0, (4.0 + float(skill_id) * 1.5 + float(attack_stage - 1)) * (1.0 - progress * 0.65))
	draw_circle(Vector2.ZERO, core_radius, Color(1.0, 1.0, 0.9, fade * 0.92))

	var direction := streak_direction_local()
	var perpendicular := streak_perpendicular_local()
	var trail_scale: float = state["streak_length"]
	var streak_count := 2 if attack_stage == 1 and skill_id == 0 else 3
	for index in range(streak_count):
		var offset := float(index) - float(streak_count - 1) * 0.5
		var start := direction * (radius * (0.34 + absf(offset) * 0.08)) + perpendicular * offset * 4.0
		var finish := start - direction * trail_scale - perpendicular * offset * 1.8
		var streak_color := Color(1.0, 0.98, 0.9, fade * (0.82 if index == 0 else 0.54))
		draw_line(start, finish, streak_color, maxf(0.8, arc_width * (0.58 if index == 0 else 0.36) * fade), true)

	var shard_travel: float = state["shard_travel"]
	for index in range(shard_count):
		var angle := TAU * float(index) / float(shard_count) + _phase_offset
		var shard_direction := Vector2.RIGHT.rotated(angle)
		var tangent := shard_direction.orthogonal()
		var inner := shard_direction * (radius * 0.42 + shard_travel * 0.28)
		var outer := inner + shard_direction * (3.0 + float(attack_stage) * 1.7 + float(skill_id) * 1.5) + tangent * (2.0 + float(skill_id))
		var shard_color := impact_color
		shard_color.a = fade * (0.86 if index % 2 == 0 else 0.62)
		draw_line(inner, outer, shard_color, maxf(1.0, arc_width * 0.52 * fade), true)
