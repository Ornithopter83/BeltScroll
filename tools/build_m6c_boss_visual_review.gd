extends SceneTree
"""Builds a human review sheet for a Raider reference and optional boss candidate."""

const DEFAULT_REFERENCE := "res://assets/art/enemies/forest_raider_reference_v1_final_candidate_1254x1254.png"
const DEFAULT_CANDIDATE := "res://assets/art/enemies/ruins_warden_boss_v1_candidate_1254x1254.png"
const DEFAULT_OUTPUT := "res://assets/art/review/m6c_boss_visual_comparison.png"
const BOARD_SIZE := Vector2i(2000, 1000)
const GAME_DISPLAY_SCALE := 0.446928
const BOARD_DISPLAY_SCALE := GAME_DISPLAY_SCALE

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var options := _parse_args(OS.get_cmdline_user_args())
	if not options.ok:
		printerr(options.error)
		quit(2)
		return
	var reference := _load_image(options.reference)
	if reference == null:
		printerr("Raider 기준 원화를 읽을 수 없습니다: %s" % options.reference)
		quit(2)
		return
	var candidate: Image = null
	var candidate_path: String = options.candidate if not options.candidate.is_empty() else DEFAULT_CANDIDATE
	candidate = _load_image(candidate_path)
	if candidate == null:
		printerr("보스 후보 이미지를 읽을 수 없습니다: %s" % candidate_path)
		quit(2)
		return
	var report := inspect_images(reference, candidate)
	var board := build_review_board(reference, candidate, report, candidate_path)
	var output_path := ProjectSettings.globalize_path(options.output)
	var mkdir_error := DirAccess.make_dir_recursive_absolute(output_path.get_base_dir())
	if mkdir_error != OK and mkdir_error != ERR_ALREADY_EXISTS:
		printerr("출력 폴더 생성 실패: %s" % error_string(mkdir_error))
		quit(2)
		return
	var save_error := board.save_png(output_path)
	if save_error != OK:
		printerr("검수판 저장 실패: %s" % error_string(save_error))
		quit(2)
		return
	print_report(report, candidate_path, options.output)
	quit(0 if report.get("valid", false) else 1)

static func inspect_images(reference: Image, candidate: Image) -> Dictionary:
	var ref := inspect_one(reference)
	if candidate == null:
		return {"valid": true, "candidate_present": false, "reference": ref, "candidate": {}, "checks": [], "status": "CANDIDATE_MISSING"}
	var cand := inspect_one(candidate)
	var checks: Array[Dictionary] = []
	_add_check(checks, "candidate_rgba", candidate.get_format() == Image.FORMAT_RGBA8 or candidate.get_format() == Image.FORMAT_RGBAF or candidate.get_format() == Image.FORMAT_RGBAH, "Decoded format %d" % candidate.get_format())
	_add_check(checks, "candidate_alpha", cand.has_transparency, "Transparent pixels: %s" % ("yes" if cand.has_transparency else "no"))
	_add_check(checks, "candidate_margin", cand.has_alpha and cand.margin_min >= 8, "Clear margin %d px (need 8 px)" % cand.margin_min)
	_add_check(checks, "candidate_not_clipped", not cand.touches_edge, "Alpha touches canvas edge: %s" % ("yes" if cand.touches_edge else "no"))
	_add_check(checks, "reference_alpha", ref.has_alpha, "Raider alpha bounds %d x %d px" % [ref.bounds.size.x, ref.bounds.size.y])
	var height_ratio := float(cand.bounds.size.y) / maxf(1.0, float(ref.bounds.size.y)) if cand.has_alpha and ref.has_alpha else 0.0
	var width_ratio := float(cand.bounds.size.x) / maxf(1.0, float(ref.bounds.size.x)) if cand.has_alpha and ref.has_alpha else 0.0
	var ref_foot := _foot_anchor(reference, ref.bounds) if ref.has_alpha else Vector2i(-1, -1)
	var cand_foot := _foot_anchor(candidate, cand.bounds) if cand.has_alpha else Vector2i(-1, -1)
	var foot_delta := float(cand_foot.y - ref_foot.y) * GAME_DISPLAY_SCALE if cand.has_alpha and ref.has_alpha else INF
	var silhouette_iou := _silhouette_iou(reference, ref.bounds, candidate, cand.bounds) if cand.has_alpha and ref.has_alpha else 0.0
	_add_check(checks, "display_size", height_ratio >= 0.5 and height_ratio <= 2.0, "Scale %.3f; boss silhouette %.1f x %.1f px; vs Raider H %.3fx W %.3fx" % [GAME_DISPLAY_SCALE, cand.bounds.size.x * GAME_DISPLAY_SCALE, cand.bounds.size.y * GAME_DISPLAY_SCALE, height_ratio, width_ratio])
	_add_check(checks, "foot_anchor", absf(foot_delta) <= GAME_DISPLAY_SCALE * 8.0, "Foot anchor (%d,%d); delta from Raider %.1f display px" % [cand_foot.x, cand_foot.y, foot_delta])
	var face_delta := _region_color_delta(reference, ref.bounds, candidate, cand.bounds, Rect2(0.28, 0.08, 0.44, 0.32))
	var armor_delta := _region_color_delta(reference, ref.bounds, candidate, cand.bounds, Rect2(0.22, 0.34, 0.56, 0.42))
	_add_check(checks, "silhouette_similarity", silhouette_iou >= 0.45, "Normalized silhouette IoU %.3f" % silhouette_iou)
	_add_check(checks, "face_visual_delta", face_delta >= 0.0, "Face region mean RGB delta %.1f / 255" % face_delta)
	_add_check(checks, "armor_visual_delta", armor_delta >= 0.0, "Armor region mean RGB delta %.1f / 255" % armor_delta)
	var valid := true
	for check in checks:
		valid = valid and check.ok
	return {"valid": valid, "candidate_present": true, "reference": ref, "candidate": cand, "checks": checks, "status": "PASS" if valid else "REVIEW_REQUIRED", "height_ratio": height_ratio, "width_ratio": width_ratio, "foot_delta": foot_delta, "reference_foot": ref_foot, "candidate_foot": cand_foot, "silhouette_iou": silhouette_iou, "face_delta": face_delta, "armor_delta": armor_delta}

static func inspect_one(image: Image) -> Dictionary:
	if image == null or image.is_empty():
		return {"width": 0, "height": 0, "bounds": Rect2i(), "has_alpha": false, "has_transparency": false, "touches_edge": false, "margin_min": 0}
	var w := image.get_width()
	var h := image.get_height()
	var min_x := w
	var min_y := h
	var max_x := -1
	var max_y := -1
	var alpha_min_x := w
	var alpha_min_y := h
	var alpha_max_x := -1
	var alpha_max_y := -1
	var transparent := false
	for y in range(h):
		for x in range(w):
			var color := image.get_pixel(x, y)
			if color.a < 0.999:
				transparent = true
			if color.a > 0.05:
				min_x = mini(min_x, x)
				min_y = mini(min_y, y)
				max_x = maxi(max_x, x)
				max_y = maxi(max_y, y)
			if color.a >= 0.999:
				alpha_min_x = mini(alpha_min_x, x)
				alpha_min_y = mini(alpha_min_y, y)
				alpha_max_x = maxi(alpha_max_x, x)
				alpha_max_y = maxi(alpha_max_y, y)
	var has := max_x >= min_x and max_y >= min_y
	var bounds := Rect2i(min_x, min_y, max_x - min_x + 1, max_y - min_y + 1) if has else Rect2i()
	var touches := has and (min_x == 0 or min_y == 0 or max_x == w - 1 or max_y == h - 1)
	var margin := mini(mini(min_x, min_y), mini(w - max_x - 1, h - max_y - 1)) if has else 0
	return {"width": w, "height": h, "bounds": bounds, "has_alpha": has, "has_transparency": transparent, "touches_edge": touches, "margin_min": margin, "opaque_bounds": Rect2i(alpha_min_x, alpha_min_y, alpha_max_x - alpha_min_x + 1, alpha_max_y - alpha_min_y + 1) if alpha_max_x >= alpha_min_x else Rect2i()}

static func build_review_board(reference: Image, candidate: Image, report: Dictionary, candidate_path: String = "") -> Image:
	var board := Image.create(BOARD_SIZE.x, BOARD_SIZE.y, false, Image.FORMAT_RGBA8)
	board.fill(Color("#171d25"))
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Arial", "Noto Sans CJK KR"])
	_draw_text(board, font, "M6C BOSS VISUAL REVIEW", Vector2i(28, 48), 30, Color("#edf3f8"))
	_draw_text(board, font, "Raider reference vs boss candidate  |  independent review only", Vector2i(28, 80), 17, Color("#aebdca"))
	_draw_panel(board, Rect2i(24, 104, 630, 790), "RAIDER | LIVE GAME SCALE", reference, report.reference, font, Color("#5aa9dc"))
	if report.candidate_present:
		_draw_panel(board, Rect2i(685, 104, 630, 790), "RUINS WARDEN | SAME SCALE", candidate, report.candidate, font, Color("#efa955"))
		var overlay := _make_overlay(reference, report.reference.bounds, candidate, report.candidate.bounds)
		_draw_panel(board, Rect2i(1346, 104, 630, 790), "SILHOUETTE OVERLAY", overlay, {"bounds": Rect2i(0, 0, overlay.get_width(), overlay.get_height())}, font, Color("#a88ee8"))
	else:
		_draw_text(board, font, "NO CANDIDATE", Vector2i(700, 145), 24, Color("#ffcf72"))
	_draw_report(board, font, report, candidate_path)
	_draw_text(board, font, "Human visual approval required · candidate is not registered in gameplay scenes", Vector2i(28, 950), 17, Color("#ffcf72"))
	_draw_text(board, font, "Sprite2D scale 0.446928 from forest_raider.tscn; both images use identical source-pixel scale", Vector2i(28, 920), 14, Color("#aebdca"))
	return board

static func _draw_panel(board: Image, rect: Rect2i, title: String, source: Image, metrics: Dictionary, font: Font, accent: Color) -> void:
	board.fill_rect(rect, Color("#222b35"))
	_draw_text(board, font, title, Vector2i(rect.position.x + 14, rect.position.y + 29), 18, accent)
	var image_rect := Rect2i(rect.position.x + 22, rect.position.y + 46, rect.size.x - 44, 570)
	_draw_checker(board, image_rect)
	_draw_text(board, font, "%d x %d px" % [source.get_width(), source.get_height()], Vector2i(rect.position.x + 14, rect.end.y - 44), 14, Color("#c4d0da"))
	var bounds: Rect2i = metrics.get("bounds", Rect2i())
	if bounds.size.x <= 0 or bounds.size.y <= 0:
		return
	var cropped := source.get_region(bounds)
	var rendered_size := Vector2i(roundi(cropped.get_width() * BOARD_DISPLAY_SCALE), roundi(cropped.get_height() * BOARD_DISPLAY_SCALE))
	var resized := cropped.duplicate()
	resized.resize(rendered_size.x, rendered_size.y, Image.INTERPOLATE_LANCZOS)
	var target := Vector2i(image_rect.position.x + (image_rect.size.x - rendered_size.x) / 2, image_rect.end.y - rendered_size.y - 30)
	board.blend_rect(resized, Rect2i(Vector2i.ZERO, resized.get_size()), target)
	var baseline_y := image_rect.end.y - 21
	board.fill_rect(Rect2i(image_rect.position.x + 8, baseline_y, image_rect.size.x - 16, 2), Color("#82c88f"))
	board.fill_rect(Rect2i(image_rect.position.x + image_rect.size.x / 2 - 1, image_rect.position.y + 8, 2, image_rect.size.y - 16), Color(0.7, 0.8, 0.9, 0.16))

static func _draw_report(board: Image, font: Font, report: Dictionary, candidate_path: String) -> void:
	var y := 756
	_draw_text(board, font, "CHECK SUMMARY", Vector2i(1360, y), 19, Color("#edf3f8"))
	y += 28
	if not report.candidate_present:
		_draw_text(board, font, "CANDIDATE ABSENT — reference only", Vector2i(1360, y), 15, Color("#ffcf72"))
		return
	var source_text := "SOURCE: RUINS WARDEN BOSS V1 CANDIDATE 1254X1254"
	_draw_text(board, font, source_text, Vector2i(1360, y), 12, Color("#c4d0da"))
	y += 21
	for check in report.checks:
		var color := Color("#80d39a") if check.ok else Color("#ff8585")
		var text_value: String = ("PASS  " if check.ok else "CHECK ") + check.detail
		var lines := _wrap_text(text_value, 70)
		for line in lines:
			_draw_text(board, font, line, Vector2i(1360, y), 12, color)
			y += 15

static func _wrap_text(value: String, max_chars: int) -> PackedStringArray:
	var lines := PackedStringArray()
	var current := ""
	for word in value.split(" "):
		if not current.is_empty() and current.length() + 1 + word.length() > max_chars:
			lines.append(current)
			current = word
		else:
			current = word if current.is_empty() else current + " " + word
	if not current.is_empty():
		lines.append(current)
	return lines

static func _make_overlay(reference: Image, ref_bounds: Rect2i, candidate: Image, cand_bounds: Rect2i) -> Image:
	var ref_size := ref_bounds.size
	var cand_size := cand_bounds.size
	var size := Vector2i(maxi(ref_size.x, cand_size.x) + 24, maxi(ref_size.y, cand_size.y) + 16)
	var overlay := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	overlay.fill(Color(0, 0, 0, 0))
	var ref_crop := reference.get_region(ref_bounds)
	var cand_crop := candidate.get_region(cand_bounds)
	var ref_x := (size.x - ref_size.x) / 2
	var cand_x := (size.x - cand_size.x) / 2
	var ref_y := size.y - ref_size.y
	var cand_y := size.y - cand_size.y
	for y in range(size.y):
		for x in range(size.x):
			var a := ref_crop.get_pixel(x - ref_x, y - ref_y).a if x >= ref_x and y >= ref_y and x < ref_x + ref_size.x and y < ref_y + ref_size.y else 0.0
			var b := cand_crop.get_pixel(x - cand_x, y - cand_y).a if x >= cand_x and y >= cand_y and x < cand_x + cand_size.x and y < cand_y + cand_size.y else 0.0
			if a > 0.05 and b > 0.05:
				overlay.set_pixel(x, y, Color("#df5d65"))
			elif a > 0.05:
				overlay.set_pixel(x, y, Color("#56b8ff"))
			elif b > 0.05:
				overlay.set_pixel(x, y, Color("#ffbd55"))
	return overlay

static func _foot_anchor(image: Image, bounds: Rect2i) -> Vector2i:
	for y in range(bounds.end.y - 1, bounds.position.y - 1, -1):
		var left := image.get_width()
		var right := -1
		for x in range(bounds.position.x, bounds.end.x):
			if image.get_pixel(x, y).a > 0.05:
				left = mini(left, x)
				right = maxi(right, x)
		if right >= left:
			return Vector2i(roundi((left + right) * 0.5), y)
	return Vector2i(-1, -1)

static func _silhouette_iou(a: Image, a_bounds: Rect2i, b: Image, b_bounds: Rect2i) -> float:
	var side := 64
	var intersection := 0
	var union := 0
	for y in range(side):
		for x in range(side):
			var ax := a_bounds.position.x + int((float(x) + 0.5) / side * a_bounds.size.x)
			var ay := a_bounds.position.y + int((float(y) + 0.5) / side * a_bounds.size.y)
			var bx := b_bounds.position.x + int((float(x) + 0.5) / side * b_bounds.size.x)
			var by := b_bounds.position.y + int((float(y) + 0.5) / side * b_bounds.size.y)
			var ia := a.get_pixel(mini(ax, a.get_width() - 1), mini(ay, a.get_height() - 1)).a > 0.05
			var ib := b.get_pixel(mini(bx, b.get_width() - 1), mini(by, b.get_height() - 1)).a > 0.05
			if ia and ib: intersection += 1
			if ia or ib: union += 1
	return float(intersection) / maxf(1.0, float(union))

static func _region_color_delta(a: Image, ab: Rect2i, b: Image, bb: Rect2i, region: Rect2) -> float:
	var total := 0.0
	var count := 0
	for iy in range(16):
		for ix in range(16):
			var u := region.position.x + (float(ix) + 0.5) / 16.0 * region.size.x
			var v := region.position.y + (float(iy) + 0.5) / 16.0 * region.size.y
			var ac := a.get_pixel(clampi(ab.position.x + int(u * ab.size.x), 0, a.get_width() - 1), clampi(ab.position.y + int(v * ab.size.y), 0, a.get_height() - 1))
			var bc := b.get_pixel(clampi(bb.position.x + int(u * bb.size.x), 0, b.get_width() - 1), clampi(bb.position.y + int(v * bb.size.y), 0, b.get_height() - 1))
			if ac.a > 0.05 or bc.a > 0.05:
				total += (absf(ac.r - bc.r) + absf(ac.g - bc.g) + absf(ac.b - bc.b)) / 3.0
				count += 1
	return total / maxf(1.0, float(count)) * 255.0

static func _draw_checker(image: Image, rect: Rect2i) -> void:
	for y in range(rect.position.y, rect.end.y, 16):
		for x in range(rect.position.x, rect.end.x, 16):
			var even := ((x - rect.position.x) / 16 + (y - rect.position.y) / 16) % 2 == 0
			image.fill_rect(Rect2i(x, y, mini(16, rect.end.x - x), mini(16, rect.end.y - y)), Color("#37424d") if even else Color("#2d3741"))

static func _fit(source: Image, box: Vector2i) -> Vector2i:
	var scale := minf(float(box.x) / source.get_width(), float(box.y) / source.get_height())
	return Vector2i(maxi(1, int(source.get_width() * scale)), maxi(1, int(source.get_height() * scale)))

static func _draw_text(image: Image, font: Font, value: String, position: Vector2i, size: int, color: Color) -> void:
	var glyphs := _bitmap_glyphs()
	var scale := maxi(1, size / 8)
	var cursor_x := position.x
	for character in value.to_upper():
		if character == " ":
			cursor_x += 4 * scale
			continue
		var rows: PackedStringArray = glyphs.get(character, glyphs["?"])
		for row in range(rows.size()):
			for column in range(rows[row].length()):
				if rows[row][column] == "1":
					image.fill_rect(Rect2i(cursor_x + column * scale, position.y + row * scale, scale, scale), color)
		cursor_x += 6 * scale

static func _bitmap_glyphs() -> Dictionary:
	return {
		"A": ["01110", "10001", "10001", "11111", "10001", "10001", "10001"], "B": ["11110", "10001", "10001", "11110", "10001", "10001", "11110"],
		"C": ["01111", "10000", "10000", "10000", "10000", "10000", "01111"], "D": ["11110", "10001", "10001", "10001", "10001", "10001", "11110"],
		"E": ["11111", "10000", "10000", "11110", "10000", "10000", "11111"], "F": ["11111", "10000", "10000", "11110", "10000", "10000", "10000"],
		"G": ["01111", "10000", "10000", "10111", "10001", "10001", "01111"], "H": ["10001", "10001", "10001", "11111", "10001", "10001", "10001"],
		"I": ["11111", "00100", "00100", "00100", "00100", "00100", "11111"], "J": ["00111", "00010", "00010", "00010", "10010", "10010", "01100"],
		"K": ["10001", "10010", "10100", "11000", "10100", "10010", "10001"], "L": ["10000", "10000", "10000", "10000", "10000", "10000", "11111"],
		"M": ["10001", "11011", "10101", "10101", "10001", "10001", "10001"], "N": ["10001", "11001", "10101", "10011", "10001", "10001", "10001"],
		"O": ["01110", "10001", "10001", "10001", "10001", "10001", "01110"], "P": ["11110", "10001", "10001", "11110", "10000", "10000", "10000"],
		"Q": ["01110", "10001", "10001", "10001", "10101", "10010", "01101"], "R": ["11110", "10001", "10001", "11110", "10100", "10010", "10001"],
		"S": ["01111", "10000", "10000", "01110", "00001", "00001", "11110"], "T": ["11111", "00100", "00100", "00100", "00100", "00100", "00100"],
		"U": ["10001", "10001", "10001", "10001", "10001", "10001", "01110"], "V": ["10001", "10001", "10001", "10001", "10001", "01010", "00100"],
		"W": ["10001", "10001", "10001", "10101", "10101", "10101", "01010"], "X": ["10001", "10001", "01010", "00100", "01010", "10001", "10001"],
		"Y": ["10001", "10001", "01010", "00100", "00100", "00100", "00100"], "Z": ["11111", "00001", "00010", "00100", "01000", "10000", "11111"],
		"0": ["01110", "10001", "10011", "10101", "11001", "10001", "01110"], "1": ["00100", "01100", "00100", "00100", "00100", "00100", "01110"],
		"2": ["01110", "10001", "00001", "00010", "00100", "01000", "11111"], "3": ["11110", "00001", "00001", "01110", "00001", "00001", "11110"],
		"4": ["00010", "00110", "01010", "10010", "11111", "00010", "00010"], "5": ["11111", "10000", "10000", "11110", "00001", "00001", "11110"],
		"6": ["01110", "10000", "10000", "11110", "10001", "10001", "01110"], "7": ["11111", "00001", "00010", "00100", "01000", "01000", "01000"],
		"8": ["01110", "10001", "10001", "01110", "10001", "10001", "01110"], "9": ["01110", "10001", "10001", "01111", "00001", "00001", "01110"],
		"-": ["00000", "00000", "00000", "11111", "00000", "00000", "00000"], ".": ["00000", "00000", "00000", "00000", "00000", "00110", "00110"],
		":": ["00000", "00110", "00110", "00000", "00110", "00110", "00000"], "/": ["00001", "00010", "00010", "00100", "01000", "01000", "10000"],
		"%": ["11001", "11010", "00100", "01000", "10110", "00110", "00000"], "(": ["00010", "00100", "01000", "01000", "01000", "00100", "00010"],
		")": ["01000", "00100", "00010", "00010", "00010", "00100", "01000"], ",": ["00000", "00000", "00000", "00000", "00110", "00110", "00100"],
		"|": ["00100", "00100", "00100", "00100", "00100", "00100", "00100"], "?": ["01110", "10001", "00001", "00010", "00100", "00000", "00100"]
	}

static func _add_check(checks: Array[Dictionary], name: String, ok: bool, detail: String) -> void:
	checks.append({"name": name, "ok": ok, "detail": detail})

static func _load_image(path: String) -> Image:
	var global_path := ProjectSettings.globalize_path(path) if path.begins_with("res://") else path
	var image := Image.new()
	return image if image.load(global_path) == OK else null

static func _parse_args(args: PackedStringArray) -> Dictionary:
	var result := {"ok": true, "reference": DEFAULT_REFERENCE, "candidate": "", "output": DEFAULT_OUTPUT, "error": ""}
	var i := 0
	while i < args.size():
		var key := args[i]
		if key in ["--reference", "--candidate", "--output"]:
			if i + 1 >= args.size():
				return {"ok": false, "error": "인수 값 누락: %s" % key}
			i += 1
			if key == "--reference": result.reference = args[i]
			elif key == "--candidate": result.candidate = args[i]
			else: result.output = args[i]
		else:
			return {"ok": false, "error": "알 수 없는 인수: %s" % key}
		i += 1
	return result

static func print_report(report: Dictionary, candidate_path: String, output: String) -> void:
	print("comparison: %s" % output)
	if not report.candidate_present:
		print("candidate: absent (RESOURCE 후보 미발견; 기준 원화만으로 검수판 생성)")
		return
	print("candidate: %s" % candidate_path)
	for check in report.checks:
		print("%s %s: %s" % ["PASS" if check.ok else "REVIEW", check.name, check.detail])
	print("status: %s (person approval required; no production scene is modified)" % report.status)
