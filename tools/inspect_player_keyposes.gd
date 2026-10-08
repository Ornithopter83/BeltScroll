extends SceneTree

const DEFAULT_REFERENCE := "res://assets/art/player/elven_fighter_reference_v8_clean_candidate_1254x1254.png"
const DEFAULT_OUTPUT := "res://assets/art/review/player_keyposes_v2_contact.png"
const DISPLAY_SIZE := 192
const CONTACT_SIZE := Vector2i(832, 576)
const PANEL_SIZE := Vector2i(400, 264)

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var parsed := _parse_args(args)
	if not parsed["ok"]:
		printerr(parsed["message"])
		quit(2)
		return
	var options: Dictionary = parsed["options"]
	var reference := _load_png(options["reference"])
	if reference == null:
		printerr("v8 비교 원화를 읽을 수 없습니다: %s" % options["reference"])
		quit(2)
		return
	var input: Image = _load_png(options["input"]) if not options["input"].is_empty() else null
	if not options["input"].is_empty() and input == null:
		printerr("입력 PNG를 읽을 수 없습니다: %s" % options["input"])
		quit(2)
		return
	var report := inspect_image(input, options["anchors"], options["margin"], options["tolerance"])
	var output_path: String = ProjectSettings.globalize_path(options["output"])
	var contact := build_contact_sheet(input, reference, report)
	var dir_error := DirAccess.make_dir_recursive_absolute(output_path.get_base_dir())
	if dir_error != OK and dir_error != ERR_ALREADY_EXISTS:
		printerr("출력 폴더를 만들 수 없습니다: %s" % error_string(dir_error))
		quit(2)
		return
	var save_error := contact.save_png(output_path)
	if save_error != OK:
		printerr("contact sheet 저장 실패: %s" % error_string(save_error))
		quit(2)
		return
	print_report(report)
	print("contact sheet: %s" % options["output"])
	quit(exit_code_for(report))

static func inspect_image(sheet: Image, anchors: Array[int] = [], margin: int = 2, foot_tolerance: int = 2) -> Dictionary:
	var checks: Array[Dictionary] = []
	if sheet == null or sheet.is_empty():
		_add_check(checks, "input_missing", false, "입력 시트 없음")
		return {"valid": false, "checks": checks, "cells": [], "failure_codes": ["INPUT_MISSING"], "cell_size": Vector2i.ZERO}
	var dimensions_ok := sheet.get_width() > 0 and sheet.get_height() > 0 and sheet.get_width() == sheet.get_height() and sheet.get_width() % 2 == 0
	_add_check(checks, "dimensions", dimensions_ok, "%d×%d, 정사각형 2×2 균등 분할%s" % [sheet.get_width(), sheet.get_height(), "" if dimensions_ok else " 필요"])
	var cell_w := sheet.get_width() / 2
	var cell_h := sheet.get_height() / 2
	var cells: Array[Dictionary] = []
	if not dimensions_ok:
		return {"valid": false, "checks": checks, "cells": cells, "failure_codes": ["INVALID_DIMENSIONS"], "cell_size": Vector2i(cell_w, cell_h)}
	var all_valid := true
	var observed_feet: Array[int] = []
	for index in range(4):
		var rect := Rect2i((index % 2) * cell_w, (index / 2) * cell_h, cell_w, cell_h)
		var cell := sheet.get_region(rect)
		var cell_checks: Array[Dictionary] = []
		var size_ok := cell.get_width() == cell.get_height() and cell.get_width() > 0
		_add_check(cell_checks, "cell_size", size_ok, "실제 셀 %d×%dpx" % [cell_w, cell_h])
		var bounds := _alpha_bounds(cell)
		var has_alpha := bounds.size.x > 0 and bounds.size.y > 0
		_add_check(cell_checks, "alpha_bounds", has_alpha, "투명도 5%% 이상 경계 %s" % str(bounds))
		var touches_edge := has_alpha and (bounds.position.x == 0 or bounds.position.y == 0 or bounds.end.x >= cell_w or bounds.end.y >= cell_h)
		_add_check(cell_checks, "cell_intrusion", not touches_edge, "셀 외곽 alpha 접촉=%s" % str(touches_edge))
		var inset_ok := has_alpha and bounds.position.x >= margin and bounds.position.y >= margin and cell_w - bounds.end.x >= margin and cell_h - bounds.end.y >= margin
		_add_check(cell_checks, "alpha_margin", inset_ok, "최소 여백 %dpx, 실제 경계 %s" % [margin, str(bounds)])
		var clipped := has_alpha and (bounds.position.x == 0 or bounds.position.y == 0 or bounds.end.x >= cell_w or bounds.end.y >= cell_h)
		_add_check(cell_checks, "clipping", not clipped, "셀 경계 잘림 징후=%s" % str(clipped))
		var foot_y := bounds.end.y - 1 if has_alpha else -1
		observed_feet.append(foot_y)
		var foot_ok := has_alpha
		var foot_detail := "alpha 최하단 y=%d" % foot_y
		if anchors.size() == 4:
			foot_ok = has_alpha and abs(foot_y - anchors[index]) <= foot_tolerance
			foot_detail = "기준선 y=%d, 예상 y=%d, 허용 오차 %d" % [foot_y, anchors[index], foot_tolerance]
		_add_check(cell_checks, "foot_anchor", foot_ok, foot_detail)
		for check in cell_checks:
			all_valid = all_valid and check["ok"]
		cells.append({"index": index, "rect": rect, "bounds": bounds, "foot_y": foot_y, "checks": cell_checks, "valid": _checks_pass(cell_checks)})
	if anchors.is_empty() and observed_feet.size() == 4 and observed_feet.min() >= 0:
		var spread: int = observed_feet.max() - observed_feet.min()
		var feet_ok := spread <= foot_tolerance
		_add_check(checks, "foot_baseline_alignment", feet_ok, "네 셀 최하단 편차 %dpx (허용 %dpx); 명시 anchor로 셀별 지정 가능" % [spread, foot_tolerance])
		all_valid = all_valid and feet_ok
	for cell_result in cells:
		all_valid = all_valid and cell_result["valid"]
	var result := {"valid": all_valid, "checks": checks, "cells": cells, "cell_size": Vector2i(cell_w, cell_h)}
	result["failure_codes"] = _failure_codes(result)
	return result

static func _failure_codes(report: Dictionary) -> Array[String]:
	var codes: Array[String] = []
	for check in report.get("checks", []):
		if not check["ok"]:
			_append_failure_code(codes, "FOOT_BASELINE_ERROR" if check["name"] == "foot_baseline_alignment" else "INVALID_DIMENSIONS")
	for cell in report.get("cells", []):
		for check in cell["checks"]:
			if check["ok"]:
				continue
			match check["name"]:
				"cell_intrusion", "clipping": _append_failure_code(codes, "GRID_INTRUSION")
				"foot_anchor": _append_failure_code(codes, "FOOT_BASELINE_ERROR")
				"cell_size": _append_failure_code(codes, "INVALID_DIMENSIONS")
				"alpha_bounds": _append_failure_code(codes, "NO_ALPHA")
				_: _append_failure_code(codes, "ALPHA_MARGIN_ERROR")
	return codes

static func _append_failure_code(codes: Array[String], code: String) -> void:
	if not codes.has(code):
		codes.append(code)

static func exit_code_for(report: Dictionary) -> int:
	return 0 if report.get("valid", false) else 1

static func build_contact_sheet(sheet: Image, reference: Image, report: Dictionary) -> Image:
	var canvas := Image.create(CONTACT_SIZE.x, CONTACT_SIZE.y, false, Image.FORMAT_RGBA8)
	canvas.fill(Color("#20252b"))
	var ref := _resize_to_box(_alpha_crop(reference), Vector2i(DISPLAY_SIZE, DISPLAY_SIZE))
	for i in range(4):
		var col := i % 2
		var row := i / 2
		var origin := Vector2i(12 + col * (PANEL_SIZE.x + 8), 12 + row * (PANEL_SIZE.y + 8))
		var source_rect := Rect2i(origin, PANEL_SIZE)
		_draw_checker(canvas, source_rect)
		var gutter_x := origin.x + 8
		var top_y := origin.y + 34
		var left_label := "POSE %d" % (i + 1)
		var right_label := "V8 CLEAN"
		_draw_label(canvas, left_label, Vector2i(gutter_x, origin.y + 23), Color("#dce3e8"))
		_draw_label(canvas, right_label, Vector2i(gutter_x + 196, origin.y + 23), Color("#dce3e8"))
		canvas.fill_rect(Rect2i(origin.x + 7, top_y + DISPLAY_SIZE, PANEL_SIZE.x - 14, 1), Color("#7e8993"))
		var ref_pos := Vector2i(origin.x + 204, top_y)
		canvas.blend_rect(ref, Rect2i(Vector2i.ZERO, ref.get_size()), ref_pos)
		if sheet != null and sheet.get_width() % 2 == 0 and sheet.get_height() % 2 == 0:
			var cell_rect := Rect2i((i % 2) * sheet.get_width() / 2, (i / 2) * sheet.get_height() / 2, sheet.get_width() / 2, sheet.get_height() / 2)
			var cell := sheet.get_region(cell_rect)
			if not cell.is_empty():
				var cell_bounds := _alpha_bounds(cell)
				if cell_bounds.size.x > 0:
					var cropped := cell.get_region(cell_bounds)
					var fitted := _resize_to_box(cropped, Vector2i(DISPLAY_SIZE, DISPLAY_SIZE))
					canvas.blend_rect(fitted, Rect2i(Vector2i.ZERO, fitted.get_size()), Vector2i(origin.x + 8 + (DISPLAY_SIZE - fitted.get_width()) / 2, top_y + (DISPLAY_SIZE - fitted.get_height()) / 2))
			else:
				canvas.fill_rect(Rect2i(origin.x + 8, top_y, DISPLAY_SIZE, DISPLAY_SIZE), Color("#39434c"))
		else:
			canvas.fill_rect(Rect2i(origin.x + 8, top_y, DISPLAY_SIZE, DISPLAY_SIZE), Color("#39434c"))
		canvas.fill_rect(Rect2i(origin.x + 7, origin.y + PANEL_SIZE.y - 26, PANEL_SIZE.x - 14, 18), Color("#303941"))
		var state := "PENDING" if sheet == null else ("PASS" if report.get("valid", false) else "FAIL")
		_draw_label(canvas, state, Vector2i(origin.x + 12, origin.y + PANEL_SIZE.y - 12), Color("#91d7a5") if state == "PASS" else Color("#f3bd70"))
	return canvas

static func print_report(report: Dictionary) -> void:
	var failure_codes: Array = report.get("failure_codes", [])
	if not failure_codes.is_empty():
		print("FAILURE_CODES: %s" % ",".join(failure_codes))
	for check in report.get("checks", []):
		print("%s %s: %s" % ["PASS" if check["ok"] else "FAIL", check["name"], check["detail"]])
	for cell in report.get("cells", []):
		for check in cell["checks"]:
			print("%s cell_%d_%s: %s" % ["PASS" if check["ok"] else "FAIL", cell["index"] + 1, check["name"], check["detail"]])

static func _parse_args(args: PackedStringArray) -> Dictionary:
	var result := {"ok": false, "message": "사용법: godot --headless --path . --script res://tools/inspect_player_keyposes.gd -- [입력.png] [--reference v8_clean.png] [--output contact.png] [--margin px] [--foot-tolerance px] [--foot-anchors y1,y2,y3,y4]", "options": {"input": "", "reference": DEFAULT_REFERENCE, "output": DEFAULT_OUTPUT, "margin": 2, "tolerance": 2, "anchors": [] as Array[int]}}
	var options: Dictionary = result["options"]
	var i := 0
	while i < args.size():
		var token := args[i]
		if token == "--help" or token == "-h":
			result["ok"] = false
			return result
		if token.begins_with("--"):
			if i + 1 >= args.size():
				result["message"] = "옵션 값이 없습니다: %s" % token
				return result
			i += 1
			var value := args[i]
			match token:
				"--reference": options["reference"] = _resolve_path(value)
				"--output": options["output"] = _resolve_path(value)
				"--margin":
					if not value.is_valid_int() or int(value) < 0:
						result["message"] = "--margin은 0 이상의 정수여야 합니다."
						return result
					options["margin"] = int(value)
				"--foot-tolerance":
					if not value.is_valid_int() or int(value) < 0:
						result["message"] = "--foot-tolerance는 0 이상의 정수여야 합니다."
						return result
					options["tolerance"] = int(value)
				"--foot-anchors":
					var tokens := value.split(",")
					if tokens.size() != 4:
						result["message"] = "--foot-anchors에는 셀별 y 정수 네 개가 필요합니다."
						return result
					for anchor in tokens:
						if not anchor.is_valid_int():
							result["message"] = "--foot-anchors 값은 모두 정수여야 합니다."
							return result
						options["anchors"].append(int(anchor))
				_:
					result["message"] = "알 수 없는 옵션: %s" % token
					return result
		else:
			if not options["input"].is_empty():
				result["message"] = "입력 PNG는 하나만 지정할 수 있습니다."
				return result
			options["input"] = _resolve_path(token)
		i += 1
	result["ok"] = true
	return result

static func _load_png(path: String) -> Image:
	var absolute := ProjectSettings.globalize_path(path)
	if not FileAccess.file_exists(absolute):
		return null
	var bytes := FileAccess.get_file_as_bytes(absolute)
	# PNG IHDR color types 4 (gray+alpha) and 6 (RGBA) carry an alpha channel.
	if bytes.size() < 26 or bytes[25] not in [4, 6]:
		return null
	var image := Image.new()
	if image.load_png_from_buffer(bytes) != OK or image.is_empty():
		return null
	if image.get_format() != Image.FORMAT_RGBA8:
		image.convert(Image.FORMAT_RGBA8)
	return image

static func _alpha_bounds(image: Image) -> Rect2i:
	var min_x := image.get_width()
	var min_y := image.get_height()
	var max_x := -1
	var max_y := -1
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			if image.get_pixel(x, y).a >= 0.05:
				min_x = mini(min_x, x)
				min_y = mini(min_y, y)
				max_x = maxi(max_x, x)
				max_y = maxi(max_y, y)
	return Rect2i(min_x, min_y, max_x - min_x + 1, max_y - min_y + 1) if max_x >= min_x else Rect2i()

static func _alpha_crop(image: Image) -> Image:
	if image == null or image.is_empty():
		var blank := Image.create(DISPLAY_SIZE, DISPLAY_SIZE, false, Image.FORMAT_RGBA8)
		blank.fill(Color.TRANSPARENT)
		return blank
	var bounds := _alpha_bounds(image)
	return image.get_region(bounds) if bounds.size.x > 0 else image.duplicate()

static func _resize_to_box(source: Image, box: Vector2i) -> Image:
	var result := Image.create(box.x, box.y, false, Image.FORMAT_RGBA8)
	result.fill(Color.TRANSPARENT)
	if source == null or source.is_empty():
		return result
	var scale := minf(float(box.x) / source.get_width(), float(box.y) / source.get_height())
	var size := Vector2i(maxi(1, int(round(source.get_width() * scale))), maxi(1, int(round(source.get_height() * scale))))
	var scaled := source.duplicate()
	scaled.resize(size.x, size.y, Image.INTERPOLATE_LANCZOS)
	result.blend_rect(scaled, Rect2i(Vector2i.ZERO, size), (box - size) / 2)
	return result

static func _draw_checker(image: Image, rect: Rect2i) -> void:
	var tile := 16
	for y in range(rect.position.y, rect.end.y, tile):
		for x in range(rect.position.x, rect.end.x, tile):
			var shade := Color("#92999f") if ((x - rect.position.x) / tile + (y - rect.position.y) / tile) % 2 == 0 else Color("#c1c6ca")
			image.fill_rect(Rect2i(x, y, mini(tile, rect.end.x - x), mini(tile, rect.end.y - y)), shade)

static func _draw_label(image: Image, label: String, position: Vector2i, color: Color) -> void:
	var glyphs := {
		"A": ["010", "101", "111", "101", "101"], "B": ["110", "101", "110", "101", "110"],
		"C": ["011", "100", "100", "100", "011"], "D": ["110", "101", "101", "101", "110"],
		"E": ["111", "100", "110", "100", "111"], "F": ["111", "100", "110", "100", "100"],
		"I": ["111", "010", "010", "010", "111"], "L": ["100", "100", "100", "100", "111"],
		"N": ["101", "111", "111", "111", "101"], "O": ["111", "101", "101", "101", "111"],
		"P": ["110", "101", "110", "100", "100"], "S": ["011", "100", "010", "001", "110"],
		"T": ["111", "010", "010", "010", "010"], "V": ["101", "101", "101", "101", "010"],
		"X": ["101", "101", "010", "101", "101"], "G": ["011", "100", "101", "101", "011"],
		"1": ["010", "110", "010", "010", "111"], "2": ["110", "001", "010", "100", "111"],
		"8": ["111", "101", "111", "101", "111"], "9": ["111", "101", "111", "001", "110"]
	}
	var cursor := position.x
	for character in label:
		if glyphs.has(character):
			var rows: Array = glyphs[character]
			for y in range(rows.size()):
				for x in range(rows[y].length()):
					if rows[y].substr(x, 1) == "1":
						image.fill_rect(Rect2i(cursor + x * 2, position.y - 10 + y * 2, 2, 2), color)
		cursor += 8

static func _add_check(checks: Array[Dictionary], name: String, ok: bool, detail: String) -> void:
	checks.append({"name": name, "ok": ok, "detail": detail})

static func _checks_pass(checks: Array[Dictionary]) -> bool:
	for check in checks:
		if not check["ok"]:
			return false
	return true

static func _resolve_path(path: String) -> String:
	if path.begins_with("res://") or path.begins_with("user://") or path.is_absolute_path():
		return path
	return "res://" + path
