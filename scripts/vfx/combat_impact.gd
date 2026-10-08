extends Node2D
"""Short world-space impact arc and speed streak, animated in real time."""

const LIFETIMES := [0.12, 0.17, 0.23]
const ARC_RADII := [19.0, 30.0, 38.0]
const ARC_WIDTHS := [3.0, 4.0, 5.0]
const STREAK_LENGTHS := [15.0, 23.0, 31.0]
const MAX_SCREEN_RADIUS := 40.0

var attack_stage: int = 1
var attack_direction := Vector2.DOWN
var lifetime: float = LIFETIMES[0]
var arc_radius: float = ARC_RADII[0]
var arc_width: float = ARC_WIDTHS[0]
var streak_length: float = STREAK_LENGTHS[0]
var elapsed_real: float = 0.0
var _start_ticks_usec: int = 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("combat_impacts")
	_start_ticks_usec = Time.get_ticks_usec()
	queue_redraw()

func configure(stage: int, direction: Vector2) -> void:
	attack_stage = clampi(stage, 1, 3)
	attack_direction = direction.normalized() if direction.length_squared() > 0.0001 else Vector2.DOWN
	rotation = attack_direction.angle() + PI * 0.5
	var index := attack_stage - 1
	lifetime = LIFETIMES[index]
	arc_radius = minf(ARC_RADII[index], MAX_SCREEN_RADIUS)
	arc_width = ARC_WIDTHS[index]
	streak_length = STREAK_LENGTHS[index]
	queue_redraw()

func streak_direction_local() -> Vector2:
	return Vector2.UP

func streak_perpendicular_local() -> Vector2:
	return streak_direction_local().orthogonal()

func visual_state_at(progress: float) -> Dictionary:
	var normalized_progress := clampf(progress, 0.0, 1.0)
	var radius_scale := 0.72 + normalized_progress * 0.5
	return {
		"progress": normalized_progress,
		"fade": 1.0 - normalized_progress,
		"radius": minf(arc_radius * radius_scale, MAX_SCREEN_RADIUS),
		"streak_length": (1.0 - normalized_progress) * streak_length,
		"arc_alpha": (1.0 - normalized_progress) * (1.0 if attack_stage == 3 else 0.92),
	}

func _process(_delta: float) -> void:
	elapsed_real = float(Time.get_ticks_usec() - _start_ticks_usec) / 1000000.0
	if elapsed_real >= lifetime:
		queue_free()
		return
	queue_redraw()

func _draw() -> void:
	var state := visual_state_at(elapsed_real / maxf(lifetime, 0.001))
	var progress: float = state["progress"]
	var fade: float = state["fade"]
	var radius: float = state["radius"]
	var color := Color(1.0, 0.91, 0.63, fade * 0.92)
	var arc_start := -0.85 * PI
	var arc_end := -0.15 * PI
	if attack_stage == 2:
		arc_start = -0.98 * PI
		arc_end = -0.02 * PI
	elif attack_stage == 3:
		# Rising finisher: sweep climbs from low left to high right.
		arc_start = 0.65 * PI
		arc_end = 1.65 * PI
		color = Color(1.0, 0.79, 0.42, fade)
	draw_arc(Vector2.ZERO, radius, arc_start, arc_end, 24, color, arc_width * fade, true)

	var direction := streak_direction_local()
	var perpendicular := streak_perpendicular_local()
	var trail_scale: float = state["streak_length"]
	var streak_count := 2 if attack_stage == 1 else 3
	for index in range(streak_count):
		var offset := float(index) - float(streak_count - 1) * 0.5
		var start := direction * (radius * (0.38 + absf(offset) * 0.08)) + perpendicular * offset * 5.0
		var finish := start - direction * trail_scale - perpendicular * offset * 2.0
		var streak_color := Color(1.0, 0.98, 0.84, fade * (0.72 if index == 0 else 0.5))
		draw_line(start, finish, streak_color, maxf(1.0, arc_width * 0.55 * fade), true)
