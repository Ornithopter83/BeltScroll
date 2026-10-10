extends Node2D
"""Procedural straight-line Num4 dash telegraph and hitbox-aligned contact VFX."""

const STARTUP_DURATION := 0.16
const ACTIVE_DURATION := 0.12
const RECOVERY_DURATION := 0.42
const HIT_FLASH_DURATION := 0.16
const CYAN := Color("#9cefff")
const WHITE := Color("#f5fdff")
const GOLD := Color("#ffd27a")

var _player: CharacterBody2D
var _hit_flash_remaining := 0.0
var _hit_flash_position := Vector2.ZERO
var _facing := Vector2.RIGHT

func _ready() -> void:
	_player = get_parent() as CharacterBody2D
	z_index = 3
	visible = false
	if is_instance_valid(_player) and _player.has_signal("player_hit"):
		_player.player_hit.connect(clear_effects)
	if is_instance_valid(_player) and _player.has_signal("player_ko"):
		_player.player_ko.connect(clear_effects)

func _process(delta: float) -> void:
	if not is_instance_valid(_player):
		clear_effects()
		return
	var phase := str(_player.get("skill_phase"))
	var box := _skill1_hitbox()
	var valid_phase := int(_player.get("skill_id")) == 1 and phase in ["startup", "active", "recovery"]
	var interrupted: bool = _player.get("is_ko") == true or float(_player.get("hitstun_remaining")) > 0.0
	if interrupted or not valid_phase or box == null:
		clear_effects()
		return
	# The hitbox rotation is the authoritative direction. If facing flips, the
	# trail is redrawn on that axis immediately; no old-side particles persist.
	_facing = Vector2.RIGHT.rotated(box.rotation).normalized()
	_hit_flash_remaining = maxf(0.0, _hit_flash_remaining - maxf(delta, 0.0))
	visible = true
	queue_redraw()

func on_skill_hit(skill_id: int) -> void:
	if skill_id != 1 or not is_instance_valid(_player):
		return
	var box := _skill1_hitbox()
	if box == null or not box.monitoring or str(_player.get("skill_phase")) != "active":
		return
	_facing = Vector2.RIGHT.rotated(box.rotation).normalized()
	_hit_flash_position = _actual_contact_point(box)
	_hit_flash_remaining = HIT_FLASH_DURATION
	queue_redraw()

func clear_effects(_unused: Variant = null) -> void:
	_hit_flash_remaining = 0.0
	visible = false
	queue_redraw()

func _skill1_hitbox() -> Area2D:
	if not is_instance_valid(_player):
		return null
	return _player.get_node_or_null("Hitboxes/Skill1Hitbox") as Area2D

func _actual_contact_point(box: Area2D) -> Vector2:
	# skill_hit is emitted only after the real Skill1Hitbox overlap is accepted.
	# Prefer that receiver's position; fall back to the hitbox's real center.
	for body in box.get_overlapping_bodies():
		if body != _player and body.is_in_group("hit_receivers"):
			return to_local(body.global_position)
	return to_local(box.global_position)

func _draw() -> void:
	if not visible or not is_instance_valid(_player):
		return
	var phase := str(_player.get("skill_phase"))
	var remaining := maxf(0.0, float(_player.get("skill_phase_remaining")))
	var duration := STARTUP_DURATION if phase == "startup" else (ACTIVE_DURATION if phase == "active" else RECOVERY_DURATION)
	var progress := clampf((duration - remaining) / duration, 0.0, 1.0)
	var axis := _facing
	var side := Vector2(-axis.y, axis.x)
	match phase:
		"startup":
			_draw_startup(axis, side, progress)
		"active":
			_draw_active(axis, side, progress)
		"recovery":
			_draw_recovery(axis, side, progress)
	if _hit_flash_remaining > 0.0:
		_draw_hit_pop(axis, side)

func _draw_startup(axis: Vector2, side: Vector2, progress: float) -> void:
	# Compress behind the shoulder, then load forward along the future hitbox axis.
	var load := _smooth(progress)
	var base := axis * 15.0 + Vector2(0.0, -34.0)
	var reach := 32.0 + load * 26.0
	var alpha := 0.28 + load * 0.55
	draw_line(base - axis * 7.0, base - axis * reach, Color(CYAN, alpha), 4.0, true)
	draw_line(base + side * 7.0, base - axis * (reach - 12.0) + side * 7.0, Color(WHITE, alpha * 0.72), 1.8, true)
	draw_line(base - side * 7.0, base - axis * (reach - 17.0) - side * 7.0, Color(CYAN, alpha * 0.56), 1.5, true)
	var fist := axis * (30.0 + 8.0 * load) + Vector2(0.0, -126.0 + 5.0 * load)
	draw_line(fist - axis * (18.0 + 8.0 * load), fist, Color(WHITE, alpha), 3.0, true)
	draw_line(fist, fist + side * 8.0, Color(CYAN, alpha), 2.2, true)

func _draw_active(axis: Vector2, side: Vector2, progress: float) -> void:
	# The path ends at the leading edge of the real 108px Skill1Hitbox.
	var box := _skill1_hitbox()
	if box == null:
		return
	var shape_node := box.get_node_or_null("CollisionShape2D") as CollisionShape2D
	var rect := shape_node.shape as RectangleShape2D if shape_node != null else null
	var half_length := rect.size.x * 0.5 if rect != null else 54.0
	var center := to_local(box.global_position)
	var tip := center + axis * half_length
	var ease := _ease_out(progress)
	var fade := 0.86 - 0.26 * progress
	var trail_start := axis * 18.0 + Vector2(0.0, -34.0)
	var trail_mid := center - axis * (half_length * (0.46 - 0.12 * ease))
	draw_line(trail_start, tip, Color(CYAN, fade), 5.0, true)
	draw_line(trail_start + side * 8.0, tip - side * 8.0, Color(WHITE, fade * 0.84), 2.2, true)
	draw_line(trail_mid - side * 13.0, tip - side * 13.0, Color(CYAN, fade * 0.68), 2.0, true)
	# Flat parallel impact bars and an extended fist keep the silhouette linear.
	for offset: float in [-12.0, 12.0]:
		var point: Vector2 = tip + side * offset
		draw_line(point - axis * 17.0 - side * 7.0, point, Color(WHITE, fade), 2.5, true)
		draw_line(point, point - axis * 17.0 + side * 7.0, Color(CYAN, fade), 2.5, true)
	var fist_center := tip + axis * 5.0 + Vector2(0.0, -8.0)
	draw_circle(fist_center, 7.0, Color(WHITE, fade))
	draw_line(fist_center - axis * 16.0, fist_center - axis * 7.0, Color(CYAN, 1.0), 3.5, true)

func _draw_recovery(axis: Vector2, side: Vector2, progress: float) -> void:
	# A straight decelerating wake contracts toward the stance and floor anchor.
	var fade := 1.0 - _smooth(progress)
	var start := axis * (20.0 + 14.0 * fade) + Vector2(0.0, -34.0)
	var finish := axis * (54.0 + 102.0 * fade) + Vector2(0.0, -34.0)
	draw_line(start, finish, Color(CYAN, 0.12 + fade * 0.58), 3.4, true)
	draw_line(start + side * 7.0, finish - side * 7.0, Color(WHITE, fade * 0.58), 1.7, true)
	var heel := Vector2(0.0, -8.0) - axis * (12.0 + 8.0 * progress)
	draw_line(heel - axis * 5.0 + side * 8.0, heel, Color(CYAN, fade * 0.78), 2.6, true)
	draw_line(heel, heel - axis * 5.0 - side * 8.0, Color(CYAN, fade * 0.78), 2.6, true)

func _draw_hit_pop(axis: Vector2, side: Vector2) -> void:
	var fade := clampf(_hit_flash_remaining / HIT_FLASH_DURATION, 0.0, 1.0)
	var expansion := 1.0 + (1.0 - fade) * 0.42
	var center := _hit_flash_position
	# Short forward rays and cross bars indicate a forceful straight contact,
	# without the circular burst used by the Num5 spin skill.
	for index in range(5):
		var offset := float(index - 2) * 0.34
		var ray := (axis + side * offset).normalized()
		draw_line(center - axis * 4.0 + ray * 4.0, center + ray * (20.0 * expansion), Color(GOLD, fade), 2.2, true)
	draw_line(center - axis * 11.0 + side * 8.0, center + axis * 10.0 + side * 8.0, Color(WHITE, fade), 2.2, true)
	draw_line(center - axis * 11.0 - side * 8.0, center + axis * 10.0 - side * 8.0, Color(CYAN, fade), 2.2, true)

func _smooth(value: float) -> float:
	var t := clampf(value, 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)

func _ease_out(value: float) -> float:
	var t := clampf(value, 0.0, 1.0)
	return 1.0 - (1.0 - t) * (1.0 - t)
