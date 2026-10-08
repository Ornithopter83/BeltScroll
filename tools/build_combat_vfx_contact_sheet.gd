extends SceneTree
"""Builds a labeled synthetic composite of CombatImpact over Forest Ruins."""

const FOREST_PATH := "res://assets/art/stage/forest_ruins_v1_1920x1080.png"
const DEFAULT_OUTPUT := "res://assets/art/review/combat_vfx_contact_sheet.png"
const TILE_SIZE := Vector2i(480, 360)
const HEADER_HEIGHT := 78
const STAGES := 3
const DIRECTIONS := [Vector2.UP, Vector2.RIGHT, Vector2.DOWN, Vector2.LEFT]
const DIRECTION_NAMES := ["UP", "RIGHT", "DOWN", "LEFT"]
const GLYPHS := {
	"A": ["010", "101", "111", "101", "101"], "C": ["011", "100", "100", "100", "011"],
	"D": ["110", "101", "101", "101", "110"], "E": ["111", "100", "110", "100", "111"],
	"F": ["111", "100", "110", "100", "100"], "G": ["011", "100", "101", "101", "011"],
	"H": ["101", "101", "111", "101", "101"], "I": ["111", "010", "010", "010", "111"],
	"L": ["100", "100", "100", "100", "111"], "N": ["101", "111", "111", "111", "101"],
	"O": ["010", "101", "101", "101", "010"], "P": ["110", "101", "110", "100", "100"],
	"R": ["110", "101", "110", "101", "101"], "S": ["011", "100", "010", "001", "110"],
	"T": ["111", "010", "010", "010", "010"], "U": ["101", "101", "101", "101", "111"],
	"W": ["101", "101", "111", "111", "101"], "Y": ["101", "101", "010", "010", "010"],
	"1": ["010", "110", "010", "010", "111"], "2": ["110", "001", "010", "100", "111"],
	"3": ["110", "001", "010", "001", "110"], " ": ["000", "000", "000", "000", "000"],
}

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 1 or args.has("--help") or args.has("-h"):
		printerr("사용법: godot --headless --path . --script res://tools/build_combat_vfx_contact_sheet.gd [출력 PNG]")
		quit(0 if args.has("--help") or args.has("-h") else 2)
		return
	var output_path := _resolve_path(args[0] if not args.is_empty() else DEFAULT_OUTPUT)
	var forest := _load_png(_resolve_path(FOREST_PATH))
	if forest == null:
		printerr("Forest Ruins 배경 PNG를 읽지 못했습니다.")
		quit(1)
		return
	var canvas := Image.create(TILE_SIZE.x * DIRECTIONS.size(), HEADER_HEIGHT + TILE_SIZE.y * STAGES, false, Image.FORMAT_RGBA8)
	canvas.fill(Color("#121820"))
	var thumbnail := forest.duplicate()
	thumbnail.resize(TILE_SIZE.x, int(round(float(TILE_SIZE.x) * float(forest.get_height()) / float(forest.get_width()))), Image.INTERPOLATE_LANCZOS)
	for column in range(DIRECTIONS.size()):
		var x := column * TILE_SIZE.x
		canvas.fill_rect(Rect2i(x, 0, TILE_SIZE.x, HEADER_HEIGHT), Color("#273442"))
		_draw_text(canvas, Vector2i(x + 20, 25), DIRECTION_NAMES[column], Color("#f3d38a"), 4)
		for stage in range(1, STAGES + 1):
			var y := HEADER_HEIGHT + (stage - 1) * TILE_SIZE.y
			canvas.blend_rect(thumbnail, Rect2i(Vector2i.ZERO, thumbnail.get_size()), Vector2i(x, y))
			canvas.fill_rect(Rect2i(x, y + thumbnail.get_height(), TILE_SIZE.x, TILE_SIZE.y - thumbnail.get_height()), Color("#111820"))
			_draw_effect(canvas, Vector2(x + TILE_SIZE.x * 0.5, y + 145.0), stage, DIRECTIONS[column])
			canvas.fill_rect(Rect2i(x, y + 270, TILE_SIZE.x, 90), Color(0.035, 0.055, 0.075, 0.93))
			_draw_text(canvas, Vector2i(x + 20, y + 290), "STAGE " + str(stage), Color("#f3d38a"), 3)
			_draw_text(canvas, Vector2i(x + 20, y + 323), "SYNTHETIC", Color("#c7d6df"), 3)
			_draw_text(canvas, Vector2i(x + 280, y + 323), "NOT ENGINE", Color("#93a5b1"), 2)
			_draw_text(canvas, Vector2i(x + 280, y + 344), "CAPTURE", Color("#93a5b1"), 2)
			canvas.fill_rect(Rect2i(x, y + TILE_SIZE.y - 2, TILE_SIZE.x, 2), Color("#78aeb6"))
	var output_dir := output_path.get_base_dir()
	if not DirAccess.dir_exists_absolute(output_dir):
		var dir_error := DirAccess.make_dir_recursive_absolute(output_dir)
		if dir_error != OK:
			printerr("출력 디렉터리 생성 실패: %s" % error_string(dir_error))
			quit(1)
			return
	var error := canvas.save_png(output_path)
	if error != OK:
		printerr("접촉 시트 저장 실패: %s" % error_string(error))
		quit(1)
		return
	print("combat_vfx_contact_sheet: synthetic composite saved: %s (%dx%d)" % [output_path, canvas.get_width(), canvas.get_height()])
	quit(0)

func _draw_effect(image: Image, origin: Vector2, stage: int, attack_direction: Vector2) -> void:
	var local_direction := Vector2.UP
	var rotation_angle := attack_direction.angle() + PI * 0.5
	var radius: float = [19.0, 30.0, 38.0][stage - 1]
	var width: float = [3.0, 4.0, 5.0][stage - 1]
	var streak_length: float = [15.0, 23.0, 31.0][stage - 1]
	var start_angle := -0.85 * PI
	var end_angle := -0.15 * PI
	if stage == 2:
		start_angle = -0.98 * PI
		end_angle = -0.02 * PI
	elif stage == 3:
		start_angle = 0.65 * PI
		end_angle = 1.65 * PI
	var arc_color := Color(1.0, 0.91, 0.63, 0.92) if stage < 3 else Color(1.0, 0.79, 0.42, 1.0)
	var steps := 32
	for point in range(steps):
		var t0 := float(point) / steps
		var t1 := float(point + 1) / steps
		var a0 := start_angle + (end_angle - start_angle) * t0
		var a1 := start_angle + (end_angle - start_angle) * t1
		var p0: Vector2 = Vector2(cos(a0), sin(a0)) * radius
		var p1: Vector2 = Vector2(cos(a1), sin(a1)) * radius
		_draw_line(image, origin + p0.rotated(rotation_angle), origin + p1.rotated(rotation_angle), arc_color, width)
	var streak_count := 2 if stage == 1 else 3
	var perpendicular := local_direction.orthogonal()
	for index in range(streak_count):
		var offset := float(index) - float(streak_count - 1) * 0.5
		var begin_local: Vector2 = local_direction * (radius * (0.38 + absf(offset) * 0.08)) + perpendicular * offset * 5.0
		var end_local: Vector2 = begin_local - local_direction * streak_length - perpendicular * offset * 2.0
		var streak_color := Color(1.0, 0.98, 0.84, 0.82 if index == 0 else 0.57)
		_draw_line(image, origin + begin_local.rotated(rotation_angle), origin + end_local.rotated(rotation_angle), streak_color, maxf(1.0, width * 0.55))

func _draw_line(image: Image, from: Vector2, to: Vector2, color: Color, thickness: float) -> void:
	var distance := from.distance_to(to)
	var samples := maxi(1, int(ceil(distance * 1.5)))
	var radius := maxf(0.5, thickness * 0.5)
	for sample in range(samples + 1):
		var point := from.lerp(to, float(sample) / samples)
		var left := maxi(0, int(floor(point.x - radius)))
		var right := mini(image.get_width() - 1, int(ceil(point.x + radius)))
		var top := maxi(0, int(floor(point.y - radius)))
		var bottom := mini(image.get_height() - 1, int(ceil(point.y + radius)))
		for py in range(top, bottom + 1):
			for px in range(left, right + 1):
				if Vector2(px + 0.5, py + 0.5).distance_to(point) <= radius:
					image.set_pixel(px, py, _over(image.get_pixel(px, py), color))

func _over(background: Color, foreground: Color) -> Color:
	var alpha := foreground.a + background.a * (1.0 - foreground.a)
	if alpha <= 0.0001:
		return Color(0.0, 0.0, 0.0, 0.0)
	var rgb := (Vector3(foreground.r, foreground.g, foreground.b) * foreground.a + Vector3(background.r, background.g, background.b) * background.a * (1.0 - foreground.a)) / alpha
	return Color(rgb.x, rgb.y, rgb.z, alpha)

func _draw_text(image: Image, position: Vector2i, value: String, color: Color, scale: int) -> void:
	var cursor_x := position.x
	for character in value:
		var glyph: Array = GLYPHS.get(character, GLYPHS[" "])
		for row in range(glyph.size()):
			var bits: String = glyph[row]
			for column in range(bits.length()):
				if bits.substr(column, 1) == "1":
					image.fill_rect(Rect2i(cursor_x + column * scale, position.y + row * scale, scale, scale), color)
		cursor_x += 4 * scale

func _load_png(path: String) -> Image:
	if not FileAccess.file_exists(path):
		return null
	var image := Image.new()
	if image.load_png_from_buffer(FileAccess.get_file_as_bytes(path)) != OK or image.is_empty():
		return null
	if image.get_format() != Image.FORMAT_RGBA8:
		image.convert(Image.FORMAT_RGBA8)
	return image

func _resolve_path(path: String) -> String:
	if path.begins_with("res://") or path.begins_with("user://"):
		return ProjectSettings.globalize_path(path)
	if path.is_absolute_path():
		return path
	return ProjectSettings.globalize_path("res://" + path)
