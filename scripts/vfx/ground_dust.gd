extends Node2D

const LIFETIME := 0.48
const DUST_COLOR := Color(0.39, 0.30, 0.20, 0.27)
const LEAF_COLORS := [Color(0.30, 0.34, 0.15, 0.78), Color(0.42, 0.36, 0.16, 0.72)]

var elapsed := 0.0
var is_landing := false
var dust_particles: Array[Dictionary] = []
var leaves: Array[Dictionary] = []

func configure(landing: bool, seed_value: int = 0) -> void:
	is_landing = landing
	var rng := RandomNumberGenerator.new()
	if seed_value == 0:
		rng.randomize()
	else:
		rng.seed = seed_value
	var dust_count := 7 if is_landing else 5
	for index in range(dust_count):
		var direction := Vector2.from_angle(rng.randf_range(0.0, TAU))
		dust_particles.append({
			"origin": Vector2(rng.randf_range(-3.0, 3.0), rng.randf_range(-1.5, 1.5)),
			"drift": direction * rng.randf_range(5.0, 13.0) + Vector2(0.0, -rng.randf_range(1.0, 4.0)),
			"radius": rng.randf_range(1.5, 3.2),
			"phase": rng.randf_range(0.0, 0.18),
		})
	var leaf_count := rng.randi_range(1, 2) if is_landing else 1
	for index in range(leaf_count):
		var direction := Vector2.from_angle(rng.randf_range(0.0, TAU))
		leaves.append({
			"origin": Vector2(rng.randf_range(-3.0, 3.0), rng.randf_range(-1.5, 1.5)),
			"drift": direction * rng.randf_range(8.0, 16.0) + Vector2(0.0, -rng.randf_range(2.0, 6.0)),
			"size": rng.randf_range(2.0, 3.2),
			"rotation": rng.randf_range(-1.0, 1.0),
			"spin": rng.randf_range(-3.5, 3.5),
			"color": LEAF_COLORS[rng.randi_range(0, LEAF_COLORS.size() - 1)],
			"phase": rng.randf_range(0.0, 0.1),
		})
	queue_redraw()

func _process(delta: float) -> void:
	elapsed += delta
	if elapsed >= LIFETIME:
		queue_free()
		return
	queue_redraw()

func _draw() -> void:
	var life_ratio := clampf(1.0 - elapsed / LIFETIME, 0.0, 1.0)
	for particle in dust_particles:
		var age_ratio: float = clampf((elapsed - particle["phase"]) / LIFETIME, 0.0, 1.0)
		if age_ratio <= 0.0:
			continue
		var center: Vector2 = particle["origin"] + particle["drift"] * age_ratio
		var radius: float = float(particle["radius"]) * (0.7 + age_ratio * 0.45)
		var color := DUST_COLOR
		color.a *= life_ratio * (1.0 - age_ratio * 0.35)
		draw_circle(center, radius, color)
	for leaf in leaves:
		var age_ratio: float = clampf((elapsed - leaf["phase"]) / LIFETIME, 0.0, 1.0)
		if age_ratio <= 0.0:
			continue
		var center: Vector2 = leaf["origin"] + leaf["drift"] * age_ratio
		var size: float = float(leaf["size"])
		var leaf_color: Color = leaf["color"]
		leaf_color.a *= life_ratio
		var angle: float = float(leaf["rotation"]) + float(leaf["spin"]) * age_ratio
		var axis := Vector2(cos(angle), sin(angle)) * size
		var side := axis.orthogonal() * size * 0.38
		draw_colored_polygon(PackedVector2Array([center - axis, center + side, center + axis, center - side]), leaf_color)
