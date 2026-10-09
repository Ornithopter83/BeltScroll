extends Node2D
"""Temporary procedural Num4 dash telegraph; no approved fist art is available."""

const STARTUP_DURATION := 0.16
const ACTIVE_DURATION := 0.12
const RECOVERY_DURATION := 0.42
const CYAN := Color("#a8f5ff")
const WHITE := Color("#f5fdff")
const GOLD := Color("#ffd27a")

var _player: CharacterBody2D
var _hit_flash_remaining := 0.0

func _ready() -> void:
	_player = get_parent() as CharacterBody2D
	z_index = 3
	queue_redraw()

func _process(delta: float) -> void:
	if not is_instance_valid(_player):
		visible = false
		return
	_hit_flash_remaining = maxf(0.0, _hit_flash_remaining - maxf(delta, 0.0))
	visible = _player.get("is_ko") != true and int(_player.get("skill_id")) == 1 and str(_player.get("skill_phase")) in ["startup", "active", "recovery"]
	queue_redraw()

func on_skill_hit(skill_id: int) -> void:
	if skill_id != 1:
		return
	_hit_flash_remaining = 0.18
	queue_redraw()

func _draw() -> void:
	if not visible or not is_instance_valid(_player):
		return
	var facing := -1.0 if float(_player.get("facing_direction").x) < 0.0 else 1.0
	var phase := str(_player.get("skill_phase"))
	var remaining := maxf(0.0, float(_player.get("skill_phase_remaining")))
	var duration := STARTUP_DURATION if phase == "startup" else (ACTIVE_DURATION if phase == "active" else RECOVERY_DURATION)
	var progress := clampf((duration - remaining) / duration, 0.0, 1.0)
	if phase == "startup":
		_draw_startup(facing, progress)
	elif phase == "active":
		_draw_active(facing, progress)
	elif phase == "recovery":
		_draw_recovery(facing, progress)
	if _hit_flash_remaining > 0.0:
		_draw_hit_pop(facing)

func _draw_startup(facing: float, progress: float) -> void:
	# A low, rearward load and paired ground streaks show weight moving forward.
	var load := _smooth(progress)
	var sweep := 20.0 + load * 26.0
	var alpha := 0.30 + load * 0.52
	draw_line(Vector2(-facing * 8.0, -10.0), Vector2(-facing * sweep, -10.0), Color(CYAN, alpha), 3.0, true)
	draw_line(Vector2(-facing * 5.0, -15.0), Vector2(-facing * (sweep - 10.0), -15.0), Color(WHITE, alpha * 0.62), 1.5, true)
	var fist := Vector2(facing * (24.0 + 5.0 * load), -126.0 + 8.0 * load)
	draw_arc(fist, 13.0 + 4.0 * load, -0.45, 0.45, 16, Color(CYAN, alpha), 2.0, true)
	draw_line(fist + Vector2(-facing * 12.0, 2.0), fist + Vector2(-facing * 28.0, 2.0), Color(CYAN, alpha * 0.8), 2.0, true)

func _draw_active(facing: float, progress: float) -> void:
	# Parallel, tapered strokes stay on a straight forward axis (unlike Num5's radial sweep).
	var lead := 42.0 + 34.0 * _ease_out(progress)
	var end_x := lead + 92.0
	var pulse := 0.78 + 0.22 * sin(progress * PI)
	var tip := Vector2(facing * end_x, -126.0)
	draw_line(Vector2(facing * 20.0, -126.0), tip, Color(CYAN, 0.72 * pulse), 5.0, true)
	draw_line(Vector2(facing * (lead - 8.0), -134.0), Vector2(facing * (end_x - 13.0), -134.0), Color(WHITE, 0.82 * pulse), 2.2, true)
	draw_line(Vector2(facing * (lead + 4.0), -117.0), Vector2(facing * (end_x - 24.0), -117.0), Color(CYAN, 0.60 * pulse), 2.0, true)
	# Two flat chevrons at the front communicate forward impact without a circle.
	for offset in [-10.0, 10.0]:
		var point := Vector2(facing * (end_x - 2.0), -126.0 + offset)
		draw_line(point + Vector2(-facing * 15.0, -8.0), point, Color(WHITE, 0.9 * pulse), 2.4, true)
		draw_line(point, point + Vector2(-facing * 15.0, 8.0), Color(CYAN, 0.9 * pulse), 2.4, true)
	draw_line(Vector2(-facing * 4.0, -8.0), Vector2(-facing * 30.0, -8.0), Color(CYAN, 0.7), 2.0, true)

func _draw_recovery(facing: float, progress: float) -> void:
	# The tapered path contracts toward the planted stance, then its rear arrow settles.
	var retract := 1.0 - _smooth(progress)
	var start_x := 22.0 + 38.0 * retract
	var end_x := 42.0 + 90.0 * retract
	var alpha := 0.18 + 0.56 * retract
	draw_line(Vector2(facing * start_x, -126.0), Vector2(facing * end_x, -126.0), Color(CYAN, alpha), 3.2, true)
	draw_line(Vector2(facing * (start_x + 5.0), -133.0), Vector2(facing * (end_x - 10.0), -133.0), Color(WHITE, alpha * 0.8), 1.6, true)
	var heel := Vector2(-facing * (8.0 + progress * 7.0), -10.0)
	draw_line(heel + Vector2(facing * 17.0, -4.0), heel, Color(CYAN, alpha), 2.6, true)
	draw_line(heel, heel + Vector2(facing * 17.0, 4.0), Color(CYAN, alpha), 2.6, true)

func _draw_hit_pop(facing: float) -> void:
	var fade := clampf(_hit_flash_remaining / 0.18, 0.0, 1.0)
	var stretch := 1.0 + (1.0 - fade) * 0.35
	var center := Vector2(facing * 146.0, -126.0)
	for index in range(5):
		var angle := -0.9 + float(index) * 0.45
		var direction := Vector2(cos(angle) * facing, sin(angle))
		draw_line(center + direction * 5.0, center + direction * (19.0 * stretch), Color(GOLD, fade), 2.8 if index == 2 else 2.0, true)
	draw_line(center + Vector2(-facing * 11.0, 0.0), center + Vector2(facing * 12.0, 0.0), Color(WHITE, fade), 2.0, true)

func _smooth(value: float) -> float:
	var t := clampf(value, 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)

func _ease_out(value: float) -> float:
	var t := clampf(value, 0.0, 1.0)
	return 1.0 - (1.0 - t) * (1.0 - t)
